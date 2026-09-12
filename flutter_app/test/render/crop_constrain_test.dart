import 'package:darkmoon/render/crop_transform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const w = 600, h = 400;

  test('an untransformed frame is valid everywhere', () {
    final quad = validCanvasQuad(const CropTransformParams(), w, h);
    final rect = largestInscribedRect(quad);
    expect(rect.left, closeTo(0, 1e-6));
    expect(rect.top, closeTo(0, 1e-6));
    expect(rect.right, closeTo(1, 1e-6));
    expect(rect.bottom, closeTo(1, 1e-6));
  });

  test('a straightened frame loses its empty corners', () {
    const params = CropTransformParams(straightenAngle: 8);
    final quad = validCanvasQuad(params, w, h);
    final rect = largestInscribedRect(quad);
    // Smaller than the frame, still most of it, and centred.
    final area = (rect.right - rect.left) * (rect.bottom - rect.top);
    expect(area, lessThan(0.9));
    expect(area, greaterThan(0.55));
    expect((rect.left + rect.right) / 2, closeTo(0.5, 0.03));
    expect((rect.top + rect.bottom) / 2, closeTo(0.5, 0.03));
    expect(rectInsideQuad(rect, quad), isTrue);
    // The full frame is not inside the rotated content.
    expect(
      rectInsideQuad((left: 0, top: 0, right: 1, bottom: 1), quad),
      isFalse,
    );
  });

  test('a fixed aspect keeps the rectangle at that ratio', () {
    const params = CropTransformParams(straightenAngle: 5, vertical: 30);
    final quad = validCanvasQuad(params, w, h);
    final rect = largestInscribedRect(
      quad,
      aspect: 1.0,
      canvasWidth: w,
      canvasHeight: h,
    );
    final widthPx = (rect.right - rect.left) * w;
    final heightPx = (rect.bottom - rect.top) * h;
    expect(widthPx / heightPx, closeTo(1.0, 0.02));
    expect(rectInsideQuad(rect, quad), isTrue);
  });

  test('a keystone correction also leaves corners to cut', () {
    const params = CropTransformParams(vertical: 40);
    final quad = validCanvasQuad(params, w, h);
    final rect = largestInscribedRect(quad);
    // A vertical keystone pulls the top corners inward, so the cut is on
    // the sides, not at the top.
    expect(rect.left, greaterThan(0.0));
    expect(rect.right, lessThan(1.0));
    expect(rect.top, closeTo(0.0, 0.02));
    expect(rectInsideQuad(rect, quad), isTrue);
  });

  test('constrainCrop snaps to the largest valid crop and keeps a crop '
      'that already fits', () {
    const rotated = CropTransformParams(straightenAngle: 6, constrain: true);
    final snapped = constrainCrop(rotated, w, h, snap: true);
    expect(snapped.cropLeft, greaterThan(0));
    expect(snapped.cropRight, lessThan(1));
    // A smaller crop inside the valid area is left alone when not
    // snapping; one poking outside is replaced.
    final small = snapped.copyWith(
      cropLeft: snapped.cropLeft + 0.1,
      cropTop: snapped.cropTop + 0.1,
      cropRight: snapped.cropRight - 0.1,
      cropBottom: snapped.cropBottom - 0.1,
    );
    final kept = constrainCrop(small, w, h, snap: false);
    expect(kept.cropLeft, small.cropLeft);
    final outside = rotated.copyWith(cropLeft: 0, cropTop: 0);
    final fixed = constrainCrop(outside, w, h, snap: false);
    expect(fixed.cropLeft, snapped.cropLeft);
    // Without the switch nothing moves.
    final off = const CropTransformParams(straightenAngle: 6, constrain: false);
    expect(constrainCrop(off, w, h, snap: true).cropLeft, 0);
  });
}
