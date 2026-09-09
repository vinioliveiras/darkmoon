import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/native/common_image.dart';
import 'package:darkmoon/native/edit_source.dart';
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

    String writePng(int r, int g, int b, {int w = 8, int h = 6}) {
      final image = img.Image(width: w, height: h);
      img.fill(image, color: img.ColorRgb8(r, g, b));
      final path = '${dir.path}${Platform.pathSeparator}flat_${w}x$h.png';
      File(path).writeAsBytesSync(Uint8List.fromList(img.encodePng(image)));
      return path;
    }

    test('a common image ignores the setting entirely', () {
      // There is no second interpretation of a PNG to choose between, so
      // both answers have to be the same pixels.
      final path = writePng(10, 200, 90);
      final off = decodeSourceImage(path, embeddedJpeg: false)!;
      final on = decodeSourceImage(path, embeddedJpeg: true)!;
      expect(on.rgbBytes, off.rgbBytes);
      expect(on.width, 8);
      expect(on.height, 6);
      expect(off.rgbBytes.sublist(0, 3), [10, 200, 90]);
    });

    test('the preview honours the resolution cap in either mode', () {
      // The regression this guards: embedded-JPEG mode was briefly exempt
      // from the cap, on the reasoning that the camera's JPEG is already
      // smaller than the sensor so capping it throws detail away for
      // nothing. What the cap buys is a cheaper *render*, and that runs on
      // every slider move no matter where the pixels came from. The same
      // exception silently uncapped common formats, which had always been
      // capped here.
      final path = writePng(90, 90, 90, w: 400, h: 300);
      for (final embedded in const [false, true]) {
        final pair = decodeEditSources(
          path,
          previewMaxDimension: 100,
          editEmbeddedJpeg: embedded,
        )!;
        expect(
          math.max(pair.preview.width, pair.preview.height),
          100,
          reason: 'editEmbeddedJpeg: $embedded',
        );
      }
    });

    test('zero still means the whole source', () {
      final path = writePng(90, 90, 90, w: 400, h: 300);
      final pair = decodeEditSources(path, previewMaxDimension: 0)!;
      expect(pair.preview.width, 400);
      expect(pair.preview.height, 300);
    });

    test('it carries no camera match — there is nothing to match', () {
      final decoded = decodeSourceImage(
        writePng(40, 40, 40),
        embeddedJpeg: true,
      )!;
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

    testWidgets('the resolution row reads the same either way', (tester) async {
      // It briefly did not: embedded-JPEG mode was exempt from the cap,
      // so the row had to say it no longer applied. Both modes honour it
      // now — the cap buys a cheaper render on every slider move, which
      // has nothing to do with where the pixels came from.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await pump(tester, const AppSettings(editEmbeddedJpeg: true));
      expect(find.text(l10n.settingsPreviewResolutionHint), findsOneWidget);
      expect(find.text(l10n.settingsPreviewResolutionLabel), findsOneWidget);
    });
  });
}
