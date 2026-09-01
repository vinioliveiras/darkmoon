/// CIE L*a*b* conversion matching OpenCV's `cv2.cvtColor(..., COLOR_BGR2Lab
/// / COLOR_LAB2BGR)` for float32 [0,1] images exactly — same sRGB EOTF
/// ([srgbToLinear]/[linearToSrgb], same threshold constants OpenCV uses),
/// same sRGB/D65 RGB<->XYZ matrix `white_balance.dart`'s `_rgbToXyz`/
/// `_xyzToRgb` already use elsewhere in this codebase (not imported from
/// there since those are private to that file — these are the same
/// well-known Lindbloom/sRGB-spec constants, duplicated the same way the
/// luma weights 0.2126/0.7152/0.0722 already are across several files in
/// this codebase).
///
/// Built for `colorize.dart`'s DDColor pipeline (item 37) — the reference
/// implementation is Python/OpenCV (`ddcolor/pipeline.py`), so this exists
/// to reproduce that exactly rather than use a simpler/different Lab
/// formulation that would drift from what the model was fed during
/// export/training.
library;

import 'color_space.dart';

const _rgbToXyz = [
  [0.4124564, 0.3575761, 0.1804375],
  [0.2126729, 0.7151522, 0.0721750],
  [0.0193339, 0.1191920, 0.9503041],
];
const _xyzToRgb = [
  [3.2404542, -1.5371385, -0.4985314],
  [-0.9692660, 1.8760108, 0.0415560],
  [0.0556434, -0.2040259, 1.0572252],
];

// D65 reference white, OpenCV's own exact constants (cvtcolor.cpp).
const _xn = 0.950456;
const _yn = 1.0;
const _zn = 1.088754;

const _labEpsilon = 0.008856; // (6/29)^3
const _labKappa = 7.787; // (1/3)*(29/6)^2

double _labF(double t) =>
    t > _labEpsilon ? _cbrt(t) : (_labKappa * t) + (16.0 / 116.0);

double _labFInv(double t) {
  final t3 = t * t * t;
  return t3 > _labEpsilon ? t3 : (t - 16.0 / 116.0) / _labKappa;
}

double _cbrt(double x) {
  if (x <= 0.0) return 0.0;
  // Newton's method on x^3 - v = 0, starting from a decent initial guess —
  // Dart's math library has no built-in cbrt; a couple of iterations is
  // plenty for the smooth, bounded [0,1]-ish inputs Lab conversion feeds
  // this with.
  var guess = x > 1.0 ? x : 1.0;
  for (var i = 0; i < 8; i++) {
    guess = guess - (guess * guess * guess - x) / (3 * guess * guess);
  }
  return guess;
}

/// sRGB [0,1] -> CIE L*a*b* (L in [0,100], a/b roughly [-127,127]).
({double l, double a, double b}) rgbToLab(double r, double g, double b) {
  final lr = srgbToLinear(r);
  final lg = srgbToLinear(g);
  final lb = srgbToLinear(b);

  final x = _rgbToXyz[0][0] * lr + _rgbToXyz[0][1] * lg + _rgbToXyz[0][2] * lb;
  final y = _rgbToXyz[1][0] * lr + _rgbToXyz[1][1] * lg + _rgbToXyz[1][2] * lb;
  final z = _rgbToXyz[2][0] * lr + _rgbToXyz[2][1] * lg + _rgbToXyz[2][2] * lb;

  final fx = _labF(x / _xn);
  final fy = _labF(y / _yn);
  final fz = _labF(z / _zn);

  return (l: 116.0 * fy - 16.0, a: 500.0 * (fx - fy), b: 200.0 * (fy - fz));
}

/// CIE L*a*b* -> sRGB [0,1] (not clamped — callers that display/encode as
/// bytes must clamp, same as every other render-pipeline conversion in
/// this codebase).
({double r, double g, double b}) labToRgb(double l, double a, double b) {
  final fy = (l + 16.0) / 116.0;
  final fx = fy + a / 500.0;
  final fz = fy - b / 200.0;

  final x = _xn * _labFInv(fx);
  final y = _yn * _labFInv(fy);
  final z = _zn * _labFInv(fz);

  final lr = _xyzToRgb[0][0] * x + _xyzToRgb[0][1] * y + _xyzToRgb[0][2] * z;
  final lg = _xyzToRgb[1][0] * x + _xyzToRgb[1][1] * y + _xyzToRgb[1][2] * z;
  final lb = _xyzToRgb[2][0] * x + _xyzToRgb[2][1] * y + _xyzToRgb[2][2] * z;

  return (r: linearToSrgb(lr), g: linearToSrgb(lg), b: linearToSrgb(lb));
}
