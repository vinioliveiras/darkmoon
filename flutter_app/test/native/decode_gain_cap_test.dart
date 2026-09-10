import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/native/camera_match.dart';
import 'package:darkmoon/render/color_space.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The decode-time gain cap (2026-09-10): a RAW decode with LibRaw's
/// auto-bright off may be brightened inside LibRaw, but only until it
/// would clip more of the frame than the camera's own preview does.

/// [count] pixels, the first [bright] of them at [brightValue] and the
/// rest at [baseValue]; brightest-first so the quantile maths is legible.
Uint8List _frame(int count, int baseValue, int bright, int brightValue) {
  final rgb = Uint8List(count * 3);
  for (var p = 0; p < count; p++) {
    final v = p < bright ? brightValue : baseValue;
    rgb[p * 3] = v;
    rgb[p * 3 + 1] = v;
    rgb[p * 3 + 2] = v;
  }
  return rgb;
}

EmbeddedPreview _preview(int width, int height, int value, {int clipped = 0}) {
  final image = img.Image(width: width, height: height);
  var p = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++, p++) {
      final v = p < clipped ? 255 : value;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  // JPEG, because that is what a camera embeds and all decode() accepts.
  return EmbeddedPreview.decode(
    Uint8List.fromList(img.encodeJpg(image, quality: 100)),
  )!;
}

double _stopsToWhite(int value) =>
    math.log(1.0 / srgbToLinear(value / 255.0)) / math.ln2;

void main() {
  test('against a preview that clips nothing, the cap puts the frame\'s '
      'brightest pixels (past the 0.2% margin) at white', () {
    // 1000 pixels, the brightest 10 at 128: with only the margin allowed
    // to clip, the (1 - 0.002) quantile lands inside those 10, so the cap
    // is the gain that takes 128 to white.
    final frame = _frame(1000, 64, 10, 128);
    final cap = decodeGainCapStops(frame, _preview(40, 25, 120));
    expect(cap, closeTo(_stopsToWhite(128), 0.01));
    expect(cap, closeTo(2.21, 0.05));
  });

  test('a preview that already clips a lot allows the same fraction here', () {
    // The camera clipped 5% of its frame; our brightest 10% sit at 200,
    // so the quantile at 5.2% from the top is one of those, and the cap
    // is the gain that takes 200 to white — 0.8 stops rather than 2.2.
    final frame = _frame(1000, 64, 100, 200);
    final cap = decodeGainCapStops(frame, _preview(40, 25, 120, clipped: 50));
    expect(cap, closeTo(_stopsToWhite(200), 0.01));
    expect(cap, closeTo(0.79, 0.05));
  });

  test('the cap is what limits a large measured offset', () {
    // A frame far darker than its preview: the offset wants ~3 stops, the
    // brightest pixels allow ~2.2 — libraw.dart takes the smaller.
    final frame = _frame(1000, 40, 10, 128);
    final preview = _preview(40, 25, 140);
    final wanted = cameraExposureOffsetStops(
      frame,
      40,
      25,
      preview.bytes,
      limitStops: 5,
      preview: preview,
    )!;
    final cap = decodeGainCapStops(frame, preview);
    expect(wanted, greaterThan(cap));
    expect(math.min(wanted, cap), cap);
  });

  test('an all-black frame is unbounded rather than divided by zero', () {
    expect(
      decodeGainCapStops(_frame(100, 0, 0, 0), _preview(10, 10, 50)),
      double.infinity,
    );
  });

  test('EmbeddedPreview decodes once and rejects what is not an image', () {
    expect(EmbeddedPreview.decode(null), isNull);
    expect(EmbeddedPreview.decode(Uint8List.fromList([1, 2, 3])), isNull);
    final preview = _preview(8, 6, 100);
    expect(preview.image.width, 8);
    expect(preview.bytes, isNotEmpty);
  });
}
