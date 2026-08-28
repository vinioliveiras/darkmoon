import 'dart:math' as math;
import 'dart:typed_data';

import 'calibration.dart';

/// Film grain for the Effects panel — a faithful port of RapidRAW's
/// `apply_grain` (shader.wgsl): value-noise (`gradient_noise`) additive
/// grain, luminance-masked so it fades out of deep shadows and bright
/// highlights, with a "roughness" control blending a finer and a coarser
/// noise octave.
///
/// Deterministic — the noise is a pure function of pixel coordinates, so a
/// re-render (or the same photo reopened) produces the identical grain, and
/// export matches the preview. The grain frequency is divided by the
/// image's size relative to a 1080px reference, so a grain of a given
/// "Size" looks the same on the downscaled edit preview and the full-res
/// export.
class GrainParams {
  const GrainParams({
    this.amount = 0,
    this.size = 25,
    this.roughness = 50,
  });

  /// Builds params from the editor's flat `{sliderName: value}` map —
  /// keyed `'Grain' + <Amount|Size|Roughness>`, same convention as every
  /// other slider. Matches Lightroom's `crs:GrainAmount` / `GrainSize` /
  /// `GrainFrequency` (all 0..100).
  factory GrainParams.fromValues(Map<String, double> values) {
    const defaults = GrainParams();
    return GrainParams(
      amount: values['GrainAmount'] ?? defaults.amount,
      size: values['GrainSize'] ?? defaults.size,
      roughness: values['GrainRoughness'] ?? defaults.roughness,
    );
  }

  /// 0..100 — overall grain visibility. 0 = off.
  final double amount;

  /// 0..100 — grain particle size (fine → coarse).
  final double size;

  /// 0..100 — blends a coarser, more irregular noise octave over the fine
  /// one.
  final double roughness;

  bool get isIdentity => amount <= 0;
}

double _fract(double x) => x - x.floorToDouble();

/// Port of shader.wgsl's `hash(vec2)` — note `p.xyx`, so the 1st and 3rd
/// lanes start equal.
double _hash(double px, double py) {
  var x = _fract(px * 0.1031);
  var y = _fract(py * 0.1031);
  var z = _fract(px * 0.1031);
  final d = x * (y + 33.33) + y * (z + 33.33) + z * (x + 33.33);
  x += d;
  y += d;
  z += d;
  return _fract((x + y) * z);
}

/// Port of shader.wgsl's `gradient_noise(vec2)` — quintic-smoothed value
/// noise in roughly [-1, 1].
double _gradientNoise(double px, double py) {
  final ix = px.floorToDouble();
  final iy = py.floorToDouble();
  final fx = px - ix;
  final fy = py - iy;
  final ux = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0);
  final uy = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0);

  double gradX(double cx, double cy) => _hash(ix + cx, iy + cy) * 2.0 - 1.0;
  double gradY(double cx, double cy) =>
      _hash(ix + cx + 11.0, iy + cy + 37.0) * 2.0 - 1.0;

  final dot00 = gradX(0, 0) * fx + gradY(0, 0) * fy;
  final dot10 = gradX(1, 0) * (fx - 1.0) + gradY(1, 0) * fy;
  final dot01 = gradX(0, 1) * fx + gradY(0, 1) * (fy - 1.0);
  final dot11 = gradX(1, 1) * (fx - 1.0) + gradY(1, 1) * (fy - 1.0);

  final bottom = dot00 + (dot10 - dot00) * ux;
  final top = dot01 + (dot11 - dot01) * ux;
  return bottom + (top - bottom) * uy;
}

double _smoothstep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/// Applies film grain in place to a packed RGB [Float32List] (3 values/
/// pixel, 0..255, gamma-encoded — the pipeline's between-stage convention).
/// A no-op when [GrainParams.amount] is 0.
void applyGrain(Float32List img, int width, int height, GrainParams params) {
  if (params.isIdentity || width < 1 || height < 1) {
    return;
  }
  // RapidRAW: amount = grain_amount * 0.5 (its buffer is 0..1); ours is
  // 0..255, so the * 255 folds the space conversion in.
  final amount =
      (params.amount / 100.0) * 0.5 * calGrainStrength * 255.0;
  final roughness = (params.roughness / 100.0).clamp(0.0, 1.0);

  final grainSizePx = calGrainSizePxAt0 +
      (params.size / 100.0).clamp(0.0, 1.0) *
          (calGrainSizePxAt100 - calGrainSizePxAt0);
  // Keep the grain the same relative size regardless of render resolution
  // (shader.wgsl's REFERENCE_DIMENSION = 1080).
  final refScale = math.max(0.1, math.min(width, height) / 1080.0);
  final frequency = (1.0 / math.max(grainSizePx, 0.1)) / refScale;
  final roughFrequency = frequency * calGrainRoughCoordScale;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final luma =
          (0.2126 * img[i] + 0.7152 * img[i + 1] + 0.0722 * img[i + 2]) /
              255.0;
      if (luma <= 0.0) {
        continue;
      }
      final lumaMask = _smoothstep(0.0, 0.15, luma) *
          (1.0 - _smoothstep(0.6, 1.0, luma));
      if (lumaMask <= 0.0) {
        continue;
      }
      final noiseBase = _gradientNoise(x * frequency, y * frequency);
      final noiseRough = _gradientNoise(
        x * roughFrequency + 5.2,
        y * roughFrequency + 1.3,
      );
      final noiseVal = noiseBase + (noiseRough - noiseBase) * roughness;
      final delta = noiseVal * amount * lumaMask;
      img[i] += delta;
      img[i + 1] += delta;
      img[i + 2] += delta;
    }
  }
}
