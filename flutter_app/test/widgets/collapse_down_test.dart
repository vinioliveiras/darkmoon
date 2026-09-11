import 'package:darkmoon/widgets/collapse_down.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bottom strip folds down and away: mid-way its box is shorter and
/// its content has moved down; hidden, nothing is built; shown again, it
/// is back at full height.
void main() {
  const childKey = Key('strip');

  Widget host(bool shown) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const Expanded(child: SizedBox()),
          CollapseDown(
            shown: shown,
            duration: const Duration(milliseconds: 200),
            child: const SizedBox(key: childKey, height: 100),
          ),
        ],
      ),
    ),
  );

  testWidgets('folds the strip down and away, then brings it back', (
    tester,
  ) async {
    await tester.pumpWidget(host(true));
    expect(tester.getSize(find.byType(CollapseDown)).height, 100);
    final restingTop = tester.getTopLeft(find.byKey(childKey)).dy;

    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(milliseconds: 100));
    final midHeight = tester.getSize(find.byType(CollapseDown)).height;
    expect(midHeight, greaterThan(0));
    expect(midHeight, lessThan(100));
    // The content slides down inside its shrinking box: its top is
    // lower on screen than where the box now starts.
    final boxTop = tester.getTopLeft(find.byType(CollapseDown)).dy;
    expect(tester.getTopLeft(find.byKey(childKey)).dy, greaterThan(boxTop));
    expect(tester.getTopLeft(find.byKey(childKey)).dy, greaterThan(restingTop));

    await tester.pumpAndSettle();
    expect(find.byKey(childKey), findsNothing);
    expect(tester.getSize(find.byType(CollapseDown)).height, 0);

    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(find.byKey(childKey), findsOneWidget);
    expect(tester.getSize(find.byType(CollapseDown)).height, 100);
  });
}
