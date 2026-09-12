import 'package:darkmoon/render/mask.dart';
import 'package:flutter_test/flutter_test.dart';

/// The linear gradient's feather narrows the fade around the midpoint:
/// at 100 it is the old whole-span ramp, lower is a tighter band, and
/// the midpoint stays at half strength throughout.
void main() {
  const width = 100, height = 1;

  double alphaAt(double feather, int x) {
    final mask = MaskLayer(
      id: 'l',
      name: 'l',
      type: MaskType.linearGradient,
      linear: LinearGradientGeometry(
        startX: 0,
        startY: 0.5,
        endX: 1,
        endY: 0.5,
        feather: feather,
      ),
    );
    return computeMaskAlpha(mask, width, height)[x];
  }

  test('at 100 the fade runs the whole span, as before', () {
    expect(alphaAt(100, 0), closeTo(0.995, 0.01));
    expect(alphaAt(100, 25), closeTo(0.745, 0.01));
    expect(alphaAt(100, 50), closeTo(0.495, 0.01));
    expect(alphaAt(100, 99), closeTo(0.005, 0.01));
  });

  test('a narrower feather is a band around the midpoint', () {
    expect(alphaAt(20, 25), 1.0);
    expect(alphaAt(20, 45), closeTo(0.725, 0.03));
    expect(alphaAt(20, 50), closeTo(0.495, 0.03));
    expect(alphaAt(20, 75), 0.0);
  });

  test('the geometry round-trips its feather through copyWith', () {
    const g = LinearGradientGeometry(feather: 30);
    expect(g.copyWith(startX: 0.1).feather, 30);
    expect(g.copyWith(feather: 55).feather, 55);
    expect(const LinearGradientGeometry().feather, 100);
  });
}
