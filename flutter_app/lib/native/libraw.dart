import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../render/white_balance.dart' show wbMultipliersToKelvinTint;
import 'libraw_bindings.dart';

/// LibRaw (this file) vs. RapidRAW's own decoder (Rawler, a pure-Rust RAW
/// library) — investigated as part of trying to match RapidRAW's tonal
/// pipeline pixel-for-pixel (see render.dart/color_mixer.dart/dehaze.dart's
/// own doc comments for the adjustment-level ports). The short version:
/// **RAW decode is the one part of this pipeline that can't realistically
/// be made to match** — not a specific bug to fix, a different library
/// with its own demosaic algorithm, denoising, and highlight handling.
/// Two differences matter most for anyone chasing pixel parity downstream:
///
/// 1. **Output precision/color-space.** [decodeRawImage] below explicitly
///    sets `params.output_bps = 8` and a real sRGB gamma
///    (`params.gamm = [1/2.4, 12.92]`), so LibRaw hands back gamma-encoded
///    8-bit-per-channel bytes — which is *why* every adjustment ported
///    from RapidRAW elsewhere in this codebase has to convert back to
///    linear internally (`srgbToLinear`/`linearToSrgb`) before doing its
///    own math, then re-encode afterward. RapidRAW's Rust decoder
///    (`raw_processing.rs`'s `develop_internal`) does the opposite: it
///    explicitly *strips* the sRGB-encode step from Rawler's own develop
///    pipeline (`developer.steps.retain(|&step| step != ProcessingStep::
///    SRgb)`) and keeps the whole image as 32-bit-float scene-linear data
///    all the way through its render pipeline, only gamma-encoding once,
///    right before display/export. That's a real precision ceiling this
///    app's decode stage puts under every downstream fix: once a shadow
///    tone has been quantized into one of 8-bit gamma's few distinct
///    near-black levels, no amount of "operate on linear values" in a
///    later adjustment recovers detail that quantization already
///    discarded — a difference no per-adjustment port can undo.
///
/// 2. **The demosaic/highlight-recovery algorithms themselves differ.**
///    LibRaw here uses linear interpolation for [fastPreview] (a real
///    demosaic, not `half_size`'s box average — see that param's own
///    comment) or its own AHD-class default otherwise, plus blend-mode
///    highlight reconstruction (`params.highlight = 2`). RapidRAW's
///    `raw_processing.rs` sets `DemosaicAlgorithm::Speed` for its own fast
///    path and otherwise leaves Rawler's own default algorithm (a
///    different, unrelated implementation — Rawler is vendored as a
///    crates.io dependency, not in this checkout, so its exact algorithm
///    name isn't derivable from here), plus its own highlight-compression
///    formula (`raw_processing.rs`'s `safe_highlight_compression`
///    blend). Both use the camera's own embedded white balance and color
///    calibration matrix (LibRaw: `use_camera_wb`/`use_camera_matrix`;
///    Rawler: `raw_image.wb_coeffs`/`ProcessingStep::Calibrate`) — that
///    part is conceptually aligned even if the exact matrix math isn't
///    verified to be numerically identical.
///
/// **Practical takeaway**: pixel-identical output between the two apps is
/// only achievable, if at all, by feeding both the *same already-decoded*
/// RGB buffer (e.g. compare a step further down the pipeline, not from a
/// RAW file), or by replacing this decoder with Rawler outright — a much
/// larger, separate undertaking (new native/FFI story entirely, since
/// Rawler is Rust, not a C library like LibRaw) than any adjustment-level
/// port. Matching RapidRAW's math for each slider (as the rest of this
/// codebase's ports do) gets the *relative* effect of each adjustment
/// right; it can't erase the baseline difference the decoder itself
/// already introduced before any slider runs.

