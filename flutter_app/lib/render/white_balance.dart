import 'dart:math' as math;
import 'dart:typed_data';

/// White-balance model helpers shared by the render pipeline (`render.dart`
/// and `render_gpu.dart` both call [whiteBalanceGains]), the mode selector
/// and the eyedropper. Pure Dart, no Flutter imports.

/// The neutral reference used when a photo carries no camera white
/// balance (every non-RAW file, and RAW files LibRaw can't read `cam_mul`
/// from).
const double wbDefaultKelvin = 5500.0;
const double wbDefaultTint = 0.0;

/// How hard a full ±100 Tint pushes green against red/blue. Close to the
/// previous model's 0.25, nudged up toward Lightroom's slightly stronger
/// Tint; the luminance-normalise step below keeps it brightness-neutral.
const double _wbTintStrength = 0.35;

/// Working-space gamma the render buffers are encoded with (LibRaw is set
/// to ~sRGB, `gamm = [1/2.4, 12.92]`). White-balance gains are derived in
/// linear light but multiplied into these gamma-encoded values, so each is
/// raised to `1/gamma` first — then `gammaValue * gain` equals
/// `(linearValue * linearGain)` re-encoded.
const double _wbWorkingGamma = 2.2;

enum WbMode {
  asShot,
  auto,
  daylight,
  cloudy,
  shade,
  tungsten,
  fluorescent,
  flash,
  custom,
}

/// Absolute (kelvin, tint) for the fixed lighting presets — classic Adobe
/// DNG reference values. `asShot`/`auto`/`custom` are resolved by the
/// caller (from metadata / a gray-world pass / the current sliders).
({double kelvin, double tint})? wbModePreset(WbMode mode) => switch (mode) {
  WbMode.daylight => (kelvin: 5500, tint: 10),
  WbMode.cloudy => (kelvin: 6500, tint: 10),
  WbMode.shade => (kelvin: 7500, tint: 10),
  WbMode.tungsten => (kelvin: 2850, tint: 0),
  WbMode.fluorescent => (kelvin: 3800, tint: 21),
  WbMode.flash => (kelvin: 5500, tint: 0),
  _ => null,
};

/// Per-channel multipliers for a White Balance move from the photo's
/// [asShotKelvin]/[asShotTint] reference to [targetKelvin]/[targetTint],
/// ready to multiply straight into the render buffer's gamma-encoded RGB.
///
/// Bradford chromatic adaptation from the target illuminant's white to
/// the photo's (already-neutral) as-shot white, collapsed to its effect
/// on a neutral so it stays three per-channel scalars — no per-pixel
/// matrix, the shader is untouched. Cone-space adaptation moves green the
/// way it physically should (a cooled sky reads cyan, skin neutralises),
/// which the old symmetric R/B model couldn't. Then a green/magenta Tint
/// term, and a final luminance-normalise so the sliders don't drift
/// brightness. At `target == asShot` the gains are exactly (1, 1, 1).
({double r, double g, double b}) whiteBalanceGains(
  double targetKelvin,
  double targetTint,
  double asShotKelvin,
  double asShotTint,
) {
  // Bradford chromatic adaptation from the target illuminant's white to
  // the (already-neutral) as-shot white, reduced to its effect on a
  // neutral so it stays three scalars (no per-pixel matrix / shader
  // change). Cone space gives the stronger, greener blue<->yellow
  // response Lightroom's Temperature slider has.
  final adapted = _bradfordNeutralGains(
    _referenceWhiteXyz(asShotKelvin),
    _referenceWhiteXyz(targetKelvin),
  );
  var r = adapted.r;
  var g = adapted.g;
  var b = adapted.b;

  // Green/magenta tint, relative to the as-shot tint. Positive = magenta
  // (green down, red+blue up), matching Lightroom's slider.
  final t = (targetTint - asShotTint) / 100.0;
  g *= 1.0 - t * _wbTintStrength;
  r *= 1.0 + t * _wbTintStrength * 0.5;
  b *= 1.0 + t * _wbTintStrength * 0.5;
  // (r/b get half the swing — Tint is mostly a green-vs-magenta shift, not
  // a red+blue boost; the luminance-normalise below balances the rest.)

  // Luminance-normalise (Rec. 709 weights) so brightness stays put.
  final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  if (lum > 1e-6) {
    r /= lum;
    g /= lum;
    b /= lum;
  }

  // Linear gains -> gamma-space gains (see [_wbWorkingGamma]).
  final e = 1.0 / _wbWorkingGamma;
  return (
    r: math.pow(r.clamp(1e-4, 100.0), e).toDouble(),
    g: math.pow(g.clamp(1e-4, 100.0), e).toDouble(),
    b: math.pow(b.clamp(1e-4, 100.0), e).toDouble(),
  );
}

