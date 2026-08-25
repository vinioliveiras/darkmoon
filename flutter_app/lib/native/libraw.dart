import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'libraw_bindings.dart';

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
    );
  } finally {
    lib.libraw_close(lr);
  }
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