/// A fully decoded/demosaiced RAW image: packed 8-bit RGB, row-major, no
/// padding — 3 bytes per pixel, matching libraw_dcraw_make_mem_image's
/// default (non-TIFF) output.
class RawImage {
  RawImage({required this.width, required this.height, required this.rgbBytes});

  final int width;
  final int height;
  final Uint8List rgbBytes;
}

class _Lib {
  static LibRawBindings? _instance;

  static LibRawBindings get instance => _instance ??= LibRawBindings(_load());

  static DynamicLibrary _load() {
    if (Platform.isWindows) {
      // Installed next to the executable by windows/CMakeLists.txt.
      return DynamicLibrary.open('raw_r.dll');
    }
    throw UnsupportedError('LibRaw is only wired up for Windows so far.');
  }
}

// Header fields of libraw_processed_image_t that precede its trailing
// `unsigned char data[]` flexible array member:
// enum(4) + ushort height/width/colors/bits(2*4) + uint data_size(4) = 16.
// (Verified against libraw_types.h; ffigen represents the flexible array as
// a 1-element Array, so this can't be derived from sizeOf() automatically.)
const int _processedImageHeaderSize = 16;

Uint8List _copyProcessedImageData(Pointer<libraw_processed_image_t> image) {
  final dataPtr = image.cast<Uint8>() + _processedImageHeaderSize;
  return Uint8List.fromList(dataPtr.asTypedList(image.ref.data_size));
}

/// Camera/exposure metadata read straight from a RAW file's own header —
/// no demosaic/decode needed, so this is far cheaper than
/// [decodeRawImage] or even [extractRawThumbnailJpeg].
class RawMetadata {
  const RawMetadata({
    required this.cameraMake,
    required this.cameraModel,
    required this.lensModel,
    required this.isoSpeed,
    required this.shutterSeconds,
    required this.apertureFNumber,
    required this.focalLengthMm,
    required this.width,
    required this.height,
    this.asShotKelvin = 5500,
    this.asShotTint = 0,
  });

  /// Manufacturer-normalized names (e.g. "Fujifilm" rather than a
  /// per-model raw string), matching what a Lightroom-style metadata panel
  /// shows — empty string if LibRaw couldn't identify the camera.
  final String cameraMake;
  final String cameraModel;

  /// Empty string if the file carries no lens data (older/manual lenses,
  /// or a camera model LibRaw doesn't parse lens info for).
  final String lensModel;

  /// 0 if absent from the file.
  final double isoSpeed;

  /// Exposure time in seconds (e.g. 0.004 for "1/250") — 0 if absent.
  final double shutterSeconds;

  /// f-number (e.g. 2.8 for "f/2.8") — 0 if absent.
  final double apertureFNumber;

  /// 0 if absent.
  final double focalLengthMm;

  /// The final image's pixel dimensions — already flip/rotation-adjusted
  /// the same way [decodeRawImage]'s actual output is (LibRaw's own
  /// `sizes.iwidth`/`iheight`, not the pre-flip `sizes.width`/`height`),
  /// so this is exactly what exporting at 100% would produce. Read from
  /// the same header-only LibRaw open this whole class is extracted from
  /// — no extra decode cost. Backs the export dialog's "Rapid export"
  /// resolution slider preview.
  final int width;
  final int height;

  /// The camera's own as-shot white balance, approximated from LibRaw's
  /// `cam_mul`/`cam_xyz` (see `wbMultipliersToKelvinTint`). Defaults to
  /// 5500 K / 0 tint when the file carries no usable camera multipliers.
  /// Used as the neutral reference for the White Balance sliders — at
  /// these values the render leaves the (already camera-WB'd) decode
  /// untouched.
  final double asShotKelvin;
  final double asShotTint;
}

/// Reads a null-terminated `Array<Char>` field as a Dart string, stopping
/// at the first NUL byte (or the array's own length, whichever comes
/// first) rather than assuming the whole fixed-size buffer is meaningful.
String _charArrayToString(Array<Char> array, int maxLength) {
  final bytes = <int>[];
  for (var i = 0; i < maxLength; i++) {
    final b = array[i];
    if (b == 0) {
      break;
    }
    bytes.add(b);
  }
  return String.fromCharCodes(bytes).trim();
}