/// XYZ (Y = 1) of the reference white at [kelvin]. CIE daylight locus
/// at/above 4000 K (what Lightroom's Temperature slider tracks), Planckian
/// blackbody below it.
({double x, double y, double z}) _referenceWhiteXyz(double kelvin) {
  final k = kelvin.clamp(1667.0, 25000.0);
  final double cx;
  final double cy;
  if (k >= 4000.0) {
    cx = k <= 7000.0
        ? -4.6070e9 / (k * k * k) + 2.9678e6 / (k * k) + 99.11e0 / k + 0.244063
        : -2.0064e9 / (k * k * k) + 1.9018e6 / (k * k) + 247.48e0 / k + 0.237040;
    cy = -3.0 * cx * cx + 2.870 * cx - 0.275;
  } else {
    final uv = _planckianUv(k);
    final d = 2.0 * uv.u - 8.0 * uv.v + 4.0;
    cx = 3.0 * uv.u / d;
    cy = 2.0 * uv.v / d;
  }
  return (x: cx / cy, y: 1.0, z: (1.0 - cx - cy) / cy);
}

// Bradford XYZ<->cone matrices and the sRGB (D65) RGB<->XYZ pair.
const _bradford = [
  [0.8951, 0.2664, -0.1614],
  [-0.7502, 1.7135, 0.0367],
  [0.0389, -0.0685, 1.0296],
];
const _bradfordInv = [
  [0.9869929, -0.1470543, 0.1599627],
  [0.4323053, 0.5183603, 0.0492912],
  [-0.0085287, 0.0400428, 0.9684867],
];
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

/// The per-channel linear-sRGB effect, on a neutral, of adapting [dst]
/// (the target illuminant white) to look like [src] (the as-shot white)
/// via Bradford. Full matrix collapsed to `M · (1,1,1)`.
({double r, double g, double b}) _bradfordNeutralGains(
  ({double x, double y, double z}) src,
  ({double x, double y, double z}) dst,
) {
  final sl = _mul3(_bradford, [src.x, src.y, src.z]);
  final dl = _mul3(_bradford, [dst.x, dst.y, dst.z]);
  final diag = [sl[0] / dl[0], sl[1] / dl[1], sl[2] / dl[2]];
  // M_xyz = M_bfd⁻¹ · diag(scale) · M_bfd
  final scaled = [
    for (var i = 0; i < 3; i++)
      [for (var j = 0; j < 3; j++) diag[i] * _bradford[i][j]],
  ];
  final mXyz = _matMul(_bradfordInv, scaled);
  // M_rgb = (sRGB<-XYZ) · M_xyz · (XYZ<-sRGB)
  final mRgb = _matMul(_xyzToRgb, _matMul(mXyz, _rgbToXyz));
  final gray = _mul3(mRgb, const [1.0, 1.0, 1.0]);
  return (
    r: gray[0] <= 1e-4 ? 1e-4 : gray[0],
    g: gray[1] <= 1e-4 ? 1e-4 : gray[1],
    b: gray[2] <= 1e-4 ? 1e-4 : gray[2],
  );
}

List<double> _mul3(List<List<double>> m, List<double> v) => [
  for (var i = 0; i < 3; i++)
    m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2],
];

List<List<double>> _matMul(List<List<double>> a, List<List<double>> b) => [
  for (var i = 0; i < 3; i++)
    [
      for (var j = 0; j < 3; j++)
        a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j],
    ],
];

