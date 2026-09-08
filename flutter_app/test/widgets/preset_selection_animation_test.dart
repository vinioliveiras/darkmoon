import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/animations_config.dart';
import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/presets/preset.dart';
import 'package:darkmoon/widgets/preset_panel.dart';

Preset preset(String id) =>
    Preset(id: id, name: 'Preset $id', values: const {});

Future<void> pumpPanel(
  WidgetTester tester, {
  bool animationsEnabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AnimationsConfig(
          enabled: animationsEnabled,
          child: SizedBox(
            width: 300,
            height: 600,
            child: PresetPanel(
              presets: [preset('a'), preset('b')],
              enabled: true,
              isApplied: (_) => false,
              onApply: (_) {},
              onSaveNew: () {},
              onImport: () {},
              onRename: (_) {},
              onExport: (_) {},
              onDelete: (_) {},
              onDeleteMany: (_) {},
              onExportMany: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Width of the collapsing slot wrapping the button with [tooltip].
///
/// The button itself keeps its intrinsic size throughout — it is the slot
/// around it that opens and closes — so measuring the button would report
/// the same number before, during and after the transition and pass no
/// matter what.
double slotWidth(WidgetTester tester, String tooltip) => tester
    .getSize(
      find
          .ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(ClipRect),
          )
          .first,
    )
    .width;

void main() {
  testWidgets('entering selection mode animates rather than snapping', (
    tester,
  ) async {
    await pumpPanel(tester);

    // The row checkboxes' slots exist collapsed before the mode is on.
    final collapsed = tester
        .widgetList<ClipRect>(find.byType(ClipRect))
        .length;
    expect(collapsed, greaterThan(0));

    await tester.tap(find.byTooltip('Select presets').first);
    await tester.pump();

    // One frame in, part-way through: the cancel button has started to
    // appear but has not reached full width. Without the animation this
    // frame would already be the finished state.
    await tester.pump(const Duration(milliseconds: 60));
    final mid = slotWidth(tester, 'Cancel');
    await tester.pumpAndSettle();
    final settled = slotWidth(tester, 'Cancel');
    expect(mid, greaterThan(0.0));
    expect(
      mid,
      lessThan(settled),
      reason: 'the cancel button should still be growing 60ms in',
    );
  });

  testWidgets('leaving selection mode animates back', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.byTooltip('Select presets').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cancel').first);
    await tester.pump(const Duration(milliseconds: 60));
    // Still on screen, mid-collapse, rather than gone the instant it was
    // pressed.
    expect(find.byTooltip('Cancel'), findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('Settings > Interface animations off snaps instantly', (
    tester,
  ) async {
    await pumpPanel(tester, animationsEnabled: false);

    await tester.tap(find.byTooltip('Select presets').first);
    // A single frame with no elapsed time: with animations off the header
    // must already be in its final state, which is the whole contract of
    // AnimationsConfig.
    await tester.pump();
    final immediate = slotWidth(tester, 'Cancel');
    await tester.pumpAndSettle();
    expect(slotWidth(tester, 'Cancel'), immediate);
    expect(immediate, greaterThan(0.0));
  });
}
