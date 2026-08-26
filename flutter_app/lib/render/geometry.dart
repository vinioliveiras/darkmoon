import 'dart:math' as math;
import 'dart:typed_data';

/// A 3x3 matrix for 2D homogeneous (projective) point transforms — used by
/// [Transform]/Crop's perspective correction, which (unlike every other
/// adjustment in this app) needs to warp geometry, not just recolor pixels
/// in place.
class Matrix3 {
  const Matrix3(this.m);

  /// Row-major: `[m0 m1 m2; m3 m4 m5; m6 m7 m8]`.
  final List<double> m;

  static const identity = Matrix3([1, 0, 0, 0, 1, 0, 0, 0, 1]);

  /// Applies this matrix to homogeneous point `(x, y, 1)` and returns the
  /// perspective-divided `[x', y']`.
  List<double> transformPoint(double x, double y) {
    final wx = m[0] * x + m[1] * y + m[2];
    final wy = m[3] * x + m[4] * y + m[5];
    final w = m[6] * x + m[7] * y + m[8];
    return [wx / w, wy / w];
  }

  /// The standard adjugate/determinant 3x3 matrix inverse — falls back to
  /// [identity] on a singular (non-invertible) matrix rather than dividing
  /// by zero, which shouldn't happen for the well-conditioned quads this
  /// module builds but is a safe fallback if slider values ever combine
  /// into a degenerate transform.
  Matrix3 invert() {
    final a = m[0], b = m[1], c = m[2];
    final d = m[3], e = m[4], f = m[5];
    final g = m[6], h = m[7], i = m[8];
    final coA = e * i - f * h;
    final coB = -(d * i - f * g);
    final coC = d * h - e * g;
    final coD = -(b * i - c * h);
    final coE = a * i - c * g;
    final coF = -(a * h - b * g);
    final coG = b * f - c * e;
    final coH = -(a * f - c * d);
    final coI = a * e - b * d;
    final det = a * coA + b * coB + c * coC;
    if (det.abs() < 1e-12) {
      return identity;
    }
    final invDet = 1.0 / det;
    return Matrix3([
      coA * invDet,
      coD * invDet,
      coG * invDet,
      coB * invDet,
      coE * invDet,
      coH * invDet,
      coC * invDet,
      coF * invDet,
      coI * invDet,
    ]);
  }
}

/// Solves for the homography mapping each `src[i]` to `dst[i]` (exactly 4
/// point correspondences — the standard way to define a projective
/// transform by its effect on a quad's corners), via Gaussian elimination
/// on the 8-unknown linear system (`h33` is fixed at 1, the usual
/// normalization).
Matrix3 solveHomography(List<List<double>> src, List<List<double>> dst) {
  final a = List.generate(8, (_) => List.filled(8, 0.0));
  final b = List.filled(8, 0.0);
  for (var i = 0; i < 4; i++) {
    final x = src[i][0], y = src[i][1];
    final xp = dst[i][0], yp = dst[i][1];
    a[2 * i] = [x, y, 1, 0, 0, 0, -x * xp, -y * xp];
    b[2 * i] = xp;
    a[2 * i + 1] = [0, 0, 0, x, y, 1, -x * yp, -y * yp];
    b[2 * i + 1] = yp;
  }
  final h = _solveLinearSystem(a, b);
  return Matrix3([h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1.0]);
}

