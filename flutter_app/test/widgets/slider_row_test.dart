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
    'a single click on the track jumps to that value immediately — '
    'no waiting on the double-tap disambiguation window',
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
      // Track usable width excludes _trackInset (12px) each side; the
      // midpoint of the usable range lands at value 50.
      final mid = Offset(trackRect.center.dx, trackRect.center.dy);
      await tester.tapAt(mid);
      // Exactly one pump — a regression of the double-tap-arena bug this
      // guards against would require pumping past kDoubleTapTimeout
      // (~300ms) before onTapUp fires at all.
      await tester.pump();

      expect(changed, [50.0]);
      expect(changedEnd, [50.0]);
    },
  );

  testWidgets(
    'two quick clicks near the same spot reset to defaultValue instead of '
    'jumping twice',
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

      // First tap jumps to 50, second (within the window, same spot)
      // resets to defaultValue instead of jumping to 50 again.
      expect(changed, [50.0, 77.0]);
      expect(changedEnd, [50.0, 77.0]);
    },
  );

  // A "two clicks far apart in real time are independent jumps, not a
  // reset" case is deliberately not covered here: the production code
  // uses real DateTime.now() (correct for real usage), but
  // flutter_test's fake-async pump() doesn't advance it, and a genuine
  // wall-clock wait would just slow the suite down for little extra
  // coverage beyond what the two cases above already lock in.
}
