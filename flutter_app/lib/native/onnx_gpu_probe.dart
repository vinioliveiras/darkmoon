import 'package:flutter/foundation.dart' show compute;

import 'onnx_runtime.dart';

/// Cached for the app's lifetime once probed — DirectML support can't
/// change mid-session, so there's no reason to pay the ~1-2s session-
/// creation cost more than once. `null` means "not probed yet".
bool? _cachedGpuSupport;

/// Runs in a throwaway background isolate (via [compute]) — creating an
/// [OnnxModel] session is blocking FFI work, same reasoning every other
/// ONNX call in this codebase runs off the main isolate.
bool _probeInIsolate(void _) => OnnxModel.forSpec(denoiseModelSpec).usingGpu;

/// Whether DirectML actually works for AI Enhance's models on this
/// machine — used to show an honest "this will run on CPU and be slower"
/// warning in the AI Denoise dialog *before* the user commits to running
/// it, rather than only after (see `AiEnhanceModelInfo`/the CPU-fallback
/// SnackBar in `editor_screen.dart`, which fire only once the pipeline is
/// already running).
///
/// Only probes the denoise model, not both — whether DirectML works at
/// all is mostly a property of the GPU/driver, not the specific model
/// graph (only confirmed on one real machine so far, not a guarantee),
/// and probing both would double this one-time wait for a dialog hint
/// that's meant to be quick. If this ever proves to disagree with the
/// upscale model's own real result, `AiEnhanceModelInfo` still reports
/// the true per-model answer once the pipeline actually runs.
Future<bool> probeAiEnhanceGpuSupport() async {
  final cached = _cachedGpuSupport;
  if (cached != null) {
    return cached;
  }
  try {
    final result = await compute(_probeInIsolate, null);
    _cachedGpuSupport = result;
    return result;
  } catch (_) {
    // Model/DLL genuinely missing, or some other setup problem deeper
    // than a DirectML-vs-CPU question — not cached (worth trying again
    // later, e.g. after Settings > Developer Mode surfaces the real
    // reason), and treated as "no GPU" so the dialog's warning still
    // errs toward telling the user to expect a slow run rather than
    // silently saying nothing.
    return false;
  }
}