/// Reads camera/lens/exposure metadata from [path]'s RAW header — cheap
/// (no unpack/demosaic), since LibRaw parses this during file open alone.
/// Returns null if LibRaw fails to open the file.
///
/// Blocking native call — run on a background isolate (e.g. via `compute`).
RawMetadata? extractRawMetadata(String path) {
  final lib = _Lib.instance;
  final lr = _openRaw(lib, path);
  if (lr == null) {
    return null;
  }
  try {
    final idata = lr.ref.idata;
    final other = lr.ref.other;
    final lens = lr.ref.lens;
    final sizes = lr.ref.sizes;
    final color = lr.ref.color;
    final camMul = <double>[
      color.cam_mul[0],
      color.cam_mul[1],
      color.cam_mul[2],
      color.cam_mul[3],
    ];
    final camXyz = <List<double>>[
      for (var i = 0; i < 3; i++)
        [color.cam_xyz[i][0], color.cam_xyz[i][1], color.cam_xyz[i][2]],
    ];
    final asShot = wbMultipliersToKelvinTint(
      camMul,
      camXyz: camXyz,
      wbctCoeffs: _wbctRows(lr),
    );
    return RawMetadata(
      cameraMake: _charArrayToString(idata.normalized_make, 64),
      cameraModel: _charArrayToString(idata.normalized_model, 64),
      lensModel: _charArrayToString(lens.Lens, 128),
      isoSpeed: other.iso_speed,
      shutterSeconds: other.shutter,
      apertureFNumber: other.aperture,
      focalLengthMm: other.focal_len,
      width: sizes.iwidth,
      height: sizes.iheight,
      asShotKelvin: asShot.kelvin,
      asShotTint: asShot.tint,
    );
  } finally {
    lib.libraw_close(lr);
  }
}

/// Just the as-shot `cam_mul` for [path] (or null). Cheap — header-only
/// open. Used by `tool/wb_scan.dart` to locate a file by its multipliers.
List<double>? readCamMul(String path) {
  final lib = _Lib.instance;
  final lr = _openRaw(lib, path);
  if (lr == null) {
    return null;
  }
  try {
    final c = lr.ref.color;
    return [c.cam_mul[0], c.cam_mul[1], c.cam_mul[2], c.cam_mul[3]];
  } finally {
    lib.libraw_close(lr);
  }
}

