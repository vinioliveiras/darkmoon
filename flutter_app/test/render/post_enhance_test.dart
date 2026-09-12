import 'package:darkmoon/render/ai_enhance.dart';
import 'package:darkmoon/render/post_enhance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('off, every pass stays on the source and nothing runs after', () {
    final values = {'AiNeuralDenoise': 1.0, 'AiRestoreDetail': 1.0};
    final source = sourceNeuralPassesFor(values);
    expect(source.denoise, isTrue);
    expect(source.restoreDetail, isTrue);
    // No sharpen key: follows Restore detail, as the editor does.
    expect(source.detailSharpen, isTrue);
    expect(postEnhanceSpecFromValues(values), isNull);
  });

  test('on, the three passes leave the source for the render\'s end', () {
    final values = {
      'AiNeuralAfterEdits': 1.0,
      'AiNeuralDenoise': 1.0,
      'AiNeuralDenoiseAmount': 70.0,
      'AiRestoreDetail': 1.0,
      'AiRestoreDetailAmount': 40.0,
      'AiDetailSharpen': 0.0,
      'AiNeuralUpscale': 1.0,
    };
    final source = sourceNeuralPassesFor(values);
    expect(source.denoise, isFalse);
    expect(source.restoreDetail, isFalse);
    expect(source.detailSharpen, isFalse);
    final spec = postEnhanceSpecFromValues(values, denoiseModelPath: 'x.onnx')!;
    expect(spec.denoise, isTrue);
    expect(spec.denoiseStrength, closeTo(0.7, 1e-9));
    expect(spec.restoreDetail, isTrue);
    expect(spec.restoreAmount, closeTo(0.4, 1e-9));
    expect(spec.detailSharpen, isFalse);
    expect(spec.denoiseModelPath, 'x.onnx');
    expect(spec.cacheKey, 'post:d70r40x.onnx');
  });

  test('on with nothing to run is no spec; amounts fall back to defaults', () {
    expect(postEnhanceSpecFromValues({'AiNeuralAfterEdits': 1.0}), isNull);
    final spec = postEnhanceSpecFromValues({
      'AiNeuralAfterEdits': 1.0,
      'AiNeuralDenoise': 1.0,
    })!;
    expect(spec.denoiseStrength, defaultNeuralDenoiseAmount / 100);
    expect(spec.restoreDetail, isFalse);
    expect(spec.detailSharpen, isFalse);
  });
}
