import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/native/common_image.dart';
import 'package:darkmoon/settings/app_settings.dart';
import 'package:darkmoon/widgets/settings_dialog.dart';

/// Editing a RAW as the camera's own JPEG rendering rather than as sensor
/// data.
///
/// The setting decides *which pixels a photo is*, so the thing worth
/// guarding is that one answer reaches every decode — the editing preview,
/// the export, and the three neural pipelines. A path that missed it would
/// not fail; it would quietly show or write different pixels than the one
/// beside it.
void main() {
  group('the setting', () {
    test('is off by default — a RAW is sensor data until asked otherwise', () {
      expect(const AppSettings().editEmbeddedJpeg, isFalse);
    });

    test('it survives the constructors that rebuild every field by hand', () {
      // withDefaultDenoiseModel and asSingleFileSession list every field
      // rather than using copyWith (which cannot express "clear this"), so
      // a new field is easy to add in one place and forget in the other
      // two — where it silently reverts to its default.
      const on = AppSettings(editEmbeddedJpeg: true);
      expect(on.withDefaultDenoiseModel().editEmbeddedJpeg, isTrue);
      expect(on.asSingleFileSession('a.raf').editEmbeddedJpeg, isTrue);
    });

    test('the two resolution-shaped settings are independent', () {
      const s = AppSettings(previewResolution: 1280, editEmbeddedJpeg: true);
      expect(s.copyWith(editEmbeddedJpeg: false).previewResolution, 1280);
      expect(s.copyWith(previewResolution: 512).editEmbeddedJpeg, isTrue);
    });
  });

  group('decodeSourceImage', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('darkmoon_src'));
    tearDown(() => dir.deleteSync(recursive: true));

    String writePng(int r, int g, int b) {
      final image = img.Image(width: 8, height: 6);
      img.fill(image, color: img.ColorRgb8(r, g, b));
      final path = '${dir.path}${Platform.pathSeparator}flat.png';
      File(path).writeAsBytesSync(Uint8List.fromList(img.encodePng(image)));
      return path;
    }

    test('a common image ignores the setting entirely', () {
      // It has no embedded anything, and it was never downscaled or
      // demosaiced — there is no second interpretation of a PNG to choose
      // between, so both answers have to be the same pixels.
      final path = writePng(10, 200, 90);
      final off = decodeSourceImage(path, embeddedJpeg: false)!;
      final on = decodeSourceImage(path, embeddedJpeg: true)!;
      expect(on.rgbBytes, off.rgbBytes);
      expect(on.width, 8);
      expect(on.height, 6);
      expect(off.rgbBytes.sublist(0, 3), [10, 200, 90]);
    });

    test('it carries no camera match — there is nothing to match', () {
      final decoded = decodeSourceImage(writePng(40, 40, 40), embeddedJpeg: true)!;
      expect(decoded.baseExposureStops, isNull);
      expect(decoded.baseToneCurve, isNull);
    });
  });

  group('Settings > Performance', () {
    Future<void> pump(WidgetTester tester, AppSettings settings) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => SettingsDialog(
                    settings: settings,
                    onChanged: (_) {},
                    onClearThumbnails: () {},
                    onClearCatalog: () {},
                    onPruneMissing: () {},
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers the toggle', (tester) async {
      await pump(tester, const AppSettings());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.settingsEditEmbeddedJpegLabel), findsOneWidget);
    });

    testWidgets('off, the resolution row speaks for itself', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await pump(tester, const AppSettings());
      expect(find.text(l10n.settingsPreviewResolutionHint), findsOneWidget);
      expect(
        find.text(l10n.settingsPreviewResolutionEmbeddedHint),
        findsNothing,
      );
    });

    testWidgets('on, it says the resolution is unused', (tester) async {
      // The dropdown keeps its value — it is what the app returns to — so
      // without this the row would read as still in force while every
      // decode ignores it.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await pump(tester, const AppSettings(editEmbeddedJpeg: true));
      expect(
        find.text(l10n.settingsPreviewResolutionEmbeddedHint),
        findsOneWidget,
      );
      expect(find.text(l10n.settingsPreviewResolutionHint), findsNothing);
    });
  });
}
