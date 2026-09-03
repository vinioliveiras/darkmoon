import 'dart:ffi';
import 'dart:io';

/// Windows `THREAD_PRIORITY_BELOW_NORMAL` — one step under the default
/// `THREAD_PRIORITY_NORMAL` (0). Low enough that the scheduler prefers a
/// runnable UI thread when the CPU is contended, high enough that these
/// isolates still get every otherwise-idle core.
const int _threadPriorityBelowNormal = -1;

typedef _GetCurrentThreadNative = IntPtr Function();
typedef _GetCurrentThreadDart = int Function();
typedef _SetThreadPriorityNative =
    Int32 Function(IntPtr hThread, Int32 priority);
typedef _SetThreadPriorityDart = int Function(int hThread, int priority);

/// Drops the calling isolate's OS thread to below-normal priority so
/// speculative background work — the thumbnail-decode batch and the
/// preview-cache prewarm that both fire when a folder opens — yields to
/// the UI isolate under CPU contention instead of freezing it, while
/// still using spare cores when the machine is otherwise idle.
///
/// Call it as the very first statement inside an `Isolate.run`/`compute`
/// body, *not* on the main isolate: each spawned isolate owns its OS
/// thread for its whole lifetime and that thread is destroyed when the
/// isolate exits, so the change is scoped to this one unit of work and
/// never needs restoring.
///
/// Windows-only (the symbols live in `kernel32.dll`); a no-op elsewhere,
/// where the stock schedulers already share time fairly enough for this
/// workload. Best-effort: any failure (unexpected platform, missing
/// symbol) is swallowed — worst case the isolate just runs at normal
/// priority, the behaviour before this existed.
void lowerBackgroundThreadPriority() {
  if (!Platform.isWindows) {
    return;
  }
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getCurrentThread = kernel32
        .lookupFunction<_GetCurrentThreadNative, _GetCurrentThreadDart>(
          'GetCurrentThread',
        );
    final setThreadPriority = kernel32
        .lookupFunction<_SetThreadPriorityNative, _SetThreadPriorityDart>(
          'SetThreadPriority',
        );
    // GetCurrentThread() returns a pseudo-handle that doesn't need closing.
    setThreadPriority(getCurrentThread(), _threadPriorityBelowNormal);
  } catch (_) {
    // Best-effort — see the doc comment.
  }
}
