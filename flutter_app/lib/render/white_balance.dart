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
/// Von Kries: the target illuminant's reference white is mapped onto the
/// (already-neutral) as-shot white, so a surface lit by the target
/// illuminant comes out achromatic — and, unlike the old symmetric R/B
/// model, the green channel moves along the daylight locus the way it
/// physically should (which is what stopped skin neutralising and made
/// cooled skies go cyan). Luminance-normalised so sliding
/// Temperature/Tint doesn't drift overall brightness. At
/// `target == asShot` the gains are exactly (1, 1, 1).
({double r, double g, double b}) whiteBalanceGains(
  double targetKelvin,
  double targetTint,
  double asShotKelvin,
  double asShotTint,
) {
  final src = _referenceWhiteLinearRgb(asShotKelvin);
  final dst = _referenceWhiteLinearRgb(targetKelvin);
  var r = src.r / dst.r;
  var g = src.g / dst.g;
  var b = src.b / dst.b;

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

/// Linear-sRGB tristimulus of the reference white at [kelvin], normalised
/// so G = 1. CIE daylight locus at/above 4000 K (what Lightroom's
/// Temperature slider tracks), Planckian blackbody below it.
({double r, double g, double b}) _referenceWhiteLinearRgb(double kelvin) {
  final k = kelvin.clamp(1667.0, 25000.0);
  final double x;
  final double y;
  if (k >= 4000.0) {
    x = k <= 7000.0
        ? -4.6070e9 / (k * k * k) + 2.9678e6 / (k * k) + 99.11e0 / k + 0.244063
        : -2.0064e9 / (k * k * k) + 1.9018e6 / (k * k) + 247.48e0 / k + 0.237040;
    y = -3.0 * x * x + 2.870 * x - 0.275;
  } else {
    final uv = _planckianUv(k);
    final d = 2.0 * uv.u - 8.0 * uv.v + 4.0;
    x = 3.0 * uv.u / d;
    y = 2.0 * uv.v / d;
  }
  final bigX = x / y;
  final bigZ = (1.0 - x - y) / y;
  // XYZ (D65) -> linear sRGB, with Y = 1 folded into the constant terms.
  final r = 3.2406 * bigX - 1.5372 - 0.4986 * bigZ;
  final g = -0.9689 * bigX + 1.8758 + 0.0415 * bigZ;
  final b = 0.0557 * bigX - 0.2040 + 1.0570 * bigZ;
  final gg = g <= 1e-6 ? 1e-6 : g;
  return (r: r / gg, g: 1.0, b: b / gg);
}

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

/// Converts a signed distance off the Planckian locus in the CIE 1960 uv
/// plane (Δuv) to this app's -150..150 Tint units. Calibrated against
/// Lightroom's own "As Shot" Tint readout — its full range is roughly
/// Δuv ±0.06.
const double _wbTintPerDuv = 2400.0;

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
/// `1 / camMul` — maps to XYZ, then to a chromaticity. McCamy gives the
/// CCT; the signed perpendicular distance from the Planckian locus in the
/// CIE 1960 uv plane gives the tint. Returns null if `camXyz` is missing
/// or singular (falls through to the multiplier table).
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

  final n = (x - 0.3320) / (0.1858 - y);
  final cct = (449.0 * n * n * n + 3525.0 * n * n + 6823.3 * n + 5520.33)
      .clamp(2000.0, 50000.0);

  // Tint = signed perpendicular offset from the locus, in CIE 1960 uv.
  final denom = -2.0 * x + 12.0 * y + 3.0;
  final pu = 4.0 * x / denom;
  final pv = 6.0 * y / denom;
  final a = _planckianUv(cct - 150);
  final bloc = _planckianUv(cct + 150);
  var tx = bloc.u - a.u;
  var ty = bloc.v - a.v;
  final tlen = math.sqrt(tx * tx + ty * ty);
  double tint;
  if (tlen < 1e-12) {
    tint = 0;
  } else {
    tx /= tlen;
    ty /= tlen;
    final loc = _planckianUv(cct);
    // Normal (ty, -tx): below the locus (lower v) -> green -> negative,
    // matching Lightroom's convention.
    final duv = (pu - loc.u) * ty + (pv - loc.v) * -tx;
    tint = (duv * _wbTintPerDuv).clamp(-150.0, 150.0);
  }
  return (kelvin: cct, tint: tint);
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
