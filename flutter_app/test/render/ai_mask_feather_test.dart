import 'dart:typed_data';

import 'package:darkmoon/render/mask.dart';
import 'package:flutter_test/flutter_test.dart';

/// An AI mask's feather softens the segmentation's edge: with it the
/// edge ramps over several pixels, without it the map's own step stays.
void main() {
  const width = 100, height = 40;

  Float32List alphaFor(double feather) {
    // The model said: left half in, right half out.
    final data = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        data[y * width + x] = x < 50 ? 255 : 0;
      }
    }
    final mask = MaskLayer(
      id: 's',
      name: 's',
      type: MaskType.subject,
      subject: SubjectGeometry(feather: feather),
    );
    return computeMaskAlpha(
      mask,
      width,
      height,
      aiMap: AiMaskMap(width: width, height: height, data: data),
    );
  }

  test('no feather keeps the step', () {
    final alpha = alphaFor(0);
    expect(alpha[20 * width + 48], 1.0);
    expect(alpha[20 * width + 51], 0.0);
  });

  test('a feather ramps the edge and leaves the far pixels alone', () {
    final alpha = alphaFor(100);
    final row = 20 * width;
    expect(alpha[row + 49], greaterThan(0.3));
    expect(alpha[row + 49], lessThan(0.8));
    expect(alpha[row + 52], greaterThan(0.1));
    expect(alpha[row + 52], lessThan(0.6));
    expect(alpha[row + 5], closeTo(1.0, 0.01));
    expect(alpha[row + 95], closeTo(0.0, 0.01));
    expect(alpha[row + 49], greaterThan(alpha[row + 52]));
  });

  test('the geometry keeps its feather through copyWith', () {
    const g = SubjectGeometry(feather: 30);
    expect(g.copyWith(startX: 0.1).feather, 30);
    expect(const SubjectGeometry().feather, 0);
  });
}
