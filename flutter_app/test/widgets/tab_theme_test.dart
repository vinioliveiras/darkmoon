import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:darkmoon/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The selected tab has to swallow the rule that runs under the tab bar,
/// which is a one-pixel-row claim no ordinary widget test can see: the
/// widget tree is identical whether the erasure lands on the right row,
/// one row off, or not at all. So this renders the bar and reads the
/// pixels.
void main() {
  const barWidth = 300.0;
  final boundaryKey = GlobalKey();

  /// The rendered tab bar, plus where it sits inside the captured image.
  Future<({ByteData pixels, int width, Rect bar})> renderTabBar(
    WidgetTester tester, {
    double shift = 0.0,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkmoonTheme(),
        home: DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: DarkmoonColors.panel,
            body: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundaryKey,
                child: Padding(
                  // [shift] puts the bar on a half-pixel boundary, which
                  // is where the rule stopped being covered cleanly.
                  padding: EdgeInsets.only(top: shift),
                  child: Container(
                  width: barWidth,
                  color: DarkmoonColors.panel,
                  child: const TabBar(
                    tabs: [
                      Tab(height: kTabHeight, text: 'One'),
                      Tab(height: kTabHeight, text: 'Two'),
                      Tab(height: kTabHeight, text: 'Three'),
                    ],
                  ),
                ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    // Rasterising has to happen outside the test's fake-async zone: the
    // future `toImage` returns is completed by the engine, which that zone
    // never pumps, so awaiting it directly hangs the test forever rather
    // than failing.
    late ByteData pixels;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    final origin = tester.getTopLeft(find.byKey(boundaryKey));
    final bar = tester.getRect(find.byType(TabBar)).shift(-origin);
    return (pixels: pixels, width: boundary.size.width.round(), bar: bar);
  }

  Color pixelAt(ByteData data, int width, int x, int y) {
    final i = (y * width + x) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }

  testWidgets('the rule under the bar stops at the selected tab', (
    tester,
  ) async {
    final (:pixels, :width, :bar) = await renderTabBar(tester);

    // The rule Flutter draws is one pixel tall at the bar's bottom edge.
    final ruleY = bar.bottom.round() - 1;
    final tabWidth = bar.width / 3;
    final selectedX = (bar.left + tabWidth * 0.5).round();
    final unselectedX = (bar.left + tabWidth * 2.5).round();

    expect(
      pixelAt(pixels, width, unselectedX, ruleY),
      DarkmoonColors.divider,
      reason: 'the rule must still run under the tabs that are not selected',
    );
    expect(
      pixelAt(pixels, width, selectedX, ruleY),
      DarkmoonColors.panel,
      reason:
          'under the selected tab the rule must be gone, so the tab and '
          'the panel below it read as one surface',
    );
  });

  testWidgets('the selected tab is outlined on three sides, not filled', (
    tester,
  ) async {
    final (:pixels, :width, :bar) = await renderTabBar(tester);

    final tabWidth = bar.width / 3;
    final centreX = (bar.left + tabWidth * 0.5).round();

    expect(
      pixelAt(pixels, width, centreX, bar.top.round()),
      DarkmoonColors.divider,
      reason: 'the top edge is drawn',
    );
    // Just inside the top edge, away from the label, nothing is painted.
    expect(
      pixelAt(pixels, width, (bar.left + 3).round(), (bar.top + 6).round()),
      DarkmoonColors.panel,
      reason: 'an outline, not a fill — the tab body stays bare',
    );
  });

  testWidgets('the selected tab has square bottom corners', (tester) async {
    final (:pixels, :width, :bar) = await renderTabBar(tester);

    // The left edge is drawn on the tab's first pixel column and must run
    // all the way down: a rounded bottom would leave the last rows bare.
    final edgeX = bar.left.round();
    expect(
      pixelAt(pixels, width, edgeX, bar.bottom.round() - 2),
      DarkmoonColors.divider,
      reason: 'the outline reaches the bottom instead of curving away',
    );
    // The top corner, by contrast, is rounded, so that same column is
    // bare where the curve has pulled the edge inwards.
    expect(
      pixelAt(pixels, width, edgeX, bar.top.round()),
      DarkmoonColors.panel,
      reason: 'the top corners are still rounded',
    );
  });

  testWidgets('the rule stays covered when the bar lands on a half pixel', (
    tester,
  ) async {
    // A dialog whose content changes height lands here half the time, and
    // it is where a cover exactly the width of the rule stops working:
    // both get antialiased across the same two rows and 50% over 50%
    // leaves a quarter of the rule showing. Reported as a line under the
    // tabs appearing out of nowhere partway through using a dialog.
    final (:pixels, :width, :bar) = await renderTabBar(tester, shift: 0.5);

    final tabWidth = bar.width / 3;
    final selectedX = (bar.left + tabWidth * 0.5).round();
    final unselectedX = (bar.left + tabWidth * 2.5).round();

    // Either row can hold the rule once it is off the grid, so check both.
    for (final y in [bar.bottom.floor() - 1, bar.bottom.floor()]) {
      expect(
        pixelAt(pixels, width, selectedX, y),
        DarkmoonColors.panel,
        reason: 'row $y under the selected tab still shows part of the rule',
      );
    }
    expect(
      [
        pixelAt(pixels, width, unselectedX, bar.bottom.floor() - 1),
        pixelAt(pixels, width, unselectedX, bar.bottom.floor()),
      ],
      isNot(everyElement(DarkmoonColors.panel)),
      reason: 'the rule must still be there under the other tabs',
    );
  });
}
