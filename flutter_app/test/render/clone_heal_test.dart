import 'dart:typed_data';

import 'package:darkmoon/render/inpaint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A frame that is dark on the left half and bright on the right, with a
/// fine texture everywhere, and a red blot in the middle of the left half.
Uint8List _frame(int w, int h) {
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      final base = x < w ~/ 2 ? 60 : 180;
      final texture = ((x * 7 + y * 13) % 5) * 3;
      rgb[i] = base + texture;
      rgb[i + 1] = base + texture;
      rgb[i + 2] = base + texture;
    }
  }
  for (var y = 20; y < 40; y++) {
    for (var x = 20; x < 40; x++) {
      final i = (y * w + x) * 3;
      rgb[i] = 220;
      rgb[i + 1] = 30;
      rgb[i + 2] = 30;
    }
  }
  return rgb;
}

Float32List _hole(int w, int h) {
  final alpha = Float32List(w * h);
  for (var y = 18; y < 42; y++) {
    for (var x = 18; x < 42; x++) {
      alpha[y * w + x] = 1;
    }
  }
  return alpha;
}

double _mean(Uint8List rgb, int w, int x0, int y0, int x1, int y1) {
  var sum = 0.0;
  var n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      sum += rgb[(y * w + x) * 3];
      n++;
    }
  }
  return sum / n;
}

void main() {
  const w = 120, h = 60;
  final frame = _frame(w, h);
  final hole = _hole(w, h);

  test('clone copies the shifted source pixels into the hole', () {
    final out = cloneRegion(frame, w, h, hole, offsetX: 60, offsetY: 0);
    // The blot is gone: the hole now holds the right half's bright grey.
    expect(_mean(out, w, 20, 20, 40, 40), closeTo(186, 4));
    // Outside the hole nothing moved.
    expect(out[(10 * w + 10) * 3], frame[(10 * w + 10) * 3]);
    expect(out[(50 * w + 100) * 3], frame[(50 * w + 100) * 3]);
    // A partial alpha blends rather than replaces.
    final soft = Float32List.fromList(hole)..[(30 * w + 30)] = 0.5;
    final half = cloneRegion(frame, w, h, soft, offsetX: 60, offsetY: 0);
    expect(half[(30 * w + 30) * 3], closeTo((220 + 186) / 2, 6));
  });

  test('heal keeps the source texture but the hole\'s own brightness', () {
    final out = cloneRegion(
      frame,
      w,
      h,
      hole,
      offsetX: 60,
      offsetY: 0,
      fill: CloneFill.heal,
    );
    // The blot is gone and the fill matches the dark left half, not the
    // bright source — the seam is invisible.
    expect(_mean(out, w, 20, 20, 40, 40), closeTo(66, 6));
    // Texture survived: the fill is not flat.
    var minV = 255, maxV = 0;
    for (var y = 24; y < 36; y++) {
      for (var x = 24; x < 36; x++) {
        final v = out[(y * w + x) * 3];
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
    }
    expect(maxV - minV, greaterThanOrEqualTo(6));
    // Border continuity: the row just inside the hole is close to the
    // row just outside it.
    final inside = _mean(out, w, 18, 18, 42, 19);
    final outside = _mean(out, w, 18, 17, 42, 18);
    expect((inside - outside).abs(), lessThan(8));
  });

  test('an empty hole leaves the frame as it is', () {
    final none = Float32List(w * h);
    expect(
      identical(cloneRegion(frame, w, h, none, offsetX: 5, offsetY: 5), frame),
      isTrue,
    );
  });

  test('a generative patch is laid over the hole only', () {
    final patch = img.Image(width: 10, height: 10, numChannels: 3);
    img.fill(patch, color: img.ColorRgb8(0, 0, 255));
    final out = compositePatch(
      frame,
      w,
      h,
      hole,
      patch,
      left: 18 / w,
      top: 18 / h,
      patchWidth: 24 / w,
      patchHeight: 24 / h,
    );
    expect(out[(30 * w + 30) * 3 + 2], 255);
    expect(out[(30 * w + 30) * 3], 0);
    // Outside the hole but inside the patch rectangle nothing changes
    // (the hole and the rectangle coincide here, so check just outside).
    expect(out[(17 * w + 30) * 3], frame[(17 * w + 30) * 3]);
  });
}
