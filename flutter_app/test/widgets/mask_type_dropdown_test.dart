import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/render/mask.dart';
import 'package:darkmoon/widgets/mask_selector.dart';
import 'package:darkmoon/widgets/styled_dropdown.dart';

/// Mounts [MaskSelector] on a canvas tall enough that nothing is cut off
/// by the window rather than by the menu's own height cap — the point of
/// these tests is the cap, so the window must not be the thing under test.
Future<void> pumpSelector(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: MaskSelector(
              masks: const [],
              activeId: imageMaskId,
              onSelect: (_) {},
              onAdd: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the add-mask menu shows every mask type at once', (
    tester,
  ) async {
    await pumpSelector(tester);

    await tester.tap(find.byIcon(CupertinoIcons.add).hitTestable().first);
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final labels = [
      l10n.maskLinearGradient,
      l10n.maskRadialGradient,
      l10n.maskBrush,
      l10n.maskColorRange,
      l10n.maskLuminance,
      l10n.maskFlow,
      l10n.maskWholeImage,
      l10n.maskSubject,
      l10n.maskSky,
      l10n.maskForeground,
      l10n.maskDepth,
    ];
    // One entry per MaskType, so a type added without a menu entry (or a
    // menu entry left behind after a type is removed) fails here.
    expect(labels.length, MaskType.values.length);

    for (final label in labels) {
      // hitTestable(): a row scrolled out of the menu's viewport still
      // exists in the tree, so findsOneWidget alone would pass on exactly
      // the scrolling this test exists to rule out.
      expect(
        find.text(label).hitTestable(),
        findsOneWidget,
        reason: '"$label" is not visible without scrolling the menu',
      );
    }
  });

  testWidgets('a tall menu opens upward when the trigger is near the bottom', (
    tester,
  ) async {
    // Driven through StyledDropdown directly rather than MaskSelector:
    // the selector sizes itself to its parent, so it cannot be pushed to
    // the bottom of a window, and where the trigger sits is the whole
    // point here.
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              StyledDropdown<int>(
                value: null,
                placeholder: 'Add',
                items: [
                  for (var i = 0; i < 11; i++)
                    StyledDropdownItem(value: i, label: 'Item $i'),
                ],
                maxMenuHeight: 560,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final trigger = find.text('Add');
    final buttonRect = tester.getRect(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    // Before the flip existed the menu was positioned below the button
    // unconditionally and ran straight off the bottom of the window.
    final firstRow = tester.getRect(find.text('Item 0'));
    final lastRow = tester.getRect(find.text('Item 10'));
    expect(firstRow.top, greaterThanOrEqualTo(0.0));
    expect(lastRow.bottom, lessThanOrEqualTo(600.0));
    expect(lastRow.bottom, lessThanOrEqualTo(buttonRect.top));
  });
}
