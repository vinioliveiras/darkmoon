import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Minimal Dart FFI bindings to LibRaw, covering only what's needed to pull
/// the embedded preview/thumbnail JPEG out of a RAW file. Full pixel
/// decoding (libraw_data_t internals, demosaicing, ...) isn't wired up —
/// this deliberately treats `libraw_data_t*` as an opaque handle so we never
/// have to replicate its (large, version-sensitive) struct layout.
///
/// Struct/function signatures verified against LibRaw's public headers
/// (libraw/libraw_types.h, libraw/libraw.h, libraw/libraw_const.h) on
/// 2026-08-16. `libraw_processed_image_t` is a small, stable, flat struct by
/// design, specifically so bindings like this one can rely on it:
///
/// ```c
/// typedef struct {
///   enum LibRaw_image_formats type; // int-sized enum
///   ushort height, width, colors, bits;
///   unsigned int data_size;
///   unsigned char data[1]; // flexible array member, not part of the Dart struct
/// } libraw_processed_image_t;
/// ```

const int _libRawImageJpeg = 1;

final class _LibRawProcessedImage extends Struct {
  @Int32()
  external int type;
  @Uint16()
  external int height;
  @Uint16()
  external int width;
  @Uint16()
  external int colors;
  @Uint16()
  external int bits;
  @Uint32()
  external int dataSize;
}

typedef _InitNative = Pointer<Void> Function(Uint32 flags);
typedef _InitDart = Pointer<Void> Function(int flags);

typedef _OpenWFileNative = Int32 Function(Pointer<Void> lr, Pointer<Utf16> fname);
typedef _OpenWFileDart = int Function(Pointer<Void> lr, Pointer<Utf16> fname);

typedef _UnpackThumbNative = Int32 Function(Pointer<Void> lr);
typedef _UnpackThumbDart = int Function(Pointer<Void> lr);

typedef _MakeMemThumbNative =
    Pointer<_LibRawProcessedImage> Function(Pointer<Void> lr, Pointer<Int32> errc);
typedef _MakeMemThumbDart =
    Pointer<_LibRawProcessedImage> Function(Pointer<Void> lr, Pointer<Int32> errc);

typedef _ClearMemNative = Void Function(Pointer<_LibRawProcessedImage> img);
typedef _ClearMemDart = void Function(Pointer<_LibRawProcessedImage> img);

typedef _CloseNative = Void Function(Pointer<Void> lr);
typedef _CloseDart = void Function(Pointer<Void> lr);

class _LibRaw {
  _LibRaw._(DynamicLibrary lib)
    : init = lib.lookupFunction<_InitNative, _InitDart>('libraw_init'),
      openWFile = lib.lookupFunction<_OpenWFileNative, _OpenWFileDart>('libraw_open_wfile'),
      unpackThumb = lib.lookupFunction<_UnpackThumbNative, _UnpackThumbDart>('libraw_unpack_thumb'),
      makeMemThumb = lib.lookupFunction<_MakeMemThumbNative, _MakeMemThumbDart>(
        'libraw_dcraw_make_mem_thumb',
      ),
      clearMem = lib.lookupFunction<_ClearMemNative, _ClearMemDart>('libraw_dcraw_clear_mem'),
      close = lib.lookupFunction<_CloseNative, _CloseDart>('libraw_close');

  final _InitDart init;
  final _OpenWFileDart openWFile;
  final _UnpackThumbDart unpackThumb;
  final _MakeMemThumbDart makeMemThumb;
  final _ClearMemDart clearMem;
  final _CloseDart close;

  static _LibRaw? _instance;

  static _LibRaw get instance => _instance ??= _LibRaw._(_load());

  static DynamicLibrary _load() {
    if (Platform.isWindows) {
      // Installed next to the executable by windows/CMakeLists.txt.
      return DynamicLibrary.open('raw_r.dll');
    }
    throw UnsupportedError('RAW thumbnail extraction is only wired up for Windows so far.');
  }
}

/// Extracts the embedded preview/thumbnail JPEG bytes from a RAW file.
/// Returns null if the file has no thumbnail, the thumbnail isn't
/// JPEG-encoded (rare — bitmap-type embedded thumbnails aren't handled
/// yet), or LibRaw fails to open/read the file.
///
/// This makes a blocking native call and should be run on a background
/// isolate (e.g. via `compute`), not the UI isolate.
Uint8List? extractRawThumbnailJpeg(String path) {
  final libraw = _LibRaw.instance;
  final lr = libraw.init(0);
  if (lr == nullptr) {
    return null;
  }
  try {
    final pathPtr = path.toNativeUtf16();
    int openResult;
    try {
      openResult = libraw.openWFile(lr, pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
    if (openResult != 0) {
      return null;
    }

    if (libraw.unpackThumb(lr) != 0) {
      return null;
    }

    final errPtr = malloc<Int32>();
    try {
      final image = libraw.makeMemThumb(lr, errPtr);
      if (image == nullptr) {
        return null;
      }
      try {
        if (image.ref.type != _libRawImageJpeg) {
          return null;
        }
        final dataPtr = image.cast<Uint8>() + sizeOf<_LibRawProcessedImage>();
        return Uint8List.fromList(dataPtr.asTypedList(image.ref.dataSize));
      } finally {
        libraw.clearMem(image);
      }
    } finally {
      malloc.free(errPtr);
    }
  } finally {
    libraw.close(lr);
  }
}
