import 'package:darkmoon/widgets/parametric_split_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bar's whole job is that the three handles stay ordered and inside
/// their ranges no matter where the pointer goes. A drag that crossed a
/// neighbour would not look obviously broken — `parametricCurvePoints`
/// re-clamps the splits before building the curve — it would just leave
/// the handle no longer matching the boundary it claims to be. So the
/// clamping is asserted directly.
///
/// Gestures are driven with `startGesture` rather than `tester.drag` so
/// the pointer path is explicit. That matters here: the widget's reset
/// gesture is recognised from the drag lifecycle rather than by a tap
/// recogniser, precisely so that pan is the arena's only member and a
/// handle moves from the first pixel. These tests are what caught the two
/// earlier attempts, where adding a tap or double-tap recogniser made the
/// handles either sluggish or completely undraggable.
void main() {
  const width = 300.0;
  // Mirrors ParametricSplitBar's own geometry.
  const inset = 8.0;
  const usable = width - 2 * inset;
  const midHeight = 8.0;

  double xFor(double value) => inset + (value / 100.0) * usable;

  Future<({List<(String, double)> changed, List<(String, double)> ended})>
  pumpBar(
    WidgetTester tester, {
    double shadow = 25,
    double midtone = 50,
    double highlight = 75,
  }) async {
    final changed = <(String, double)>[];
    final ended = <(String, double)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: ParametricSplitBar(
                shadowSplit: shadow,
                midtoneSplit: midtone,
                highlightSplit: highlight,
                onChanged: (name, value) => changed.add((name, value)),
                onChangeEnd: (name, value) => ended.add((name, value)),
              ),
            ),
          ),
        ),
      ),
    );
    return (changed: changed, ended: ended);
  }

  /// Grabs the handle nearest [fromValue] and drags it to [toValue].
  Future<void> dragHandle(
    WidgetTester tester,
    double fromValue,
    double toValue,
  ) async {
    final origin = tester.getTopLeft(find.byType(ParametricSplitBar));
    final gesture = await tester.startGesture(
      origin + Offset(xFor(fromValue), midHeight),
    );
    // Several steps rather than one jump: a single move can land after the
    // pan is recognised but before any update is delivered, which reports
    // no change at all and looks like a broken widget.
    const steps = 6;
    for (var i = 1; i <= steps; i++) {
      final at = fromValue + (toValue - fromValue) * i / steps;
      await gesture.moveTo(origin + Offset(xFor(at), midHeight));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('dragging a handle reports only its own slider name', (
    tester,
  ) async {
    final calls = await pumpBar(tester);
    await dragHandle(tester, 25, 35);

    expect(calls.changed, isNotEmpty);
    expect(
      calls.changed.map((c) => c.$1).toSet(),
      {'ParamCurveShadowSplit'},
      reason: 'grabbing the leftmost handle must not move another split',
    );
    expect(
      calls.ended.single.$1,
      'ParamCurveShadowSplit',
      reason: 'exactly one commit per gesture, or the render runs twice',
    );
  });

  testWidgets('a handle cannot be dragged past its right neighbour', (
    tester,
  ) async {
    final calls = await pumpBar(tester);
    await dragHandle(tester, 50, 95);

    expect(calls.changed, isNotEmpty);
    final worst = calls.changed
        .map((c) => c.$2)
        .reduce((a, b) => a > b ? a : b);
    expect(
      worst,
      lessThanOrEqualTo(73.0),
      reason: 'midtone must stop 2 short of the highlight split at 75',
    );
  });

  testWidgets('a handle cannot be dragged past its left neighbour', (
    tester,
  ) async {
    final calls = await pumpBar(tester);
    await dragHandle(tester, 50, 2);

    expect(calls.changed, isNotEmpty);
    final lowest = calls.changed
        .map((c) => c.$2)
        .reduce((a, b) => a < b ? a : b);
    expect(
      lowest,
      greaterThanOrEqualTo(27.0),
      reason: 'midtone must stop 2 past the shadow split at 25',
    );
  });

  testWidgets('a handle with no room left stays exactly where it is', (
    tester,
  ) async {
    // Neighbours already closer together than twice the minimum gap, so
    // the clamp window is empty. The bug this guards against is calling
    // num.clamp with lower greater than upper, which throws.
    final calls = await pumpBar(tester, shadow: 40, midtone: 41, highlight: 42);
    await dragHandle(tester, 41, 90);

    expect(
      calls.changed,
      isNotEmpty,
      reason: 'without this the loop below would pass on an empty list',
    );
    for (final call in calls.changed) {
      expect(call.$2, 41.0, reason: 'a pinned handle must not move');
    }
  });

  testWidgets('double-tapping a handle returns it to its default', (
    tester,
  ) async {
    final calls = await pumpBar(tester, shadow: 60, midtone: 70, highlight: 80);
    final origin = tester.getTopLeft(find.byType(ParametricSplitBar));
    final target = origin + Offset(xFor(60), midHeight);

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(target);
    await tester.pump();

    expect(calls.changed, contains(('ParamCurveShadowSplit', 25.0)));
    expect(
      calls.ended,
      contains(('ParamCurveShadowSplit', 25.0)),
      reason: 'a reset must commit too, or the full-quality render never runs',
    );
  });
}
