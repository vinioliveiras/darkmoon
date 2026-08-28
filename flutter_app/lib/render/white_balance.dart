import 'dart:math' as math;
import 'dart:typed_data';

/// White-balance model helpers shared by the render pipeline, the UI mode
/// selector and the eyedropper. Pure Dart, no Flutter imports.
///
/// The gain model itself lives in `render.dart`'s `_applyWhiteBalance`
/// (and is mirrored in `render_gpu.dart`). These constants MUST stay in
/// sync with it — they're duplicated here so the eyedropper solves the
/// exact same equations the renderer applies.
const double wbMiredGainPerUnit = 0.0013;
const double wbTempRGain = 0.2;
const double wbTempGGain = 0.05;
const double wbTempBGain = 0.2;
const double wbTintGain = 0.25;

/// The neutral reference used when a photo carries no camera white
/// balance (every non-RAW file, and RAW files LibRaw can't read `cam_mul`
/// from).
const double wbDefaultKelvin = 5500.0;
const double wbDefaultTint = 0.0;

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

/// Converts a UI Kelvin value to the model's normalized `rapidTemperature`
/// (RapidRAW's -1..1 control), relative to [asShotKelvin] as the neutral.
double rapidTemperatureFor(double kelvin, double asShotKelvin) {
  final miredDelta = 1.0e6 / asShotKelvin - 1.0e6 / kelvin;
  return (miredDelta * wbMiredGainPerUnit).clamp(-0.6, 0.6) / wbTempRGain;
}

/// Inverse of [rapidTemperatureFor] — the Kelvin that produces
/// [rapidTemperature] given [asShotKelvin].
double kelvinForRapidTemperature(double rapidTemperature, double asShotKelvin) {
  final tempGain = (rapidTemperature * wbTempRGain).clamp(-0.6, 0.6);
  final miredDelta = tempGain / wbMiredGainPerUnit;
  final invKelvin = 1.0e6 / asShotKelvin - miredDelta;
  if (invKelvin <= 0) {
    return 50000.0;
  }
  return (1.0e6 / invKelvin).clamp(2000.0, 50000.0);
}

/// (sign note: a green cast — g above r/b — solves to a *positive* tint,
/// since the model's `gTintGain = 1 - rapidTint*0.25` cuts green as tint
/// rises.)
///
/// Given an average pixel colour [r],[g],[b] (0-255, gamma-encoded — the
/// same space `_applyWhiteBalance` multiplies in), returns the Temperature
/// (Kelvin) and Tint that make that colour neutral under the gain model.
///
/// Closed form: the red and blue gains share the tint factor, so the
/// temperature term separates out of the R/B ratio first, then the tint
/// falls out of the R/G ratio.
({double kelvin, double tint}) solveNeutralizingTempTint(
  double r,
  double g,
  double b, {
  required double asShotKelvin,
  required double asShotTint,
}) {
  final rr = r <= 0 ? 1e-4 : r;
  final gg = g <= 0 ? 1e-4 : g;
  final bb = b <= 0 ? 1e-4 : b;

  // r*(1 + tRGain*rt) = b*(1 - tBGain*rt)  ->  rt
  final denom = wbTempRGain * rr + wbTempBGain * bb;
  final rapidTemp = denom == 0 ? 0.0 : (bb - rr) / denom;

  final a = rr * (1.0 + wbTempRGain * rapidTemp);
  final bTerm = gg * (1.0 + wbTempGGain * rapidTemp);
  final tintDenom = wbTintGain * (a + bTerm);
  final rapidTint = tintDenom == 0 ? 0.0 : (bTerm - a) / tintDenom;

  return (
    kelvin: kelvinForRapidTemperature(rapidTemp, asShotKelvin),
    tint: (rapidTint * 100.0 + asShotTint).clamp(-150.0, 150.0),
  );
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
