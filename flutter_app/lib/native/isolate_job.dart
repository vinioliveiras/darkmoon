import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Shared pieces for every `Isolate.spawn` site in the app (RAW decode,
/// AI Enhance, Colorize, the standalone AI Enhance job, the progress
/// render and Export).
///
/// History (2026-09-09): none of those six sites passed `onError` or
/// `onExit` to [Isolate.spawn]. An exception inside the worker — a bundled
/// model missing, an ORT session refusing to load, a corrupt file — killed
/// the isolate silently, nothing ever arrived on the `ReceivePort` the
/// caller was reading, and its `await for` waited forever: a progress
/// spinner that never went away. Every site now routes both ports back to
/// the caller and recognises the two extra message shapes — an
/// [IsolateError] for `onError`, `null` for `onExit`.

/// An uncaught error that ended a worker isolate, as delivered on the
/// `onError` port: Dart sends a two-element list, the error and the stack
/// trace, both already turned into strings.
class IsolateError {
  const IsolateError(this.error, this.stackTrace);

  final String error;
  final String stackTrace;

  /// The error carried by [message] when it is an `onError` delivery,
  /// `null` for every other message. No protocol in this app sends a bare
  /// two-string list, so the shape is unambiguous.
  static IsolateError? of(Object? message) {
    if (message is List &&
        message.length == 2 &&
        message[0] is String &&
        message[1] is String) {
      return IsolateError(message[0] as String, message[1] as String);
    }
    return null;
  }

  /// The `StackTrace` form of [stackTrace], for `DevLog.logError`.
  StackTrace get trace => StackTrace.fromString(stackTrace);

  @override
  String toString() => error;
}

/// Thrown by a worker that noticed its [IsolateCancelFlag]; the isolate
/// entry catches it, runs its `finally` (session release) and reports
/// `null`, the same result the caller already reads as "no output".
class IsolateCancelled implements Exception {
  const IsolateCancelled();

  @override
  String toString() => 'IsolateCancelled';
}

/// A cancel request that crosses the isolate boundary without a message.
///
/// The AI isolates spend their time inside synchronous FFI calls — one
/// ONNX tile after another with no `await` in between — so a `SendPort`
/// message asking them to stop would sit unread until the whole run had
/// finished anyway. Killing them instead (`Isolate.kill`, what Cancel did
/// until 2026-09-09) skips their `finally` blocks, and the ONNX sessions
/// they own — hundreds of MB, 934 MB for DDColor alone — outlived them:
/// one full set of native sessions leaked per cancel.
///
/// A single `int32` in native memory needs no message loop. The spawner
/// owns it and sets it; the worker rebuilds a view of it from its
/// [address] and reads it at every progress checkpoint (each tile, each
/// stage boundary), then unwinds by throwing [IsolateCancelled] — through
/// `finally`, not around it.
///
/// Lifetime: the spawner must keep the flag alive until the worker has
/// exited — freeing it earlier leaves the worker reading freed memory.
/// [Isolate.spawn]'s `onExit` port is the signal; see
/// [disposeOnIsolateExit].
class IsolateCancelFlag {
  /// A new flag, owned by the caller. Starts clear.
  IsolateCancelFlag() : _ptr = calloc<Int32>(), _owned = true;

  /// The worker's view of a flag created elsewhere. Never frees it.
  IsolateCancelFlag.fromAddress(int address)
    : _ptr = Pointer<Int32>.fromAddress(address),
      _owned = false;

  final Pointer<Int32> _ptr;
  final bool _owned;
  bool _disposed = false;

  /// The address to hand to the worker, for [IsolateCancelFlag.fromAddress].
  int get address => _ptr.address;

  /// Whether cancel has been requested. A disposed flag reads as clear:
  /// its worker has already exited, so there is nothing left to stop.
  bool get isSet => !_disposed && _ptr.value != 0;

  /// Requests cancel. Sticky; a no-op once disposed.
  void set() {
    if (!_disposed) {
      _ptr.value = 1;
    }
  }

  /// Frees the native int. Only the owning side (the default constructor)
  /// ever does; a [IsolateCancelFlag.fromAddress] view ignores this.
  void dispose() {
    if (_owned && !_disposed) {
      _disposed = true;
      calloc.free(_ptr);
    }
  }
}

/// Frees [flag] and closes [exitPort] once the isolate whose `onExit` is
/// wired to [exitPort] has gone — the one moment it is safe to free a flag
/// the worker may still be reading.
Future<void> disposeOnIsolateExit(
  ReceivePort exitPort,
  IsolateCancelFlag flag,
) async {
  await exitPort.first;
  exitPort.close();
  flag.dispose();
}
