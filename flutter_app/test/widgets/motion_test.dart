import 'package:darkmoon/animations_config.dart';
import 'package:darkmoon/motion.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the three durations are ordered and short', () {
    expect(DarkmoonMotion.fast < DarkmoonMotion.base, isTrue);
    expect(DarkmoonMotion.base < DarkmoonMotion.slow, isTrue);
    // Nothing in the UI should take longer than a quarter of a second:
    // motion is feedback, not a show.
    expect(DarkmoonMotion.slow.inMilliseconds, lessThanOrEqualTo(250));
  });

  testWidgets('of() collapses every duration when animations are off', (
    tester,
  ) async {
    late Duration on;
    late Duration off;
    await tester.pumpWidget(
      AnimationsConfig(
        enabled: true,
        child: Builder(
          builder: (context) {
            on = DarkmoonMotion.of(context, DarkmoonMotion.slow);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      AnimationsConfig(
        enabled: false,
        child: Builder(
          builder: (context) {
            off = DarkmoonMotion.of(context, DarkmoonMotion.slow);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(on, DarkmoonMotion.slow);
    expect(off, Duration.zero);
  });

  testWidgets('HoverBuilder reports the pointer entering and leaving', (
    tester,
  ) async {
    final seen = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: HoverBuilder(
            builder: (context, hovered, child) {
              seen.add(hovered);
              return SizedBox(width: 40, height: 40, child: child);
            },
            child: const Text('x'),
          ),
        ),
      ),
    );
    expect(seen, [false]);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('x')));
    await tester.pump();
    expect(seen.last, isTrue);
    await gesture.moveTo(Offset.zero);
    await tester.pump();
    expect(seen.last, isFalse);
    // The child is passed through, not rebuilt by the hover.
    expect(find.text('x'), findsOneWidget);
  });
}
