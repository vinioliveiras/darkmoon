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
  } finally {
    lib.libraw_close(lr);
  }
}

/// Fully decodes/demosaics a RAW file into an RGB bitmap — the actual
/// editable image, not just the camera's embedded preview.
///
/// Mirrors the Python app's `raw.postprocess(use_camera_wb=True,
/// output_bps=8, half_size=...)`: only white balance, bit depth and
/// half-size are overridden, everything else (demosaic algorithm, color
/// space, auto-brightness, ...) is left at LibRaw's defaults so behavior
/// matches. `user_flip = -1` is set explicitly (rather than relying on
/// LibRaw's own default) so orientation always comes from the file's EXIF
/// data, the same fix applied on the Python side.
///
/// [halfSize] skips full demosaicing — much faster, and still comfortably
/// above a 1600px editing preview for most cameras. Set to false for a
/// full-resolution decode (e.g. for export).
///
/// Blocking native call — run on a background isolate (e.g. via `compute`).
RawImage? decodeRawImage(String path, {bool halfSize = true}) {
  final lib = _Lib.instance;
  final lr = _openRaw(lib, path);
  if (lr == null) {
    return null;
  }
  try {
    if (lib.libraw_unpack(lr) != 0) {
      return null;
    }

    final params = lr.ref.params;
    params.use_camera_wb = 1;
    params.output_bps = 8;
    // half_size does a crude 2x2-block average instead of real demosaicing.
    // That's a fine trade for speed on standard Bayer sensors, but Fujifilm
    // X-Trans sensors use a 6x6 color filter pattern (LibRaw's `filters ==
    // 9` sentinel) that doesn't reduce to 2x2 blocks — half_size produces
    // visible false-color (red/green) noise on those. Fall back to a full
    // demosaic for X-Trans even though it's much slower (seconds instead of
    // well under a second).
    final isXTrans = lr.ref.idata.filters == 9;
    params.half_size = (halfSize && !isXTrans) ? 1 : 0;
    params.user_flip = -1;

    if (lib.libraw_dcraw_process(lr) != 0) {
      return null;
    }

    final errPtr = malloc<Int>();
    try {
      final image = lib.libraw_dcraw_make_mem_image(lr, errPtr);
      if (image == nullptr) {
        return null;
      }
      try {
        if (image.ref.type != LibRaw_image_formats.LIBRAW_IMAGE_BITMAP || image.ref.colors != 3) {
          return null;
        }
        return RawImage(
          width: image.ref.width,
          height: image.ref.height,
          rgbBytes: _copyProcessedImageData(image),
        );
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