/// Diagnostic dump of everything LibRaw exposes about [path]'s white
/// balance — `cam_mul`, `pre_mul`, the WBCT colour-temperature table, the
/// named-illuminant `WB_Coeffs` presets and `cam_xyz` — plus what
/// [wbMultipliersToKelvinTint] makes of it. Used by `tool/wb_dump.dart` to
/// calibrate the as-shot Kelvin/Tint estimate against Lightroom.
String dumpRawWhiteBalanceInfo(String path) {
  final lib = _Lib.instance;
  final lr = _openRaw(lib, path);
  if (lr == null) {
    return 'LibRaw failed to open $path';
  }
  try {
    final color = lr.ref.color;
    final idata = lr.ref.idata;
    final camMul = [for (var i = 0; i < 4; i++) color.cam_mul[i].toDouble()];
    final camXyz = [
      for (var i = 0; i < 3; i++)
        [for (var j = 0; j < 3; j++) color.cam_xyz[i][j].toDouble()],
    ];
    final wbct = _wbctRows(lr);
    final est = wbMultipliersToKelvinTint(
      camMul,
      camXyz: camXyz,
      wbctCoeffs: wbct,
    );
    final b = StringBuffer();
    // Essentials first — terminals truncate long output.
    b.writeln(
      '${_charArrayToString(idata.normalized_make, 64)} '
      '${_charArrayToString(idata.normalized_model, 64)}',
    );
    b.writeln('cam_mul  : ${[for (var i = 0; i < 4; i++) color.cam_mul[i]]}');
    b.writeln('pre_mul  : ${[for (var i = 0; i < 4; i++) color.pre_mul[i]]}');
    b.writeln('as_shot_wb_applied: ${color.as_shot_wb_applied}');
    b.writeln(
      '=> estimated as-shot: ${est.kelvin.round()} K / '
      'tint ${est.tint.toStringAsFixed(1)}',
    );
    b.writeln('WB_Coeffs presets (index: m0..m3):');
    const names = {
      1: 'Daylight',
      2: 'Fluorescent',
      3: 'Tungsten',
      4: 'Flash',
      9: 'FineWeather',
      10: 'Cloudy',
      11: 'Shade',
      17: 'IllA(Tungsten2856K)',
      20: 'D55',
      21: 'D65',
      23: 'D50',
    };
    names.forEach((idx, name) {
      final row = [for (var j = 0; j < 4; j++) color.WB_Coeffs[idx][j]];
      if (row.any((v) => v != 0)) {
        b.writeln('  $name ($idx): $row');
      }
    });
    b.writeln('cam_xyz  :');
    for (var i = 0; i < 4; i++) {
      b.writeln('  ${[for (var j = 0; j < 3; j++) color.cam_xyz[i][j]]}');
    }
    b.writeln('WBCT_Coeffs (kelvin, m0..m3):');
    for (var i = 0; i < 64; i++) {
      final k = color.WBCT_Coeffs[i][0];
      if (k <= 0) break;
      b.writeln('  ${[for (var j = 0; j < 5; j++) color.WBCT_Coeffs[i][j]]}');
    }
    return b.toString();
  } finally {
    lib.libraw_close(lr);
  }
}

/// The camera's own colour-temperature table (`color.WBCT_Coeffs`) as
/// `[kelvin, m0..m3]` rows, up to the terminating zero-kelvin row.
List<List<double>> _wbctRows(Pointer<libraw_data_t> lr) {
  final t = lr.ref.color.WBCT_Coeffs;
  final rows = <List<double>>[];
  for (var i = 0; i < 64; i++) {
    final k = t[i][0];
    if (k <= 0) {
      break;
    }
    rows.add([k, t[i][1], t[i][2], t[i][3], t[i][4]]);
  }
  return rows;
}

/// Opens [path], returning an initialized `libraw_data_t*`, or null (after
/// freeing it) if LibRaw fails to open the file. Caller owns the result and
/// must eventually call `lib.libraw_close`.
Pointer<libraw_data_t>? _openRaw(LibRawBindings lib, String path) {
  final lr = lib.libraw_init(0);
  if (lr == nullptr) {
    return null;
  }
  final pathPtr = path.toNativeUtf16();
  try {
    if (lib.libraw_open_wfile(lr, pathPtr.cast()) != 0) {
      lib.libraw_close(lr);
      return null;
    }
  } finally {
    malloc.free(pathPtr);
  }
  return lr;
}

/// Extracts the embedded preview/thumbnail JPEG bytes from a RAW file.
/// Returns null if the file has no thumbnail, the thumbnail isn't
/// JPEG-encoded (bitmap-type embedded thumbnails aren't handled), or
/// LibRaw fails to open/read the file.
///
/// Blocking native call — run on a background isolate (e.g. via `compute`).
Uint8List? extractRawThumbnailJpeg(String path) {
  final lib = _Lib.instance;
  final lr = _openRaw(lib, path);
  if (lr == null) {
    return null;
  }
  try {
    return _extractThumbJpeg(lib, lr);
  } finally {
    lib.libraw_close(lr);
  }
}

