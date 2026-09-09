import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/settings/app_settings.dart';

void main() {
  group('preview resolution', () {
    test('defaults to 3072', () {
      expect(const AppSettings().previewResolution, defaultPreviewResolution);
      expect(
        previewResolutionOptions,
        contains(defaultPreviewResolution),
        reason: 'the default has to be offered by the dropdown too',
      );
      expect(
        previewResolutionOptions,
        contains(nativePreviewResolution),
        reason: 'native stays one entry away for anyone who wants it',
      );
    });

    test('the list runs high to low, with native first', () {
      expect(previewResolutionOptions.first, nativePreviewResolution);
      final capped = previewResolutionOptions.skip(1).toList();
      expect(
        capped,
        orderedEquals(capped.toList()..sort((a, b) => b.compareTo(a))),
        reason: 'the dropdown reads as a scale, so it has to be ordered',
      );
      expect(
        capped.toSet().length,
        capped.length,
        reason: 'a duplicate entry would be two identical dropdown rows',
      );
    });
  });

  group('AppSettings.tabbedControlsPanelIcons', () {
    test('defaults to words', () {
      expect(const AppSettings().tabbedControlsPanelIcons, isFalse);
    });

    // AppSettings has two hand-written copy constructors that list every
    // field. A new field forgotten in one of them does not fail to
    // compile — it silently snaps back to its default the next time that
    // constructor runs, which for asSingleFileSession is every time a
    // single photo is opened. Persistence itself reads a file and needs
    // path_provider, so it cannot be reached from here; these two can.
    test('survives withDefaultDenoiseModel', () {
      const settings = AppSettings(tabbedControlsPanelIcons: true);
      expect(
        settings.withDefaultDenoiseModel().tabbedControlsPanelIcons,
        isTrue,
      );
    });

    test('survives asSingleFileSession', () {
      const settings = AppSettings(tabbedControlsPanelIcons: true);
      expect(
        settings.asSingleFileSession(r'D:\photo.cr2').tabbedControlsPanelIcons,
        isTrue,
      );
    });
  });

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
}
