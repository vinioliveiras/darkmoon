import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/animations_config.dart';
import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/presets/preset.dart';
import 'package:darkmoon/widgets/preset_panel.dart';

/// The PRESETS heading has to start where the FOLDERS heading above it
/// does — both sit 12px in from the sidebar's left edge.
///
/// It did not. The heading is wrapped in an AnimatedSwitcher, so that the
/// title can cross-fade into the "n selected" count, and AnimatedSwitcher
/// centres its child by default. Inside an Expanded that put the word in
/// the middle of the panel, which reads as a misaligned heading rather
/// than as a centred one (2026-09-09, user's screenshot).
void main() {
  const inset = 12.0;
  const panelWidth = 300.0;

  Future<Rect> headerRect(WidgetTester tester, {required int presets}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AnimationsConfig(
            enabled: false,
            child: SizedBox(
              width: panelWidth,
              height: 600,
              child: PresetPanel(
                presets: [
                  for (var i = 0; i < presets; i++)
                    Preset(id: '$i', name: 'Preset $i', values: const {}),
                ],
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
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    return tester.getRect(find.text(l10n.sidebarPresetsSection));
  }

  testWidgets('the heading starts at the sidebar inset, not centred', (
    tester,
  ) async {
    final rect = await headerRect(tester, presets: 2);
    expect(
      rect.left,
      closeTo(inset, 0.5),
      reason:
          'centred, this lands near the middle of the $panelWidth-wide panel',
    );
  });

  testWidgets('every action button hovers on its own glyph', (tester) async {
    // The hover highlight fills the button's tap target, so the icon has
    // to sit at the centre of it. Both the header buttons and each row's
    // menu carried the scrollbar gutter as the button's *own* padding,
    // which made the target fourteen points wider than the glyph and put
    // the highlight beside it rather than on it (2026-09-09).
    await headerRect(tester, presets: 3);

    // The loops below pass trivially over an empty panel, and this test
    // would then guard nothing at all.
    expect(find.byType(IconButton), findsWidgets);

    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(
        button.padding,
        EdgeInsets.zero,
        reason:
            'padding inside an icon button is part of what lights up on '
            'hover — put spacing outside it',
      );
    }

    for (final icon in find.byType(Icon).evaluate()) {
      final iconFinder = find.byWidget(icon.widget);
      final buttons = find.ancestor(
        of: iconFinder,
        matching: find.byType(IconButton),
      );
      if (buttons.evaluate().isEmpty) {
        continue;
      }
      expect(
        tester.getCenter(iconFinder),
        offsetMoreOrLessEquals(tester.getCenter(buttons.first), epsilon: 0.5),
      );
    }
  });

  testWidgets('and does not move when the buttons beside it change', (
    tester,
  ) async {
    // The trailing slots collapse when there are no presets to act on, so
    // the space left of them changes. A left-aligned heading does not care;
    // a centred one slides.
    final empty = await headerRect(tester, presets: 0);
    final populated = await headerRect(tester, presets: 5);
    expect(empty.left, closeTo(populated.left, 0.5));
  });
}
