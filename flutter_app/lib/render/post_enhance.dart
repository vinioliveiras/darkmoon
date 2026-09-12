// The AI Denoise dialog's "apply to the edited photo" (2026-09-13, user's
// request): Denoise, Restore detail and Detail sharpen run on the
// *finished render* — the photo with every slider, curve and mask
// applied — instead of on the untouched decoded source, in the preview
// and in the export alike. Raw denoise (pre-demosaic by nature), Upscale
// (it changes the resolution the edits are rendered at) and Colorize (a
// base for the edits) stay on the source.
//
// The cost is honest: the models run again after every settled edit, in
// the render's own isolate, on top of the render itself. The live drag
// frames skip the pass (see RenderJob.postEnhance's caller).

import 'dart:typed_data';

import '../native/onnx_runtime.dart';
import 'ai_enhance.dart';

/// The param key (see `editor/definitions.dart`'s `_neuralAfterEditsKey`)
/// — `> 0` means the passes move to the render's end.
const aiNeuralAfterEditsKey = 'AiNeuralAfterEdits';

// Mirrors of the editor's private param keys, so the gating below can be
// tested outside the editor library. Keep in step with definitions.dart.
const _denoiseKey = 'AiNeuralDenoise';
const _denoiseAmountKey = 'AiNeuralDenoiseAmount';
const _restoreDetailKey = 'AiRestoreDetail';
const _restoreDetailAmountKey = 'AiRestoreDetailAmount';
const _detailSharpenKey = 'AiDetailSharpen';
const _detailSharpenAmountKey = 'AiDetailSharpenAmount';

bool _on(Map<String, double> values, String key) => (values[key] ?? 0) > 0;

/// Whether "apply to the edited photo" is on for [values].
bool neuralAfterEditsOn(Map<String, double> values) =>
    _on(values, aiNeuralAfterEditsKey);

/// A photo saved before Detail sharpen was its own toggle has no key for
/// it: its Restore detail ran both passes, so absence follows Restore.
bool _detailSharpenOn(Map<String, double> values) =>
    values.containsKey(_detailSharpenKey)
    ? _on(values, _detailSharpenKey)
    : _on(values, _restoreDetailKey);

/// The three same-resolution passes as the *source* pipeline should run
/// them: each one only when it is on and not moved to the render's end.
({bool denoise, bool restoreDetail, bool detailSharpen}) sourceNeuralPassesFor(
  Map<String, double> values,
) {
  final after = neuralAfterEditsOn(values);
  return (
    denoise: !after && _on(values, _denoiseKey),
    restoreDetail: !after && _on(values, _restoreDetailKey),
    detailSharpen: !after && _detailSharpenOn(values),
  );
}

/// What runs on the finished render. Immutable and made of primitives so
/// it crosses into the render and export isolates as part of their jobs.
class PostEnhanceSpec {
  const PostEnhanceSpec({
    required this.denoise,
    required this.denoiseStrength,
    required this.restoreDetail,
    required this.restoreAmount,
    required this.detailSharpen,
    required this.sharpenAmount,
    this.denoiseModelPath,
  });

  final bool denoise;

  /// 0..1 blend of the denoiser's output over the render.
  final double denoiseStrength;
  final bool restoreDetail;

  /// 0..1 blend of the GaterV3 restore pass.
  final double restoreAmount;
  final bool detailSharpen;

  /// 0..1 blend of the GaterV3 sharpen pass.
  final double sharpenAmount;

  /// Settings' custom denoise model, when one is set; the bundled model
  /// otherwise (and as the fallback when the custom one fails to load).
  final String? denoiseModelPath;

  /// Everything the render or export cache key needs to tell two specs
  /// apart.
  String get cacheKey =>
      'post:${denoise ? 'd${(denoiseStrength * 100).round()}' : ''}'
      '${restoreDetail ? 'r${(restoreAmount * 100).round()}' : ''}'
      '${detailSharpen ? 's${(sharpenAmount * 100).round()}' : ''}'
      '${denoiseModelPath ?? ''}';
}

/// The spec [values] asks for, or null when "apply to the edited photo" is
/// off or none of the three passes is on. [denoiseModelPath] is Settings'
/// custom model.
PostEnhanceSpec? postEnhanceSpecFromValues(
  Map<String, double> values, {
  String? denoiseModelPath,
}) {
  if (!neuralAfterEditsOn(values)) {
    return null;
  }
  final denoise = _on(values, _denoiseKey);
  final restore = _on(values, _restoreDetailKey);
  final sharpen = _detailSharpenOn(values);
  if (!denoise && !restore && !sharpen) {
    return null;
  }
  double amount(String key, double fallback) =>
      ((values[key] ?? fallback) / 100).clamp(0.0, 1.0);
  final restoreAmount = amount(
    _restoreDetailAmountKey,
    defaultRestoreDetailAmount.toDouble(),
  );
  return PostEnhanceSpec(
    denoise: denoise,
    denoiseStrength: amount(
      _denoiseAmountKey,
      defaultNeuralDenoiseAmount.toDouble(),
    ),
    restoreDetail: restore,
    restoreAmount: restoreAmount,
    detailSharpen: sharpen,
    // Absent, the sharpen amount follows the restore amount — the same
    // rule as the editor's _detailSharpenAmountOf.
    sharpenAmount: values.containsKey(_detailSharpenAmountKey)
        ? amount(_detailSharpenAmountKey, defaultDetailSharpenAmount.toDouble())
        : values.containsKey(_restoreDetailAmountKey)
        ? restoreAmount
        : defaultDetailSharpenAmount / 100,
    denoiseModelPath: denoiseModelPath,
  );
}

/// Runs [spec]'s passes over the packed RGB [rgb] render of [width] x
/// [height] and returns the result (same size). Loads the models it
/// needs in the calling isolate; a custom denoise model that fails to
/// load falls back to the bundled one, as the source pipeline does.
Uint8List applyPostEnhance(
  Uint8List rgb,
  int width,
  int height,
  PostEnhanceSpec spec, {
  void Function(String stage, int done, int total)? onProgress,
}) {
  OnnxModel? denoiseModel;
  if (spec.denoise) {
    final custom = spec.denoiseModelPath;
    try {
      denoiseModel = OnnxModel.forSpec(
        custom != null
            ? OnnxModelSpec.customDenoiseModel(custom)
            : denoiseModelSpec,
      );
    } catch (_) {
      if (custom == null) rethrow;
      denoiseModel = OnnxModel.forSpec(denoiseModelSpec);
    }
  }
  final restoreModel = spec.restoreDetail
      ? OnnxModel.forSpec(gaterV3RestoreModelSpec)
      : null;
  final sharpenModel = spec.detailSharpen
      ? OnnxModel.forSpec(gaterV3SharpenModelSpec)
      : null;
  final result = enhanceImage(
    rgb,
    width,
    height,
    denoise: (tile) => denoiseModel!.runTile(tile),
    // Never called: enableUpscale is false.
    upscale: (tile) => tile,
    enableDenoise: spec.denoise,
    enableUpscale: false,
    denoiseStrength: spec.denoiseStrength,
    detailRestore: restoreModel == null
        ? null
        : (tile) => restoreModel.runTile(tile),
    detailSharpen: sharpenModel == null
        ? null
        : (tile) => sharpenModel.runTile(tile),
    detailSpec: restoreModel != null || sharpenModel != null
        ? gaterV3RestoreModelSpec
        : null,
    detailAmount: spec.restoreAmount,
    detailSharpenAmount: spec.sharpenAmount,
    onProgress: onProgress,
  );
  return result.rgbBytes;
}
