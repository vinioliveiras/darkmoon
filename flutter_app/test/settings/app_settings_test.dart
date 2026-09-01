import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/settings/app_settings.dart';

void main() {
  group('AppSettings.customDenoiseModelPath', () {
    test('defaults to null (use the bundled model)', () {
      const settings = AppSettings();
      expect(settings.customDenoiseModelPath, isNull);
    });

    test('copyWith sets a custom path', () {
      const settings = AppSettings();
      final updated = settings.copyWith(
        customDenoiseModelPath: r'D:\models\DRUNet.onnx',
      );
      expect(updated.customDenoiseModelPath, r'D:\models\DRUNet.onnx');
    });

    test(
      'withDefaultDenoiseModel clears a previously-set custom path back '
      'to null — copyWith itself cannot do this (its `??` pattern can\'t '
      'distinguish "clear" from "leave alone", same limitation every '
      'other nullable field here already has)',
      () {
        const settings = AppSettings(
          customDenoiseModelPath: r'D:\models\DRUNet.onnx',
        );
        final reset = settings.withDefaultDenoiseModel();
        expect(reset.customDenoiseModelPath, isNull);
      },
    );

    test(
      'withDefaultDenoiseModel preserves every other field unchanged',
      () {
        const settings = AppSettings(
          language: 'pt',
          previewResolution: 1600,
          useGpuRender: false,
          devLogging: true,
          customDenoiseModelPath: r'D:\models\DRUNet.onnx',
        );
        final reset = settings.withDefaultDenoiseModel();
        expect(reset.language, 'pt');
        expect(reset.previewResolution, 1600);
        expect(reset.useGpuRender, isFalse);
        expect(reset.devLogging, isTrue);
      },
    );
  });

  group('AppSettings.asSingleFileSession', () {
    test(
      'clears lastActiveFolder and sets lastActiveFile — real bug fix: '
      'copyWith(lastActiveFolder: null) cannot clear it (same `??` '
      'limitation), so a single-file session left a stale folder recorded, '
      'and _loadSettings restored that instead of the file on next launch',
      () {
        const settings = AppSettings(lastActiveFolder: r'D:\Photos\Trip');
        final next = settings.asSingleFileSession(r'D:\Photos\one.jpg');
        expect(next.lastActiveFolder, isNull);
        expect(next.lastActiveFile, r'D:\Photos\one.jpg');
      },
    );

    test('preserves every other field unchanged', () {
      const settings = AppSettings(
        language: 'pt',
        previewResolution: 1600,
        lastActiveFolder: r'D:\Photos\Trip',
      );
      final next = settings.asSingleFileSession(r'D:\Photos\one.jpg');
      expect(next.language, 'pt');
      expect(next.previewResolution, 1600);
    });
  });
}
