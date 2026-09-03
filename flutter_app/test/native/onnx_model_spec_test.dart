import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:darkmoon/native/onnx_runtime.dart';

// Paths are built with p.join rather than written out, so they use the
// running platform's own separator. These used to be Windows literals
// (r'D:\models\DRUNet.onnx'), which quietly made two of these tests
// Windows-only: OnnxModelSpec.fileName goes through package:path's
// basename, and on Linux a backslash is an ordinary filename character,
// so the "basename" of that literal is the whole string. Caught the
// moment CI first ran the suite on Linux.
String _path(List<String> parts) => p.joinAll(parts);

void main() {
  group('OnnxModelSpec.customDenoiseModel', () {
    test('matches denoiseModelSpec\'s tile geometry exactly — a deliberate '
        'drop-in replacement, not a generically-introspected model', () {
      final custom = OnnxModelSpec.customDenoiseModel(
        _path(['models', 'DRUNet.onnx']),
      );
      expect(custom.inputTileSize, denoiseModelSpec.inputTileSize);
      expect(custom.scaleFactor, denoiseModelSpec.scaleFactor);
      expect(custom.channels, denoiseModelSpec.channels);
    });

    test('fileName is the basename, not the full path', () {
      final custom = OnnxModelSpec.customDenoiseModel(
        _path(['models', 'subdir', 'DRUNet.onnx']),
      );
      expect(custom.fileName, 'DRUNet.onnx');
    });

    test('customAbsolutePath carries the exact path given', () {
      final given = _path(['models', 'DRUNet.onnx']);
      final custom = OnnxModelSpec.customDenoiseModel(given);
      expect(custom.customAbsolutePath, given);
    });
  });

  group('OnnxModelSpec.cacheKey', () {
    test('the bundled default spec keys by its fileName', () {
      expect(denoiseModelSpec.cacheKey, denoiseModelSpec.fileName);
      expect(denoiseModelSpec.customAbsolutePath, isNull);
    });

    test('a custom-model spec keys by its full path, not just the basename '
        '— two different custom models that happen to share a filename '
        'must not collide in OnnxModel\'s session cache', () {
      final a = OnnxModelSpec.customDenoiseModel(_path(['a', 'model.onnx']));
      final b = OnnxModelSpec.customDenoiseModel(_path(['b', 'model.onnx']));
      expect(a.fileName, b.fileName); // same basename
      expect(a.cacheKey, isNot(equals(b.cacheKey))); // different cache entries
    });

    test('a custom model never collides with the bundled default, even if '
        'a user happened to name their file the same as the bundled one', () {
      final custom = OnnxModelSpec.customDenoiseModel(
        _path(['somewhere', denoiseModelSpec.fileName]),
      );
      expect(custom.cacheKey, isNot(equals(denoiseModelSpec.cacheKey)));
    });
  });
}
