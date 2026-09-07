import 'package:darkmoon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Switching a section off collapses it, and switching it back on opens
/// it again.
///
/// With no photo open the controls panel sits inside an IgnorePointer, so
/// a tap never reaches the switch. The callback is invoked directly
/// instead — which exercises exactly the wiring this covers, since the
/// question is what the panel does when told the switch moved, not
/// whether Flutter routes a tap.
///
/// Collapsing does not remove anything from the tree — the body is held
/// at zero height and zero opacity so it can animate — so finding the
/// sliders proves nothing either way. The assertion is on the height
/// factor that does the collapsing.
void main() {
  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const DarkmoonApp());
    // The splash holds a fixed-duration timer the harness complains about
    // if it never fires.
    await tester.pump(const Duration(seconds: 5));
  }

  /// The section card wrapping [label], found by type name since the card
  /// is private to editor_screen.dart.
  Finder cardFor(String label) => find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_SectionCard',
        ),
      )
      .first;

  /// The collapse target for the body of [label]'s section: 1 open, 0
  /// collapsed.
  double heightFactorOf(WidgetTester tester, String label) {
    final align = tester.widget<AnimatedAlign>(
      find
          .descendant(of: cardFor(label), matching: find.byType(AnimatedAlign))
          .first,
    );
    return align.heightFactor!;
  }

  void setSwitch(WidgetTester tester, String label, {required bool on}) {
    final toggle = tester.widget<Switch>(
      find.descendant(of: cardFor(label), matching: find.byType(Switch)).first,
    );
    toggle.onChanged!(on);
  }

  /// Moving a switch also tells the editor its edit changed, which starts
  /// the render debounce. Left pending, that timer fails the test at
  /// teardown on a complaint that has nothing to do with what is being
  /// checked here.
  Future<void> drainDebounce(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 2));

  testWidgets('turning a section off collapses it, and on reopens it', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(
      heightFactorOf(tester, 'WHITE BALANCE'),
      1.0,
      reason: 'sections start open',
    );

    setSwitch(tester, 'WHITE BALANCE', on: false);
    await tester.pump();
    expect(
      heightFactorOf(tester, 'WHITE BALANCE'),
      0.0,
      reason: 'a section that does nothing should not keep its controls up',
    );

    setSwitch(tester, 'WHITE BALANCE', on: true);
    await tester.pump();
    expect(
      heightFactorOf(tester, 'WHITE BALANCE'),
      1.0,
      reason:
          'a section that is on but still collapsed reads as broken — '
          'nothing visible changed when it was enabled',
    );

    await drainDebounce(tester);
  });

  testWidgets('collapsing one section leaves the others alone', (tester) async {
    await pumpEditor(tester);

    setSwitch(tester, 'WHITE BALANCE', on: false);
    await tester.pump();

    expect(
      heightFactorOf(tester, 'TONE'),
      1.0,
      reason: 'only the section whose switch moved may close',
    );

    await drainDebounce(tester);
  });
}
