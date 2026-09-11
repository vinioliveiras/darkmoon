import 'dart:typed_data';

import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/render/color_profile.dart';
import 'package:darkmoon/render/color_profile_reference.dart';
import 'package:darkmoon/widgets/color_profile_editor_dialog.dart';
import 'package:darkmoon/widgets/color_profile_preview.dart';
import 'package:darkmoon/widgets/slider_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dialog's real job is translating what the user touches into a
/// 33-point tone curve and a 24-bin hue table. Those two shapes are what
/// the renderer consumes, so a mistake here is invisible in the interface
/// and wrong in the picture.
void main() {
  ColorProfile identity({String name = '', int id = 1000}) => ColorProfile(
    tone: List<double>.of(identityColorProfile.tone),
    hueShift: List<double>.of(identityColorProfile.hueShift),
    satMul: List<double>.of(identityColorProfile.satMul),
    lumMul: List<double>.of(identityColorProfile.lumMul),
    name: name,
    id: id,
  );

  /// The default 800x600 test surface squeezes an AlertDialog this tall
  /// until its tab area collapses and the sliders under test are never
  /// built — a failure that looks like a missing widget and is really a
  /// window size. Give every case room.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1400, 1200);
    view.devicePixelRatio = 1.0;
    addTearDown(view.reset);
  });

  Future<List<ColorProfile>> pumpDialog(
    WidgetTester tester, {
    ColorProfile? initial,
    Set<String> existingNames = const {},
    double? highlightHue,
    Future<({Float32List rgb, int width, int height})?>? photoPreview,
  }) async {
    final drafts = <ColorProfile>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ColorProfileEditorDialog(
          initial: initial ?? identity(),
          existingNames: existingNames,
          highlightHue: highlightHue,
          photoPreview: photoPreview,
          onDraftChanged: drafts.add,
          onDraftSettled: drafts.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return drafts;
  }

  testWidgets('opens on the tone tab with an untouched profile', (
    tester,
  ) async {
    final drafts = await pumpDialog(tester);
    expect(
      drafts,
      isEmpty,
      reason: 'merely opening the dialog must not change the photo',
    );
  });

  testWidgets('saving is refused until the profile has a name', (tester) async {
    await pumpDialog(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, l10n.presetSaveLabel),
    );
    expect(
      save.onPressed,
      isNull,
      reason: 'an unnamed profile would be saved as profile.json',
    );
  });

  testWidgets('a Basic range writes its three bins and nothing else', (
    tester,
  ) async {
    final drafts = await pumpDialog(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Colour tab, then the first range (Red, bins 0-2) saturation slider.
    await tester.tap(find.text(l10n.colorProfileEditorTabColor));
    await tester.pumpAndSettle();

    final saturationSliders = find.byWidgetPredicate(
      (w) => w is SliderRow && w.name == l10n.colorProfileEditorSaturation,
    );
    expect(saturationSliders, findsWidgets);
    tester.widget<SliderRow>(saturationSliders.first).onChanged(50);
    await tester.pump();

    expect(drafts, isNotEmpty);
    final table = drafts.last.satMul;

    for (final bin in [0, 1, 2]) {
      expect(
        table[bin],
        closeTo(1.5, 1e-9),
        reason: 'bin $bin is inside the Red range',
      );
    }
    // The neighbouring bins belong to Magenta and Orange. Red's slider
    // must not touch them: there are no spare bins between ranges, so any
    // feathering here would silently edit a range the user did not open.
    // The renderer interpolates between bin centres anyway, so the
    // transition is already a 15-degree ramp in the picture.
    for (final bin in [23, 3]) {
      expect(
        table[bin],
        1.0,
        reason: 'bin $bin belongs to a neighbouring range',
      );
    }
    for (final bin in [5, 12, 20]) {
      expect(table[bin], 1.0, reason: 'bin $bin is nowhere near Red');
    }
  });

  testWidgets('dragging a range slider does not drift on repeat events', (
    tester,
  ) async {
    // onChanged fires continuously through a drag. Any write that reads the
    // current value back would accumulate across those events, so the same
    // gesture would land somewhere different depending on how many frames
    // it happened to produce.
    final drafts = await pumpDialog(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.text(l10n.colorProfileEditorTabColor));
    await tester.pumpAndSettle();
    final saturationSliders = find.byWidgetPredicate(
      (w) => w is SliderRow && w.name == l10n.colorProfileEditorSaturation,
    );

    for (var i = 0; i < 5; i++) {
      tester.widget<SliderRow>(saturationSliders.first).onChanged(50);
      await tester.pump();
    }

    for (final bin in [0, 1, 2]) {
      expect(drafts.last.satMul[bin], closeTo(1.5, 1e-9));
    }
    for (final bin in [23, 3]) {
      expect(
        drafts.last.satMul[bin],
        1.0,
        reason: 'five identical events must land exactly where one does',
      );
    }
  });

  testWidgets('Advanced writes a single bin and leaves its neighbours', (
    tester,
  ) async {
    final drafts = await pumpDialog(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.text(l10n.colorProfileEditorTabColor));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.colorProfileEditorModeAdvanced));
    await tester.pumpAndSettle();

    final hueSliders = find.byWidgetPredicate(
      (w) => w is SliderRow && w.name == l10n.colorProfileEditorHue,
    );
    tester.widget<SliderRow>(hueSliders.first).onChanged(12);
    await tester.pump();

    final table = drafts.last.hueShift;
    expect(table[0], 12);
    expect(
      table[1],
      0,
      reason: 'Advanced is per-bin — no easing into the neighbours',
    );
    expect(table[23], 0);
  });

  testWidgets('an untouched tone curve stays exactly the identity ramp', (
    tester,
  ) async {
    final drafts = await pumpDialog(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Any edit at all, so a draft is emitted without touching tone.
    await tester.tap(find.text(l10n.colorProfileEditorTabColor));
    await tester.pumpAndSettle();
    final hueSliders = find.byWidgetPredicate(
      (w) => w is SliderRow && w.name == l10n.colorProfileEditorHue,
    );
    tester.widget<SliderRow>(hueSliders.first).onChanged(5);
    await tester.pump();

    expect(drafts.last.tone.length, colorProfileTonePoints);
    expect(
      drafts.last.toneIsIdentity,
      isTrue,
      reason:
          'sampling an untouched curve must not introduce a tone curve, '
          'which would change every pixel of the photo',
    );
  });

  group('preview column', () {
    testWidgets('shows the profile on the chart and on the open photo', (
      tester,
    ) async {
      final photo = (
        rgb: Float32List.fromList(
          List<double>.generate(8 * 6 * 3, (i) => (i % 255).toDouble()),
        ),
        width: 8,
        height: 6,
      );
      await pumpDialog(tester, photoPreview: Future.value(photo));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.tap(find.text(l10n.colorProfileEditorTabColor));
      await tester.pumpAndSettle();
      final hueSliders = find.byWidgetPredicate(
        (w) => w is SliderRow && w.name == l10n.colorProfileEditorHue,
      );
      tester.widget<SliderRow>(hueSliders.first).onChanged(18);
      await tester.pump();

      final previews = tester
          .widgetList<ColorProfilePreview>(find.byType(ColorProfilePreview))
          .toList();
      expect(previews, hasLength(2));

      // Two subjects, one profile. A chart that flatters and a photo that
      // does not is the disagreement worth seeing, so both panes must
      // carry the same edit — showing the draft on one and not the other
      // would look plausible and compare nothing.
      for (final preview in previews) {
        expect(preview.profile.hueShift[0], 18);
      }
      expect(previews.first.sourceWidth, referenceChartWidth);
      expect(
        previews.last.sourceWidth,
        8,
        reason: 'the lower pane is the open photo, not a second chart',
      );
    });

    testWidgets('shows only the chart when no photo is open', (tester) async {
      await pumpDialog(tester);
      expect(find.byType(ColorProfilePreview), findsOneWidget);
    });
  });

  group('eyedropper round trip', () {
    /// The dialog has to close for a colour to be picked — a modal barrier
    /// sits over the photo — so the work in progress leaves with it. If it
    /// did not, arming the eyedropper would silently discard everything
    /// the user had built.
    testWidgets('arming carries the work out with it', (tester) async {
      ColorProfileEditorResult? popped;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                popped = await showDialog<ColorProfileEditorResult>(
                  context: context,
                  builder: (_) => ColorProfileEditorDialog(
                    initial: identity(),
                    existingNames: const {},
                    onDraftChanged: (_) {},
                    onDraftSettled: (_) {},
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.colorProfileEditorTabColor));
      await tester.pumpAndSettle();

      // Build something first, so "carries the work" means anything.
      final hueSliders = find.byWidgetPredicate(
        (w) => w is SliderRow && w.name == l10n.colorProfileEditorHue,
      );
      tester.widget<SliderRow>(hueSliders.first).onChanged(20);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.colorize));
      await tester.pumpAndSettle();

      expect(popped, isNotNull);
      expect(popped!.pickHue, isTrue);
      expect(
        popped!.profile.hueShift[0],
        20,
        reason: 'the edit made before arming must survive the round trip',
      );
    });

    testWidgets('a sampled hue opens on Colour and marks its range', (
      tester,
    ) async {
      // 50 degrees sits just past the Red/Orange boundary: 50 / 15 = bin
      // 3, and Orange owns bins 3-5 while Red owns 0-2. A boundary value
      // is the one worth asserting — the arithmetic is off by one range if
      // the floor or the modulo is wrong. Both labels are near the top of
      // the list, so both are actually built; a range further down would
      // not be, and the finder would fail for a reason unrelated to the
      // mapping.
      await pumpDialog(tester, highlightHue: 50);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      final red = tester.widget<Text>(find.text(l10n.hueRangeRed));
      final orange = tester.widget<Text>(find.text(l10n.hueRangeOrange));
      expect(
        orange.style?.fontWeight,
        FontWeight.w700,
        reason: 'hue 50 falls in bin 3, which Orange owns',
      );
      expect(
        red.style?.fontWeight,
        isNot(FontWeight.w700),
        reason: 'the neighbouring range must not also claim it',
      );
    });
  });

  testWidgets('an existing profile opens with its own values', (tester) async {
    final existing = identity(name: 'Warm', id: 2000);
    existing.satMul[6] = 1.4;

    final drafts = await pumpDialog(tester, initial: existing);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.text(l10n.colorProfileEditorTabColor));
    await tester.pumpAndSettle();
    final hueSliders = find.byWidgetPredicate(
      (w) => w is SliderRow && w.name == l10n.colorProfileEditorHue,
    );
    tester.widget<SliderRow>(hueSliders.first).onChanged(1);
    await tester.pump();

    expect(
      drafts.last.satMul[6],
      closeTo(1.4, 1e-9),
      reason: 'editing one range must not reset the rest of the profile',
    );
    expect(
      drafts.last.id,
      2000,
      reason: 'editing keeps the id, or every photo using it would be orphaned',
    );
  });
}
