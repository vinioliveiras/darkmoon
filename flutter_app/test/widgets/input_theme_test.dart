import 'package:darkmoon/theme.dart';
import 'package:darkmoon/widgets/glass_input_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every text field inherits the macOS-style border from the theme: a
/// filled, rounded glass outline whose focused state carries a halo. A
/// search box asks for the capsule and keeps the rest.
void main() {
  testWidgets('a bare TextField gets the glass border and fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkmoonTheme(),
        home: const Scaffold(body: TextField()),
      ),
    );
    final decorator = tester.widget<InputDecorator>(
      find.byType(InputDecorator),
    );
    final decoration = decorator.decoration;
    expect(decoration.filled, isTrue);
    expect(decoration.fillColor, DarkmoonColors.inputFill);
    final enabled = decoration.enabledBorder;
    expect(enabled, isA<GlassInputBorder>());
    expect((enabled! as GlassInputBorder).borderRadius.topLeft.x, 8);
    expect((enabled as GlassInputBorder).halo.a, 0);
    // Focus brightens the outline and adds nothing around it.
    final focused = decoration.focusedBorder;
    expect(focused, isA<GlassInputBorder>());
    expect((focused! as GlassInputBorder).halo.a, 0);
    expect(focused.borderSide.color, DarkmoonColors.inputOutlineFocused);
  });

  testWidgets('the capsule decoration rounds every border fully', (
    tester,
  ) async {
    late InputDecoration decoration;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkmoonTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              decoration = capsuleInputDecoration(context, hintText: 'find');
              return TextField(decoration: decoration);
            },
          ),
        ),
      ),
    );
    for (final border in [
      decoration.enabledBorder,
      decoration.focusedBorder,
      decoration.disabledBorder,
    ]) {
      expect(border, isA<GlassInputBorder>());
      expect((border! as GlassInputBorder).borderRadius.topLeft.x, 999);
    }
    expect(decoration.hintText, 'find');
  });

  test('the focus lerp fades the halo in instead of popping it', () {
    const idle = GlassInputBorder();
    const focused = GlassInputBorder(halo: Color(0x80FFFFFF));
    final half = focused.lerpFrom(idle, 0.5)! as GlassInputBorder;
    expect(half.halo.a, closeTo(0.25, 0.02));
    final back = idle.lerpFrom(focused, 0.5)! as GlassInputBorder;
    expect(back.halo.a, closeTo(0.25, 0.02));
  });
}
