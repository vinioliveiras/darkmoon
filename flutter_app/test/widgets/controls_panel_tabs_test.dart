import 'package:darkmoon/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show TabBar;
import 'package:flutter_test/flutter_test.dart';

/// Guards the coupling that made five sections disappear.
///
/// Tone Curve, Color Curve, Color Mixer, Color Grading, Effects and Lens
/// Correction are not entries of `_sections`; they were written inside the
/// loop over that map, emitted on its DETAIL iteration. Harmless while the
/// loop always ran every entry. The moment the tabs filtered it, DETAIL
/// only came up under Adjust and those six stopped existing on every other
/// tab — Effects was empty. Nothing threw. They were simply gone.
///
/// The tabs themselves cannot be clicked here: with no photo open the
/// controls panel sits inside an IgnorePointer, so a tap never reaches
/// them. What this checks instead is sharper anyway — DETAIL now lives on
/// its own tab, so Tone Curve appearing on the *opening* tab is proof that
/// it no longer depends on DETAIL being emitted.
void main() {
  Future<void> pumpEditor(WidgetTester tester) async {
    // The 800x600 default is narrower than this app ever runs at and its
    // toolbar overflows as a harness artefact.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const DarkmoonApp());
    // The splash holds a fixed-duration timer the harness will complain
    // about if it never fires.
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('the opening tab carries its own sections', (tester) async {
    await pumpEditor(tester);

    for (final section in ['WHITE BALANCE', 'TONE']) {
      expect(find.text(section), findsOneWidget, reason: '$section is Adjust');
    }
  });

  testWidgets('Tone Curve does not depend on Detail being on the same tab', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(
      find.text('DETAIL'),
      findsNothing,
      reason: 'Detail has its own tab now, so it is not on the opening one',
    );
    expect(
      find.text('TONE CURVE'),
      findsOneWidget,
      reason:
          'Tone Curve is written outside _sections and used to be emitted '
          'from inside the loop on its DETAIL iteration. With Detail gone '
          'from this tab, it can only be here if that coupling is gone too.',
    );
  });

  testWidgets('sections from other tabs are not on the opening one', (
    tester,
  ) async {
    await pumpEditor(tester);

    for (final section in [
      'PRESENCE',
      'COLOR PROFILE',
      'COLOR MIXER',
      'COLOR GRADING',
      'EFFECTS',
      'LENS CORRECTION',
    ]) {
      expect(
        find.text(section),
        findsNothing,
        reason: '$section belongs to another tab',
      );
    }
  });

  testWidgets('all four tabs are present', (tester) async {
    await pumpEditor(tester);

    // Declared in tab order: Adjust, Details, Colour, Effects. The bar
    // carries these as words now rather than glyphs (2026-09-07).
    //
    // Scoped to the TabBar rather than searched app-wide, so a section
    // header sharing one of these words cannot make this assert about the
    // wrong widget.
    const labels = ['Adjust', 'Details', 'Colour', 'Effects'];
    final lefts = <double>[];
    for (final label in labels) {
      final tab = find.descendant(
        of: find.byType(TabBar),
        matching: find.text(label),
      );
      expect(tab, findsOneWidget, reason: '$label is missing from the bar');
      lefts.add(tester.getRect(tab).left);
    }
    expect(
      lefts,
      orderedEquals(([...lefts]..sort())),
      reason: 'the tabs must read left to right in their declared order',
    );
  });
}
