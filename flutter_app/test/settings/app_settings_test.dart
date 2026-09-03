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

    test('withDefaultDenoiseModel clears a previously-set custom path back '
        'to null — copyWith itself cannot do this (its `??` pattern can\'t '
        'distinguish "clear" from "leave alone", same limitation every '
        'other nullable field here already has)', () {
      const settings = AppSettings(
        customDenoiseModelPath: r'D:\models\DRUNet.onnx',
      );
      final reset = settings.withDefaultDenoiseModel();
      expect(reset.customDenoiseModelPath, isNull);
    });

    test('withDefaultDenoiseModel preserves every other field unchanged', () {
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
    });
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

  group('fullQualityWorkingLongEdge', () {
    // The floor is the whole point: a full-quality render is never allowed
    // to come out worse than the ordinary editing preview, which means a
    // low percentage on a low-megapixel photo silently produces exactly
    // the preview resolution — the "Dynamic Full Resolution isn't working"
    // report of 2026-09-03.
    test('a low percentage on a low-megapixel photo is a no-op', () {
      // Canon 350D, 3456 px long edge, at the old 30% default.
      final r = fullQualityWorkingLongEdge(
        nativeLongEdge: 3456,
        fullQualityPercent: 30,
        previewResolution: 1280,
      );
      expect(r.longEdge, 1280, reason: 'identical to the plain preview');
      expect(r.cappedByPreview, isTrue);
    });

    test('the shipped default clears the floor on the same photo', () {
      final r = fullQualityWorkingLongEdge(
        nativeLongEdge: 3456,
        fullQualityPercent: 40,
        previewResolution: 1280,
      );
      expect(r.longEdge, 1382);
      expect(r.cappedByPreview, isFalse);
    });

    test('a high-megapixel photo clears the floor comfortably', () {
      // Fujifilm X100VI, 7728 px long edge.
      final r = fullQualityWorkingLongEdge(
        nativeLongEdge: 7728,
        fullQualityPercent: 40,
        previewResolution: 1024,
      );
      expect(r.longEdge, 3091);
      expect(r.cappedByPreview, isFalse);
    });

    test('never upscales past the sensor', () {
      final r = fullQualityWorkingLongEdge(
        nativeLongEdge: 900,
        fullQualityPercent: 100,
        previewResolution: 2048,
      );
      expect(r.longEdge, 900);
      // The floor did apply, it just lost to the native cap right after.
      expect(r.cappedByPreview, isTrue);
    });

    test('100 percent is the native resolution', () {
      final r = fullQualityWorkingLongEdge(
        nativeLongEdge: 6000,
        fullQualityPercent: 100,
        previewResolution: 1024,
      );
      expect(r.longEdge, 6000);
      expect(r.cappedByPreview, isFalse);
    });
  });
}
