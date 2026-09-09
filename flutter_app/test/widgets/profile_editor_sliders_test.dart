import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/render/color_profile.dart';
import 'package:darkmoon/widgets/color_profile_editor_dialog.dart';
import 'package:darkmoon/widgets/slider_row.dart';

/// The two sliders under the profile editor's tone curve have to follow
/// the mouse.
///
/// They did not, and the cause was duller than it looked: the second one
/// sat on the dialog's bottom edge, so a drag aimed at its centre landed
/// outside and never reached it. Widening the tone curve moved it back
/// inside. The first slider worked the whole time, which is what made it
/// read as erratic rather than as simply out of reach (2026-09-09).
///
/// The obvious suspect — a TabBarView is a PageView and competes for
/// horizontal drags — was measured and cleared: the sliders work with the
/// page swipe left enabled. The last test keeps that honest.
void main() {
  Future<void> pumpDialog(WidgetTester tester) async {
    // The dialog sizes itself against the window and caps at 620 tall; the
    // 800x600 default leaves the tone tab too short for the sliders to be
    // built at all, since a ListView only builds what is on screen.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ColorProfileEditorDialog(
            initial: identityColorProfile,
            existingNames: const {},
            onDraftChanged: (_) {},
            onDraftSettled: (_) {},
            strength: 100,
            contrast: 80,
            photoPreview: (
              rgb: Float32List.fromList(List<double>.filled(4 * 4 * 3, 128.0)),
              width: 4,
              height: 4,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The value a SliderRow named [name] is currently showing.
  double valueOf(WidgetTester tester, String name) => tester
      .widgetList<SliderRow>(find.byType(SliderRow))
      .firstWhere((row) => row.name == name)
      .value;

  testWidgets('dragging the strength slider moves it', (tester) async {
    await pumpDialog(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final track = find.descendant(
      of: find.ancestor(
        of: find.text(l10n.presetAmountLabel),
        matching: find.byType(SliderRow),
      ),
      matching: find.byKey(const Key('sliderRowTrack')),
    );
    expect(track, findsOneWidget);

    final before = valueOf(tester, l10n.presetAmountLabel);
    await tester.drag(track, const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(
      valueOf(tester, l10n.presetAmountLabel),
      greaterThan(before),
      reason: 'a drag to the right has to raise the value',
    );
  });

  testWidgets('dragging the contrast slider moves it', (tester) async {
    await pumpDialog(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final track = find.descendant(
      of: find.ancestor(
        of: find.text(l10n.sliderColorProfileAmount),
        matching: find.byType(SliderRow),
      ),
      matching: find.byKey(const Key('sliderRowTrack')),
    );
    final before = valueOf(tester, l10n.sliderColorProfileAmount);
    await tester.drag(track, const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(
      valueOf(tester, l10n.sliderColorProfileAmount),
      lessThan(before),
      reason: 'a drag to the left has to lower the value',
    );
  });

  testWidgets('both sliders fit on screen with the curve', (tester) async {
    // Not a nicety: they are the thing the curve is judged against, so a
    // curve you have to scroll away from to reach them defeats having put
    // them here. The second one sat on the dialog's bottom edge until the
    // curve was widened (2026-09-09).
    await pumpDialog(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final dialog = tester.getRect(find.byType(AlertDialog));
    for (final name in [
      l10n.presetAmountLabel,
      l10n.sliderColorProfileAmount,
    ]) {
      final row = tester.getRect(
        find.ancestor(of: find.text(name), matching: find.byType(SliderRow)),
      );
      expect(
        row.bottom,
        lessThanOrEqualTo(dialog.bottom),
        reason: '$name runs past the bottom of the dialog',
      );
    }
  });

  testWidgets('the tab does not swipe out from under a slider drag', (
    tester,
  ) async {
    // The slider's own recogniser beats the enclosing PageView's, so no
    // physics override is needed. This says so out loud, since the day it
    // stops being true a slider will start moving in one direction only.
    await pumpDialog(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final track = find.descendant(
      of: find.ancestor(
        of: find.text(l10n.presetAmountLabel),
        matching: find.byType(SliderRow),
      ),
      matching: find.byKey(const Key('sliderRowTrack')),
    );
    await tester.drag(track, const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.presetAmountLabel),
      findsOneWidget,
      reason: 'still on the tone tab — the drag belonged to the slider',
    );
  });
}
