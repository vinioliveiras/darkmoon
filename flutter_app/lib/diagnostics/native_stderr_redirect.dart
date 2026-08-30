import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _CreateFileWNative =
    Pointer<Void> Function(
      Pointer<Utf16> lpFileName,
      Uint32 dwDesiredAccess,
      Uint32 dwShareMode,
      Pointer<Void> lpSecurityAttributes,
      Uint32 dwCreationDisposition,
      Uint32 dwFlagsAndAttributes,
      Pointer<Void> hTemplateFile,
    );
typedef _CreateFileWDart =
    Pointer<Void> Function(
      Pointer<Utf16> lpFileName,
      int dwDesiredAccess,
      int dwShareMode,
      Pointer<Void> lpSecurityAttributes,
      int dwCreationDisposition,
      int dwFlagsAndAttributes,
      Pointer<Void> hTemplateFile,
    );

typedef _SetStdHandleNative =
    Int32 Function(Uint32 nStdHandle, Pointer<Void> hHandle);
typedef _SetStdHandleDart = int Function(int nStdHandle, Pointer<Void> hHandle);

const _genericWrite = 0x40000000;
const _fileShareRead = 0x1;
const _fileShareWrite = 0x2;
const _createAlways = 2;
const _fileAttributeNormal = 0x80;
const _stdOutputHandle = 0xFFFFFFF5; // (DWORD) -11
const _stdErrorHandle = 0xFFFFFFF4; // (DWORD) -12

/// Best-effort Developer Mode experiment: redirects the *process's*
/// stdout/stderr to [targetPath] via the plain Win32 `SetStdHandle` API —
/// on the chance that a native library writes diagnostic detail there
/// that its own public error-message API doesn't expose. The motivating
/// case: `OnnxModel`'s `OrtException.message` only ever says a DirectML
/// session fell back to CPU, never which graph node/operator specifically
/// caused it — that detail, if it exists anywhere, is in ONNX Runtime's
/// own internal logging, and onnxruntime.dll is loaded lazily (well after
/// this runs, from inside the AI Enhance isolate) so there's a real chance
/// its first stderr/stdout write picks up the handle this sets.
///
/// Deliberately NOT a native logging callback (`OrtApi`'s
/// `CreateEnvWithCustomLogger`) — that would need a Dart function pointer
/// ONNX Runtime could still be holding after the isolate that registered
/// it is gone (a fresh isolate is spawned per Enhance run, see
/// `edit_source_ai_enhance.dart`), which risks a real crash on a second
/// run. Plain OS handle redirection has no isolate lifecycle to manage at
/// all — the worst case here is it silently captures nothing, not a
/// crash, if whatever's writing already cached a different handle or
/// writes somewhere else entirely (e.g. `OutputDebugString`, not stdio).
///
/// Call once, as early in `main()` as possible, only when Developer Mode
/// is on — this is process-wide and affects every native library, not
/// just ONNX Runtime, so it's not something to leave on by default.
void redirectNativeStderrToFileForDevMode(String targetPath) {
  if (!Platform.isWindows) {
    return;
  }
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final createFileW = kernel32.lookupFunction<_CreateFileWNative, _CreateFileWDart>(
      'CreateFileW',
    );
    final setStdHandle = kernel32
        .lookupFunction<_SetStdHandleNative, _SetStdHandleDart>('SetStdHandle');

    final pathPtr = targetPath.toNativeUtf16();
    try {
      final handle = createFileW(
        pathPtr,
        _genericWrite,
        _fileShareRead | _fileShareWrite,
        nullptr,
        _createAlways,
        _fileAttributeNormal,
        nullptr,
      );
      if (handle.address == -1) {
        return; // CreateFileW's INVALID_HANDLE_VALUE — skip, best-effort.
      }
      setStdHandle(_stdErrorHandle, handle);
      setStdHandle(_stdOutputHandle, handle);
    } finally {
      calloc.free(pathPtr);
    }
  } catch (_) {
    // Best-effort experiment — must never affect app startup.
  }
}