/// The Temperature (Kelvin) and Tint that make the average colour
/// [r],[g],[b] (gamma-encoded — the render buffer's space) neutral under
/// [whiteBalanceGains]. Bisects Kelvin against the R:B balance, then Tint
/// against the G balance — the model is monotone in both.
({double kelvin, double tint}) solveNeutralizingTempTint(
  double r,
  double g,
  double b, {
  required double asShotKelvin,
  required double asShotTint,
}) {
  final rr = r <= 1e-4 ? 1e-4 : r;
  final gg = g <= 1e-4 ? 1e-4 : g;
  final bb = b <= 1e-4 ? 1e-4 : b;

  var lo = 2000.0;
  var hi = 50000.0;
  for (var i = 0; i < 40; i++) {
    final mid = math.sqrt(lo * hi);
    final gn = whiteBalanceGains(mid, asShotTint, asShotKelvin, asShotTint);
    // Warmer target Kelvin -> more R gain, less B gain. If R still wins
    // after the gains, the correction needs to be cooler (lower Kelvin).
    if (rr * gn.r > bb * gn.b) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  final kelvin = math.sqrt(lo * hi).clamp(2000.0, 50000.0);

  var tlo = -150.0;
  var thi = 150.0;
  for (var i = 0; i < 40; i++) {
    final mid = (tlo + thi) / 2.0;
    final gn = whiteBalanceGains(kelvin, mid, asShotKelvin, asShotTint);
    // Higher Tint -> less G gain. If G still wins, push toward magenta.
    if (gg * gn.g > rr * gn.r) {
      tlo = mid;
    } else {
      thi = mid;
    }
  }
  return (kelvin: kelvin, tint: ((tlo + thi) / 2.0).clamp(-150.0, 150.0));
}

/// Gray-world auto white balance: the trimmed mean of [rgbBytes] (packed
/// RGB, 3 bytes/pixel), skipping near-black and near-white pixels so
/// clipped regions don't dominate, fed through [solveNeutralizingTempTint].
({double kelvin, double tint}) grayWorldTempTint(
  Uint8List rgbBytes, {
  required double asShotKelvin,
  required double asShotTint,
}) {
  var sumR = 0.0, sumG = 0.0, sumB = 0.0;
  var count = 0;
  // Sample every 4th pixel — plenty for an average, 4x cheaper.
  for (var i = 0; i + 2 < rgbBytes.length; i += 12) {
    final r = rgbBytes[i];
    final g = rgbBytes[i + 1];
    final b = rgbBytes[i + 2];
    final mx = math.max(r, math.max(g, b));
    final mn = math.min(r, math.min(g, b));
    if (mn < 8 || mx > 247) {
      continue;
    }
    sumR += r;
    sumG += g;
    sumB += b;
    count++;
  }
  if (count == 0) {
    return (kelvin: asShotKelvin, tint: asShotTint);
  }
  return solveNeutralizingTempTint(
    sumR / count,
    sumG / count,
    sumB / count,
    asShotKelvin: asShotKelvin,
    asShotTint: asShotTint,
  );
}

/// Converts a signed Δuv (nearest-point offset from the reference-white
/// locus, CIE 1960 uv) to this app's -150..150 Tint units. Calibrated
/// against Lightroom's "As Shot" Tint on real Fuji X100VI files.
const double _wbTintPerDuv = 2100.0;

/// Our McCamy CCT reads a few mired cool of Lightroom's "As Shot" Kelvin
/// fairly consistently (calibrated on the same X100VI set, ~+3 mired);
/// subtracting it nudges the estimate into Adobe's reference frame.
const double _wbCctMiredBias = 3.0;

/// Tint magnitude per doubling of the R+B gain excess in the multiplier
/// fallback path (no camera matrix). Rougher than the colorimetric path.
const double _wbTintScale = 200.0;

/// Approximate camera as-shot white balance (Kelvin + Tint on this app's
/// -150..150 scale) from LibRaw's camera colour data.
///
/// Estimation order, best first:
///  1. [camXyz] — the camera's XYZ->camera colour matrix. LibRaw sources
///     this from Adobe's own per-model coefficients, so the colorimetric
///     estimate (invert the matrix, map the neutral to a chromaticity,
///     McCamy CCT + a perpendicular Δuv for tint) lands in the same
///     reference frame Lightroom uses — typically within ~150 K.
///  2. [wbctCoeffs] — the camera's internal colour-temperature table
///     (`WBCT_Coeffs`). Camera-accurate geometry but the sensor maker's
///     Kelvin labels, so it can read a few hundred K off Adobe.
({double kelvin, double tint}) wbMultipliersToKelvinTint(
  List<double> camMul, {
  List<List<double>> camXyz = const [],
  List<List<double>> wbctCoeffs = const [],
}) {
  if (camMul.length < 3 ||
      camMul[0] <= 0 ||
      camMul[1] <= 0 ||
      camMul[2] <= 0) {
    return (kelvin: wbDefaultKelvin, tint: wbDefaultTint);
  }

  final colorimetric = _kelvinTintColorimetric(camMul, camXyz);
  if (colorimetric != null) {
    return colorimetric;
  }

  final cr = camMul[0] / camMul[1];
  final cb = camMul[2] / camMul[1];
  final wbctRows = <({double k, double r, double b})>[];
  for (final row in wbctCoeffs) {
    if (row.length < 4 ||
        row[0] <= 0 ||
        row[1] <= 0 ||
        row[2] <= 0 ||
        row[3] <= 0) {
      continue;
    }
    wbctRows.add((k: row[0], r: row[1] / row[2], b: row[3] / row[2]));
  }
  return _interpKeyedRows(cr, cb, wbctRows) ??
      (kelvin: wbDefaultKelvin, tint: wbDefaultTint);
}

/// Piecewise interpolation of `(kelvin, R/G, B/G)` [rows] against the
/// as-shot chroma [cr]/[cb]. `key = log(R/B)` is monotonic in Kelvin and
/// roughly linear in mired (1e6/K), so the bracketing rows are lerped in
/// mired. Non-monotonic rows (some cameras' Shade preset overlaps D65) are
/// dropped first. Returns null if fewer than two usable rows survive or
/// the as-shot chroma lands well outside their range.
({double kelvin, double tint})? _interpKeyedRows(
  double cr,
  double cb,
  List<({double k, double r, double b})> rows,
) {
  if (rows.length < 2) {
    return null;
  }
  double rowKey(({double k, double r, double b}) row) =>
      math.log(row.r / row.b);

  final sorted = [...rows]..sort((a, b) => rowKey(a).compareTo(rowKey(b)));
  // key = log(R/B) rises with Kelvin (warm light -> tiny R gain, big B
  // gain -> R/B small; cool light -> the reverse). Keep only rows that
  // hold that trend, dropping any that break it (e.g. some cameras'
  // Shade preset chroma overlaps D65).
  final mono = <({double k, double r, double b})>[sorted.first];
  for (final row in sorted.skip(1)) {
    if (row.k > mono.last.k) {
      mono.add(row);
    }
  }
  if (mono.length < 2) {
    return null;
  }

  final key = math.log(cr / cb);
  var lo = mono.first;
  var hi = mono.last;
  var bracketed = false;
  for (var i = 0; i < mono.length - 1; i++) {
    if (key >= rowKey(mono[i]) && key <= rowKey(mono[i + 1])) {
      lo = mono[i];
      hi = mono[i + 1];
      bracketed = true;
      break;
    }
  }
  final span = rowKey(hi) - rowKey(lo);
  final t = span.abs() < 1e-9 ? 0.0 : ((key - rowKey(lo)) / span);
  if (!bracketed && (t < -0.6 || t > 1.6)) {
    return null;
  }
  final loMired = 1.0e6 / lo.k;
  final hiMired = 1.0e6 / hi.k;
  final kelvin = (1.0e6 / (loMired + (hiMired - loMired) * t))
      .clamp(2000.0, 50000.0);

  // Tint: extra combined R+B gain vs the on-locus multipliers at this key.
  final locusR = lo.r + (hi.r - lo.r) * t;
  final locusB = lo.b + (hi.b - lo.b) * t;
  final camMag = math.sqrt(cr * cb);
  final locusMag = math.sqrt(locusR * locusB);
  final excess = locusMag <= 0 ? 0.0 : math.log(camMag / locusMag) / math.ln2;
  final tint = (excess * _wbTintScale).clamp(-150.0, 150.0);

  return (kelvin: kelvin, tint: tint);
}

/// The primary estimate: `cam_xyz` (LibRaw's Adobe-sourced **XYZ ->
/// camera** matrix) is inverted so the neutral surface's camera RGB —
/// `1 / camMul` — maps to XYZ, then to a chromaticity, which is projected
/// onto the daylight/Planckian reference-white locus (Ohno's method). The
/// nearest point gives both the CCT and the signed Δuv for tint. Returns
/// null if `camXyz` is missing or singular (falls through to the table).
({double kelvin, double tint})? _kelvinTintColorimetric(
  List<double> camMul,
  List<List<double>> camXyz,
) {
  if (camXyz.length < 3 || camXyz[0].length < 3) {
    return null;
  }
  var anyNonZero = false;
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      if (camXyz[i][j] != 0) anyNonZero = true;
    }
  }
  if (!anyNonZero) {
    return null;
  }
  final camToXyz = _invert3x3(camXyz);
  if (camToXyz == null) {
    return null;
  }

  final cR = 1.0 / camMul[0];
  final cG = 1.0 / camMul[1];
  final cB = 1.0 / camMul[2];
  final bigX = camToXyz[0][0] * cR + camToXyz[0][1] * cG + camToXyz[0][2] * cB;
  final bigY = camToXyz[1][0] * cR + camToXyz[1][1] * cG + camToXyz[1][2] * cB;
  final bigZ = camToXyz[2][0] * cR + camToXyz[2][1] * cG + camToXyz[2][2] * cB;
  final sum = bigX + bigY + bigZ;
  if (sum <= 0 || bigY <= 0) {
    return null;
  }
  final x = bigX / sum;
  final y = bigY / sum;

  // Ohno-style: project the chromaticity onto the reference-white locus
  // (CIE daylight >= 4000 K, Planckian below) and read CCT *and* the
  // signed offset from that one nearest point. Self-consistent, so a
  // near-neutral as-shot no longer flips tint sign on a small CCT error.
  final denom = -2.0 * x + 12.0 * y + 3.0;
  final pu = 4.0 * x / denom;
  final pv = 6.0 * y / denom;

  var bestD2 = double.infinity;
  var bestMired = 1.0e6 / 5500.0;
  var bestCross = 0.0;
  ({double u, double v})? prev;
  var prevMired = 0.0;
  // Walk the locus warm-ward, uniformly in mired (~perceptually even).
  for (var mired = 40.0; mired <= 500.0; mired += 0.5) {
    final p = _referenceWhiteUv(1.0e6 / mired);
    if (prev != null) {
      final sx = p.u - prev.u;
      final sy = p.v - prev.v;
      final segLen2 = sx * sx + sy * sy;
      final t = segLen2 < 1e-18
          ? 0.0
          : (((pu - prev.u) * sx + (pv - prev.v) * sy) / segLen2)
                .clamp(0.0, 1.0);
      final fu = prev.u + sx * t;
      final fv = prev.v + sy * t;
      final d2 = (pu - fu) * (pu - fu) + (pv - fv) * (pv - fv);
      if (d2 < bestD2) {
        bestD2 = d2;
        bestMired = prevMired + (mired - prevMired) * t;
        // z of (segment toward warmer) x (point - foot): > 0 = green side.
        bestCross = sx * (pv - fv) - sy * (pu - fu);
      }
    }
    prev = p;
    prevMired = mired;
  }

  // Green side -> negative Tint, matching Lightroom's convention.
  final duv = (bestCross >= 0 ? 1.0 : -1.0) * math.sqrt(bestD2);
  final tint = (duv * _wbTintPerDuv).clamp(-150.0, 150.0);
  final kelvin =
      (1.0e6 / (bestMired - _wbCctMiredBias)).clamp(2000.0, 50000.0);
  return (kelvin: kelvin, tint: tint);
}

