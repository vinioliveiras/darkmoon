// The whole removal flow through the widgets: open a folder with a JPEG,
// enter removal mode from the toolbar, paint a stroke on the canvas,
// press Remove, and see the removal listed and the strokes gone. The
// model runs for real, so this needs a built bundle:
//
//   DARKMOON_NATIVE_DIR=<bundle> flutter test test/editor/remove_objects_flow_test.dart
//
// Skipped without it (CI has no model). Written for the 2026-09-12 report
// that pressing Remove left the painted mask on screen and did nothing.
import 'dart:io';

import 'package:darkmoon/editor_screen.dart';
import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/settings/app_settings.dart';
import 'package:darkmoon/theme.dart';
import 'package:darkmoon/widgets/brush_mask_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  final native = Platform.environment['DARKMOON_NATIVE_DIR'];
  late Directory dir;
  late String photo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('darkmoon_remove_flow_');
    photo = p.join(dir.path, 'street.jpg');
    // A frame with structure to fill from: a gradient sky, a striped
    // wall, and a red block to remove in the middle.
    final image = img.Image(width: 800, height: 600);
    for (var y = 0; y < 600; y++) {
      for (var x = 0; x < 800; x++) {
        final sky = y < 250;
        final r = sky ? 120 : 90 + ((x ~/ 20) % 2) * 60;
        final g = sky ? 160 + y ~/ 5 : 80 + ((x ~/ 20) % 2) * 50;
        final b = sky ? 230 : 70;
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    for (var y = 260; y < 380; y++) {
      for (var x = 340; x < 460; x++) {
        image.setPixelRgb(x, y, 220, 30, 30);
      }
    }
    await File(photo).writeAsBytes(img.encodeJpg(image, quality: 92));
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// Real work started from the widget's fake-clock zone needs real time
  /// and pumps to deliver — the pattern the library tests use.
  Future<bool> settleUntil(
    WidgetTester tester,
    bool Function() done, {
    Duration limit = const Duration(minutes: 3),
  }) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < limit) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      if (done()) {
        return true;
      }
    }
    return false;
  }

  testWidgets(
    'paint, press Remove, and the removal is listed with the strokes gone',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // The caches and stores live under a documents directory the test
      // process has no plugin for; point them at the temp folder.
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => p.join(dir.path, 'documents'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: buildDarkmoonTheme(),
          home: EditorScreen(
            onLanguageChanged: (_) {},
            settingsOverride: AppSettings(
              lastActiveFolder: dir.path,
              lastActiveFile: photo,
              libraryFolders: [dir.path],
              // A small preview keeps the rasterisation and the fill quick.
              previewResolution: 1024,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 5));

      // The photo decodes; the toolbar's removal button is enabled once
      // something is selected.
      final removeButton = find.byTooltip('Remove objects');
      expect(
        await settleUntil(tester, () => removeButton.evaluate().isNotEmpty),
        isTrue,
        reason: 'the toolbar never showed the removal button',
      );
      // The button is live once the photo is selected and decoded; tap
      // until the panel answers.
      expect(
        await settleUntil(tester, () {
          if (find.text('Remove').evaluate().isNotEmpty) {
            return true;
          }
          tester.tap(removeButton, warnIfMissed: false);
          return false;
        }),
        isTrue,
        reason: 'the panel never opened',
      );

      final overlay = find.byType(BrushMaskOverlay);
      expect(
        await settleUntil(tester, () => overlay.evaluate().isNotEmpty),
        isTrue,
        reason: 'no brush overlay on the canvas in removal mode',
      );
      final centre = tester.getCenter(overlay);
      await tester.dragFrom(centre - const Offset(40, 0), const Offset(80, 0));
      await tester.pump();

      final runButton = find.widgetWithText(FilledButton, 'Remove');
      expect(
        tester.widget<FilledButton>(runButton).onPressed,
        isNotNull,
        reason: 'Remove stays disabled after painting',
      );
      await tester.tap(runButton);
      await tester.pump();

      expect(
        await settleUntil(
          tester,
          () => find.text('Removal 1').evaluate().isNotEmpty,
        ),
        isTrue,
        reason: 'the removal never appeared in the list',
      );
      // The strokes are consumed; Remove waits for the next ones.
      expect(tester.widget<FilledButton>(runButton).onPressed, isNull);
      await tester.pumpAndSettle();
    },
    // Needs DARKMOON_NATIVE_DIR pointing at a built bundle.
    skip: native == null,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