/// Gaussian elimination with partial pivoting for a small (8x8) dense
/// system — plenty fast for a per-render one-off solve, no need for a
/// general linear-algebra dependency just for this.
List<double> _solveLinearSystem(List<List<double>> a, List<double> b) {
  final n = b.length;
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var row = col + 1; row < n; row++) {
      if (a[row][col].abs() > a[pivot][col].abs()) {
        pivot = row;
      }
    }
    final tmpRow = a[col];
    a[col] = a[pivot];
    a[pivot] = tmpRow;
    final tmpB = b[col];
    b[col] = b[pivot];
    b[pivot] = tmpB;
    final pivotVal = a[col][col];
    if (pivotVal.abs() < 1e-12) {
      continue;
    }
    for (var row = col + 1; row < n; row++) {
      final factor = a[row][col] / pivotVal;
      for (var k = col; k < n; k++) {
        a[row][k] -= factor * a[col][k];
      }
      b[row] -= factor * b[col];
    }
  }
  final x = List.filled(n, 0.0);
  for (var row = n - 1; row >= 0; row--) {
    var sum = b[row];
    for (var k = row + 1; k < n; k++) {
      sum -= a[row][k] * x[k];
    }
    x[row] = a[row][row].abs() < 1e-12 ? 0.0 : sum / a[row][row];
  }
  return x;
}

/// Rotates point `(x, y)` by [radians] about `(cx, cy)`.
List<double> rotatePoint(
  double x,
  double y,
  double cx,
  double cy,
  double radians,
) {
  final dx = x - cx;
  final dy = y - cy;
  final cosT = math.cos(radians);
  final sinT = math.sin(radians);
  return [cx + dx * cosT - dy * sinT, cy + dx * sinT + dy * cosT];
}

/// Samples packed RGB [src] ([width]x[height]) at fractional `(u, v)` via
/// bilinear interpolation, clamping to the image bounds at the edges
/// rather than producing black — a strong keystone correction or lens
/// distortion correction can otherwise expose gaps outside the original
/// frame; clamping stretches the edge pixel into that gap instead, which
/// reads better before the user crops it away. Shared by `crop_transform.dart`
/// and `lens_correction.dart` — both resample a source buffer through a
/// per-pixel geometric mapping.
void sampleBilinear(
  Uint8List src,
  int width,
  int height,
  double u,
  double v,
  Uint8List out,
  int outIndex,
) {
  final cu = u.clamp(0.0, width - 1.0);
  final cv = v.clamp(0.0, height - 1.0);
  final x0 = cu.floor();
  final y0 = cv.floor();
  final x1 = math.min(x0 + 1, width - 1);
  final y1 = math.min(y0 + 1, height - 1);
  final fx = cu - x0;
  final fy = cv - y0;
  final i00 = (y0 * width + x0) * 3;
  final i10 = (y0 * width + x1) * 3;
  final i01 = (y1 * width + x0) * 3;
  final i11 = (y1 * width + x1) * 3;
  for (var c = 0; c < 3; c++) {
    final top = src[i00 + c] * (1 - fx) + src[i10 + c] * fx;
    final bottom = src[i01 + c] * (1 - fx) + src[i11 + c] * fx;
    out[outIndex + c] = (top * (1 - fy) + bottom * fy).round().clamp(0, 255);
  }
}

/// Same fractional-position bilinear sample as [sampleBilinear], but for a
/// single [channel] (0=R, 1=G, 2=B) of packed RGB [src] — used where only
/// one channel needs resampling at its own radius (TCA correction resamples
/// red and blue independently from green, which stays untouched).
double sampleBilinearChannel(
  Uint8List src,
  int width,
  int height,
  double u,
  double v,
  int channel,
) {
  final cu = u.clamp(0.0, width - 1.0);
  final cv = v.clamp(0.0, height - 1.0);
  final x0 = cu.floor();
  final y0 = cv.floor();
  final x1 = math.min(x0 + 1, width - 1);
  final y1 = math.min(y0 + 1, height - 1);
  final fx = cu - x0;
  final fy = cv - y0;
  final i00 = (y0 * width + x0) * 3 + channel;
  final i10 = (y0 * width + x1) * 3 + channel;
  final i01 = (y1 * width + x0) * 3 + channel;
  final i11 = (y1 * width + x1) * 3 + channel;
  final top = src[i00] * (1 - fx) + src[i10] * fx;
  final bottom = src[i01] * (1 - fx) + src[i11] * fx;
  return top * (1 - fy) + bottom * fy;
}
