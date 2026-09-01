import 'dart:math' as math;
import 'dart:typed_data';

import 'calibration.dart';

/// Mirrors Meridian's Effects panel Post-Crop Vignette — [amount] and the
/// falloff shape (via [midpoint]/[feather]). Style (Highlight/Color
/// Priority/Paint Overlay) and Highlight Contrast aren't modeled — they
/// tweak how the darkening blends with highlights, a subtlety this simple
/// multiplicative version skips in favor of the amount/shape that carries
/// most of the visible effect.
class VignetteParams {
  const VignetteParams({
    this.amount = 0,
    this.midpoint = 50,
    this.feather = 50,
  });

  /// Builds params from the editor's flat `{sliderName: value}` map —
  /// keyed `'Vignette' + <Amount|Midpoint|Feather>`, same convention as
  /// every other slider.
  factory VignetteParams.fromValues(Map<String, double> values) {
    const defaults = VignetteParams();
    return VignetteParams(
      amount: values['VignetteAmount'] ?? defaults.amount,
      midpoint: values['VignetteMidpoint'] ?? defaults.midpoint,
      feather: values['VignetteFeather'] ?? defaults.feather,
    );
  }

  /// -100..100 — darkens (negative, the common case) or lightens
  /// (positive) the image toward the edges.
  final double amount;

  /// 0..100 — how far from center the vignette starts; higher pushes it
  /// closer to the corners.
  final double midpoint;

  /// 0..100 — width of the transition between untouched center and full
  /// effect; higher is a softer, more gradual falloff.
  final double feather;

  bool get isIdentity => amount == 0;
}

/// Applies a radial vignette to packed RGB [img] in place — a no-op when
/// [VignetteParams.amount] is 0.
///
/// Distance from center is normalized per-axis by the image's own
/// half-width/half-height, so the vignette follows an ellipse matching the
/// photo's aspect ratio rather than assuming a square frame.
///
/// Designed to run via `compute()`: pure function over simple, isolate-
/// transferable data (same as the rest of render.dart).
/// [rowOffset]/[fullHeight] let this run on one horizontal band of a
/// larger image — the ellipse is still measured against the *whole*
/// frame's centre and half-height, not the band's.
void applyVignette(
  Float32List img,
  int width,
  int height,
  VignetteParams params, {
  int rowOffset = 0,
  int? fullHeight,
}) {
  if (params.isIdentity) {
    return;
  }
  final frameHeight = fullHeight ?? height;
  final cx = width / 2.0;
  final cy = frameHeight / 2.0;
  final start = (params.midpoint / 100.0).clamp(0.0, 1.0);
  final featherWidth = (params.feather / 100.0).clamp(0.02, 1.0);
  final strength = params.amount / 100.0 * calVignetteStrength;
  const cornerRadius = 1.4142135623730951; // sqrt(2), a corner's distance.

  for (var y = 0; y < height; y++) {
    final dy = (y + rowOffset - cy) / cy;
    for (var x = 0; x < width; x++) {
      final dx = (x - cx) / cx;
      final radius = math.sqrt(dx * dx + dy * dy) / cornerRadius;
      final t = ((radius - start) / featherWidth).clamp(0.0, 1.0);
      final weight = t * t * (3 - 2 * t);
      if (weight == 0) {
        continue;
      }
      final factor = 1.0 + strength * weight;
      final i = (y * width + x) * 3;
      img[i] *= factor;
      img[i + 1] *= factor;
      img[i + 2] *= factor;
    }
  }
}