/// The actual thumbnail-extraction logic behind [extractRawThumbnailJpeg].
Uint8List? _extractThumbJpeg(LibRawBindings lib, Pointer<libraw_data_t> lr) {
  if (lib.libraw_unpack_thumb(lr) != 0) {
    return null;
  }
  final errPtr = malloc<Int>();
  try {
    final image = lib.libraw_dcraw_make_mem_thumb(lr, errPtr);
    if (image == nullptr) {
      return null;
    }
    try {
      if (image.ref.type != LibRaw_image_formats.LIBRAW_IMAGE_JPEG) {
        return null;
      }
      return _copyProcessedImageData(image);
    } finally {
      lib.libraw_dcraw_clear_mem(image);
    }
  } finally {
    malloc.free(errPtr);
  }
}

/// The coarse stages [decodeRawImage] moves through — LibRaw's C API
/// exposes no fractional progress callback, so this is the finest-grained
/// signal available: one message per stage boundary, not a percentage
/// within a stage.
enum RawDecodeStage { opening, unpacking, processing, extracting }

/// Fully decodes/demosaics a RAW file into an RGB bitmap — the actual
/// editable image, not just the camera's embedded preview.
///
/// Started from the Python app's `raw.postprocess(use_camera_wb=True,
/// output_bps=8, half_size=...)`, but no longer matches it exactly: three
/// params LibRaw's own defaults left sub-optimal for how this app actually
/// uses the output (see each param's own comment below for why) are now
/// set explicitly rather than left alone. `user_flip = -1` is set
/// explicitly (rather than relying on LibRaw's own default) so orientation
/// always comes from the file's EXIF data, the same fix applied on the
/// Python side.
///
/// [fastPreview] trades demosaic quality for speed — still a real
/// per-pixel demosaic, never LibRaw's `half_size` box-average (see
/// `params.half_size` below for why that path was removed entirely).
/// [decodeEditSources] downscales to [previewMaxDimension] right after
/// this returns, so the extra fidelity a slow algorithm buys is mostly
/// lost anyway; set to false for a full-resolution, full-quality decode
/// (export, or the opt-in full-quality view).
///
/// [onStage], if given, is called synchronously as each [RawDecodeStage]
/// starts — a coarse progress signal for callers that want to show more
/// than an indeterminate spinner (see `edit_source.dart`'s isolate-based
/// wrappers, which forward these across a `SendPort`).
///
/// Blocking native call — run on a background isolate (e.g. via `compute`).
RawImage? decodeRawImage(
  String path, {
  bool fastPreview = true,
  void Function(RawDecodeStage stage)? onStage,
}) {
  onStage?.call(RawDecodeStage.opening);
  final lib = _Lib.instance;
  final lr = _openRaw(lib, path);
  if (lr == null) {
    return null;
  }
  try {
    onStage?.call(RawDecodeStage.unpacking);
    if (lib.libraw_unpack(lr) != 0) {
      return null;
    }

    // Every param set below that affects the resulting pixels (not just
    // speed/quality) is covered by raw_decode_format_version.dart's
    // rawDecodeFormatVersion — bump that constant when changing one, so
    // the on-disk preview/native-source caches start fresh instead of
    // silently serving pixels decoded under the old params.
    final params = lr.ref.params;
    params.use_camera_wb = 1;
    // Use the camera's own embedded color calibration matrix (written into
    // the RAW file by the manufacturer for that specific sensor) instead
    // of LibRaw's generic per-sensor-family fallback matrix. This is the
    // biggest lever available here toward "the app recognizes the camera
    // and adjusts color like Lightroom does": Lightroom/ACR ship their own
    // per-camera-model calibration profiles, which aren't available to
    // LibRaw, but every RAW file's own manufacturer-embedded matrix is —
    // using it noticeably closes the color gap for supported cameras
    // versus falling back to a generic matrix.
    params.use_camera_matrix = 1;
    params.output_bps = 8;
    // half_size did a crude 2x2-block average instead of real demosaicing:
    // fast, but visibly flatter/more aliased than a real interpolation —
    // apps like RapidRAW/Vitrine never show a box-averaged decode, even
    // for their fastest preview. Always demosaic properly; [fastPreview]
    // controls speed via user_qual below instead.
    params.half_size = 0;
    // Fujifilm X-Trans sensors use a 6x6 color filter pattern (LibRaw's
    // `filters == 9` sentinel) that isn't compatible with the fast linear
    // algorithm below — forcing user_qual=0 on X-Trans produces visible
    // false-color noise, so leave user_qual at LibRaw's own (X-Trans-aware)
    // default for those regardless of [fastPreview].
    final isXTrans = lr.ref.idata.filters == 9;
    if (fastPreview && !isXTrans) {
      // Linear interpolation: the fastest real demosaic LibRaw offers,
      // still far cleaner than half_size's box average. LibRaw's own
      // default (user_qual left at -1) resolves to a slower
      // higher-quality algorithm (AHD-class), used here for the
      // full-quality path below since its extra cost is worth paying when
      // not immediately downscaled.
      params.user_qual = 0;
    }
    // LibRaw's own default gamma (2.222 power / 4.5 toe-slope, dcraw's
    // historical Rec.709-ish curve) is already close to sRGB but not
    // exact. Match the real sRGB transfer function instead, same choice
    // Vitrine makes explicitly (`-g 2.4 12.92` in its dcraw_emu call).
    params.gamm[0] = 1.0 / 2.4;
    params.gamm[1] = 12.92;
    // LibRaw's default (0) hard-clips blown highlights to white. Blend
    // reconstruction (2) recovers detail from the channels that aren't
    // clipped instead, closer to how RapidRAW/Vitrine and Lightroom-style
    // tools handle overexposed regions by default.
    params.highlight = 2;
    // REVERTED (2nd time) 2026-08-29 — see the "_colorProfileEnabled off
    // again" note in editor_screen.dart and project_darkmoon_color_profile
    // .md. no_auto_bright = 1 only makes sense paired with a working
    // "darkmoon Color" tone curve (color_profile.dart) to bring the
    // exposure back — without it every RAW renders dark. Keep this in
    // lockstep with _colorProfileEnabled; both back on together, next
    // time, once the profile actually holds up under real use.
    params.user_flip = -1;

    onStage?.call(RawDecodeStage.processing);
    if (lib.libraw_dcraw_process(lr) != 0) {
      return null;
    }

    onStage?.call(RawDecodeStage.extracting);
    final errPtr = malloc<Int>();
    try {
      final image = lib.libraw_dcraw_make_mem_image(lr, errPtr);
      if (image == nullptr) {
        return null;
      }
      try {
        if (image.ref.type != LibRaw_image_formats.LIBRAW_IMAGE_BITMAP ||
            image.ref.colors != 3) {
          return null;
        }
        final width = image.ref.width;
        final height = image.ref.height;
        final rgbBytes = _copyProcessedImageData(image);
        // applyCameraMatch (nudging toward the camera's own embedded JPEG
        // rendering — see its doc comment) is deliberately NOT applied
        // here: comparing LibRaw's demosaic against a Fuji-JPEG-engine
        // rendering (its own film-simulation color science, not a neutral
        // reference) reliably introduced a yellow/green cast and amplified
        // noise/clipping instead of correcting anything — confirmed by
        // comparing real presets side-by-side against Lightroom. LibRaw's
        // own use_camera_wb + use_camera_matrix calibration (set when
        // opening the file, above) is the actual camera-profile-based
        // color science and needs no such nudge.
        return RawImage(width: width, height: height, rgbBytes: rgbBytes);
      } finally {
        lib.libraw_dcraw_clear_mem(image);
      }
    } finally {
      malloc.free(errPtr);
    }
  } finally {
    lib.libraw_close(lr);
  }
}
