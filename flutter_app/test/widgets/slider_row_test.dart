import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/widgets/slider_row.dart';

void main() {
  Future<void> pumpSlider(
    WidgetTester tester, {
    required double value,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    double? defaultValue,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              child: SliderRow(
                name: 'Test',
                min: 0,
                max: 100,
                decimals: 0,
                value: value,
                defaultValue: defaultValue,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'a single click on the track does nothing — click-to-jump-to-position '
    'is disabled (2026-09-01), only double-click-to-reset remains',
    (tester) async {
      final changed = <double>[];
      final changedEnd = <double>[];
      await pumpSlider(
        tester,
        value: 10,
        defaultValue: 77,
        onChanged: changed.add,
        onChangeEnd: changedEnd.add,
      );

      final trackRect = tester.getRect(find.byKey(const Key('sliderRowTrack')));
      final mid = Offset(trackRect.center.dx, trackRect.center.dy);
      await tester.tapAt(mid);
      await tester.pump(const Duration(milliseconds: 350));

      expect(changed, isEmpty);
      expect(changedEnd, isEmpty);
    },
  );

  testWidgets(
    'two quick clicks near the same spot reset to defaultValue',
    (tester) async {
      final changed = <double>[];
      final changedEnd = <double>[];
      await pumpSlider(
        tester,
        value: 10,
        defaultValue: 77,
        onChanged: changed.add,
        onChangeEnd: changedEnd.add,
      );

      final trackRect = tester.getRect(find.byKey(const Key('sliderRowTrack')));
      final tapPoint = Offset(trackRect.center.dx, trackRect.center.dy);
      await tester.tapAt(tapPoint);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(tapPoint);
      await tester.pump();

      // The first tap is a no-op (click-to-jump disabled); the second,
      // within the window and same spot, resets to defaultValue.
      expect(changed, [77.0]);
      expect(changedEnd, [77.0]);
    },
  );

  // A "two clicks far apart in real time are independent jumps, not a
  // reset" case is deliberately not covered here: the production code
  // uses real DateTime.now() (correct for real usage), but
  // flutter_test's fake-async pump() doesn't advance it, and a genuine
  // wall-clock wait would just slow the suite down for little extra
  // coverage beyond what the two cases above already lock in.
}