/// The reference white at [kelvin] (daylight locus / Planckian below
/// 4000 K) as CIE 1960 uv.
({double u, double v}) _referenceWhiteUv(double kelvin) {
  final w = _referenceWhiteXyz(kelvin);
  final sum = w.x + w.y + w.z;
  final cx = w.x / sum;
  final cy = w.y / sum;
  final d = -2.0 * cx + 12.0 * cy + 3.0;
  return (u: 4.0 * cx / d, v: 6.0 * cy / d);
}

List<List<double>>? _invert3x3(List<List<double>> m) {
  final a = m[0][0], b = m[0][1], c = m[0][2];
  final d = m[1][0], e = m[1][1], f = m[1][2];
  final g = m[2][0], h = m[2][1], i = m[2][2];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  if (det.abs() < 1e-12) {
    return null;
  }
  final inv = 1.0 / det;
  return [
    [(e * i - f * h) * inv, (c * h - b * i) * inv, (b * f - c * e) * inv],
    [(f * g - d * i) * inv, (a * i - c * g) * inv, (c * d - a * f) * inv],
    [(d * h - e * g) * inv, (b * g - a * h) * inv, (a * e - b * d) * inv],
  ];
}

({double u, double v}) _planckianUv(double cct) {
  // Krystek's approximation of the Planckian locus in CIE 1960 uv.
  final t = cct;
  final u =
      (0.860117757 + 1.54118254e-4 * t + 1.28641212e-7 * t * t) /
      (1.0 + 8.42420235e-4 * t + 7.08145163e-7 * t * t);
  final v =
      (0.317398726 + 4.22806245e-5 * t + 4.20481691e-8 * t * t) /
      (1.0 - 2.89741816e-5 * t + 1.61456053e-7 * t * t);
  return (u: u, v: v);
}
