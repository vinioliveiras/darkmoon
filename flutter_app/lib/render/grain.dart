import 'dart:math' as math;
import 'dart:typed_data';

import 'calibration.dart';

/// Film grain for the Effects panel — a faithful port of Solstice's
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
  const GrainParams({this.amount = 0, this.size = 25, this.roughness = 50});

  /// Builds params from the editor's flat `{sliderName: value}` map —
  /// keyed `'Grain' + <Amount|Size|Roughness>`, same convention as every
  /// other slider. Matches Meridian's `crs:GrainAmount` / `GrainSize` /
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

double _quintic(double t) => t * t * t * (t * (t * 6.0 - 15.0) + 10.0);

/// One octave's precomputed `gradient_noise` corner values — every integer
/// lattice coordinate a band's pixels can land on (plus the +1 border the
/// interpolation's far corner needs), each hashed exactly once.
///
/// `gradient_noise` is a per-pixel bilinear-ish blend of the 4 lattice
/// corners surrounding it, each corner needing 2 `_hash` calls (one for
/// its X pseudo-gradient, one for Y). `calGrainSizePxAt0`/`At100` are both
/// under 5px, and export resolutions divide that by a `refScale` that's
/// >1 for anything bigger than the 1080px reference — so in practice one
/// lattice cell spans anywhere from a handful to a few dozen pixels.
/// Re-deriving the same corner's hash from scratch for every pixel inside
/// that cell (the original implementation) was by far the single most
/// expensive step in the whole point-ops pipeline; building each octave's
/// lattice once per band call and looking corners up from it turns a
/// per-pixel hash into a per-lattice-point one.
class _GradientLattice {
  factory _GradientLattice({
    required double firstX,
    required double lastX,
    required double firstY,
    required double lastY,
  }) {
    final minX = firstX.floor();
    final minY = firstY.floor();
    final width = lastX.floor() + 1 - minX + 1;
    final height = lastY.floor() + 1 - minY + 1;
    final gx = Float64List(width * height);
    final gy = Float64List(width * height);
    for (var iy = 0; iy < height; iy++) {
      final y = (minY + iy).toDouble();
      final rowBase = iy * width;
      for (var ix = 0; ix < width; ix++) {
        final x = (minX + ix).toDouble();
        final idx = rowBase + ix;
        gx[idx] = _hash(x, y) * 2.0 - 1.0;
        gy[idx] = _hash(x + 11.0, y + 37.0) * 2.0 - 1.0;
      }
    }
    return _GradientLattice._(minX, minY, width, gx, gy);
  }

  _GradientLattice._(this._minX, this._minY, this._width, this._gx, this._gy);

  final int _minX;
  final int _minY;
  final int _width;
  final Float64List _gx;
  final Float64List _gy;

  int _index(int x, int y) => (y - _minY) * _width + (x - _minX);
  double gradX(int x, int y) => _gx[_index(x, y)];
  double gradY(int x, int y) => _gy[_index(x, y)];
}

/// Same math as the old per-pixel `gradient_noise`, but sourcing each
/// corner's pseudo-gradient from a precomputed [_GradientLattice] instead
/// of calling `_hash` fresh.
double _gradientNoise(_GradientLattice lattice, double px, double py) {
  final ix = px.floor();
  final iy = py.floor();
  final fx = px - ix;
  final fy = py - iy;
  final ux = _quintic(fx);
  final uy = _quintic(fy);

  final dot00 = lattice.gradX(ix, iy) * fx + lattice.gradY(ix, iy) * fy;
  final dot10 =
      lattice.gradX(ix + 1, iy) * (fx - 1.0) + lattice.gradY(ix + 1, iy) * fy;
  final dot01 =
      lattice.gradX(ix, iy + 1) * fx + lattice.gradY(ix, iy + 1) * (fy - 1.0);
  final dot11 =
      lattice.gradX(ix + 1, iy + 1) * (fx - 1.0) +
      lattice.gradY(ix + 1, iy + 1) * (fy - 1.0);

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
///
/// [rowOffset]/[fullHeight] let this run on one horizontal band — the
/// noise field and its frequency are anchored to the whole frame, so
/// bands stitch back seamlessly.
void applyGrain(
  Float32List img,
  int width,
  int height,
  GrainParams params, {
  int rowOffset = 0,
  int? fullHeight,
}) {
  if (params.isIdentity || width < 1 || height < 1) {
    return;
  }
  final frameHeight = fullHeight ?? height;
  // Solstice: amount = grain_amount * 0.5 (its buffer is 0..1); ours is
  // 0..255, so the * 255 folds the space conversion in.
  final amount = (params.amount / 100.0) * 0.5 * calGrainStrength * 255.0;
  final roughness = (params.roughness / 100.0).clamp(0.0, 1.0);

  final grainSizePx =
      calGrainSizePxAt0 +
      (params.size / 100.0).clamp(0.0, 1.0) *
          (calGrainSizePxAt100 - calGrainSizePxAt0);
  // Keep the grain the same relative size regardless of render resolution
  // (shader.wgsl's REFERENCE_DIMENSION = 1080).
  final refScale = math.max(0.1, math.min(width, frameHeight) / 1080.0);
  final frequency = (1.0 / math.max(grainSizePx, 0.1)) / refScale;
  final roughFrequency = frequency * calGrainRoughCoordScale;

  final lastAy = (rowOffset + height - 1).toDouble();
  final baseLattice = _GradientLattice(
    firstX: 0,
    lastX: (width - 1) * frequency,
    firstY: rowOffset * frequency,
    lastY: lastAy * frequency,
  );
  final roughLattice = _GradientLattice(
    firstX: 5.2,
    lastX: (width - 1) * roughFrequency + 5.2,
    firstY: rowOffset * roughFrequency + 1.3,
    lastY: lastAy * roughFrequency + 1.3,
  );

  for (var y = 0; y < height; y++) {
    final ay = y + rowOffset;
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final luma =
          (0.2126 * img[i] + 0.7152 * img[i + 1] + 0.0722 * img[i + 2]) / 255.0;
      if (luma <= 0.0) {
        continue;
      }
      final lumaMask =
          _smoothstep(0.0, 0.15, luma) * (1.0 - _smoothstep(0.6, 1.0, luma));
      if (lumaMask <= 0.0) {
        continue;
      }
      final noiseBase = _gradientNoise(
        baseLattice,
        x * frequency,
        ay * frequency,
      );
      final noiseRough = _gradientNoise(
        roughLattice,
        x * roughFrequency + 5.2,
        ay * roughFrequency + 1.3,
      );
      final noiseVal = noiseBase + (noiseRough - noiseBase) * roughness;
      final delta = noiseVal * amount * lumaMask;
      img[i] += delta;
      img[i + 1] += delta;
      img[i + 2] += delta;
    }
  }
}
