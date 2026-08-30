import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/native/onnx_runtime.dart';

void main() {
  group('OnnxModelSpec.customDenoiseModel', () {
    test(
      'matches denoiseModelSpec\'s tile geometry exactly — a deliberate '
      'drop-in replacement, not a generically-introspected model',
      () {
        final custom = OnnxModelSpec.customDenoiseModel(
          r'D:\models\DRUNet.onnx',
        );
        expect(custom.inputTileSize, denoiseModelSpec.inputTileSize);
        expect(custom.scaleFactor, denoiseModelSpec.scaleFactor);
        expect(custom.channels, denoiseModelSpec.channels);
      },
    );

    test('fileName is the basename, not the full path', () {
      final custom = OnnxModelSpec.customDenoiseModel(
        r'D:\models\subdir\DRUNet.onnx',
      );
      expect(custom.fileName, 'DRUNet.onnx');
    });

    test('customAbsolutePath carries the exact path given', () {
      final custom = OnnxModelSpec.customDenoiseModel(
        r'D:\models\DRUNet.onnx',
      );
      expect(custom.customAbsolutePath, r'D:\models\DRUNet.onnx');
    });
  });

  group('OnnxModelSpec.cacheKey', () {
    test('the bundled default spec keys by its fileName', () {
      expect(denoiseModelSpec.cacheKey, denoiseModelSpec.fileName);
      expect(denoiseModelSpec.customAbsolutePath, isNull);
    });

    test(
      'a custom-model spec keys by its full path, not just the basename '
      '— two different custom models that happen to share a filename '
      'must not collide in OnnxModel\'s session cache',
      () {
        final a = OnnxModelSpec.customDenoiseModel(r'C:\a\model.onnx');
        final b = OnnxModelSpec.customDenoiseModel(r'C:\b\model.onnx');
        expect(a.fileName, b.fileName); // same basename
        expect(a.cacheKey, isNot(equals(b.cacheKey))); // different cache entries
      },
    );

    test(
      'a custom model never collides with the bundled default, even if '
      'a user happened to name their file the same as the bundled one',
      () {
        final custom = OnnxModelSpec.customDenoiseModel(
          'C:\\somewhere\\${denoiseModelSpec.fileName}',
        );
        expect(custom.cacheKey, isNot(equals(denoiseModelSpec.cacheKey)));
      },
    );
  });
}
