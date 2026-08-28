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

/// Approximate camera as-shot white balance (Kelvin + Tint on this app's
/// -150..150 scale) from LibRaw's `cam_mul` multipliers and `cam_xyz`
/// camera-RGB->XYZ matrix. Not spectrally exact — good to a few hundred K,
/// which is fine since it's both the displayed "As Shot" value and the
/// no-op reference (self-consistent).
/// Tint magnitude, in this app's -150..150 units, for a doubling of the
/// camera's combined R+B gain excess over the Planckian locus. Calibrated
/// by eye against Lightroom's own "As Shot" Tint readout.
const double _wbTintScale = 200.0;

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
  // Normalize the as-shot multipliers to green.
  final cr = camMul[0] / camMul[1];
  final cb = camMul[2] / camMul[1];

  final fromTable = _kelvinTintFromWbct(cr, cb, wbctCoeffs);
  if (fromTable != null) {
    return fromTable;
  }
  return _kelvinTintFromMatrix(camMul, camXyz);
}

/// Interpolates the camera's own colour-temperature table
/// (`libraw_colordata_t.WBCT_Coeffs`, rows `[kelvin, m0, m1, m2, m3]`) —
/// camera-accurate, no colour matrix needed. Returns null if the table
/// isn't usable (too few valid rows, or the ratio falls outside it).
({double kelvin, double tint})? _kelvinTintFromWbct(
  double cr,
  double cb,
  List<List<double>> wbctCoeffs,
) {
  // Valid rows -> (kelvin, rRatio = R/G, bRatio = B/G), sorted by kelvin.
  final rows = <({double k, double r, double b})>[];
  for (final row in wbctCoeffs) {
    if (row.length < 4 || row[0] <= 0 || row[1] <= 0 || row[2] <= 0 ||
        row[3] <= 0) {
      continue;
    }
    rows.add((k: row[0], r: row[1] / row[2], b: row[3] / row[2]));
  }
  if (rows.length < 2) {
    return null;
  }
  rows.sort((a, b) => a.k.compareTo(b.k));

  // log(R/B) is monotonic in kelvin and roughly linear in *mired*
  // (1e6/K) — the scale colour-temperature correction is actually linear
  // on. Interpolate the bracketing rows in mired, not in kelvin, or the
  // warm side reads a few hundred K too high.
  double rowKey(({double k, double r, double b}) row) =>
      math.log(row.r / row.b);
  final key = math.log(cr / cb);
  ({double k, double r, double b}) lo = rows.first;
  ({double k, double r, double b}) hi = rows.last;
  var bracketed = false;
  for (var i = 0; i < rows.length - 1; i++) {
    final ka = rowKey(rows[i]), kc = rowKey(rows[i + 1]);
    if ((key >= ka && key <= kc) || (key <= ka && key >= kc)) {
      lo = rows[i];
      hi = rows[i + 1];
      bracketed = true;
      break;
    }
  }
  final loKey = rowKey(lo);
  final hiKey = rowKey(hi);
  final span = hiKey - loKey;
  final t = span.abs() < 1e-9 ? 0.0 : ((key - loKey) / span).clamp(-1.0, 2.0);
  final loMired = 1.0e6 / lo.k;
  final hiMired = 1.0e6 / hi.k;
  final mired = loMired + (hiMired - loMired) * t;
  final kelvin = (1.0e6 / mired).clamp(2000.0, 50000.0);
  if (!bracketed && (t < -0.5 || t > 1.5)) {
    // As-shot ratio is well outside the table — don't trust it.
    return null;
  }

  // Tint: how much extra R+B gain the camera applied versus the on-locus
  // multipliers at this kelvin (same R/B ratio, different magnitude).
  final locusR = lo.r + (hi.r - lo.r) * t;
  final locusB = lo.b + (hi.b - lo.b) * t;
  final camMag = math.sqrt(cr * cb);
  final locusMag = math.sqrt(locusR * locusB);
  final excess = locusMag <= 0 ? 0.0 : math.log(camMag / locusMag) / math.ln2;
  final tint = (excess * _wbTintScale).clamp(-150.0, 150.0);

  return (kelvin: kelvin, tint: tint);
}

/// Fallback when the camera has no usable WBCT table: the colorimetric
/// path. `cam_xyz` is the **XYZ -> camera** matrix (dcraw/Adobe DNG
/// convention), so it must be inverted to map the neutral's camera RGB
/// back to XYZ.
({double kelvin, double tint}) _kelvinTintFromMatrix(
  List<double> camMul,
  List<List<double>> camXyz,
) {
  final xyzToCam = _usable3x3(camXyz) ?? _srgbToXyz; // (already cam<-XYZ)
  final camToXyz = _invert3x3(xyzToCam);
  if (camToXyz == null) {
    return (kelvin: wbDefaultKelvin, tint: wbDefaultTint);
  }
  // Camera RGB of a surface the camera considers neutral = 1 / multiplier.
  final cR = 1.0 / camMul[0];
  final cG = 1.0 / camMul[1];
  final cB = 1.0 / camMul[2];
  var x = camToXyz[0][0] * cR + camToXyz[0][1] * cG + camToXyz[0][2] * cB;
  var y = camToXyz[1][0] * cR + camToXyz[1][1] * cG + camToXyz[1][2] * cB;
  var z = camToXyz[2][0] * cR + camToXyz[2][1] * cG + camToXyz[2][2] * cB;
  final sum = x + y + z;
  if (sum <= 0 || y <= 0) {
    return (kelvin: wbDefaultKelvin, tint: wbDefaultTint);
  }
  x /= sum;
  y /= sum;

  final n = (x - 0.3320) / (0.1858 - y);
  final cct = (449.0 * n * n * n + 3525.0 * n * n + 6823.3 * n + 5520.33)
      .clamp(2000.0, 50000.0);

  final denom = -2.0 * x + 12.0 * y + 3.0;
  final u = 4.0 * x / denom;
  final v = 6.0 * y / denom;
  final locus = _planckianUv(cct);
  final duv = (v - locus.v) - (u - locus.u);
  final tint = (duv * 6000.0).clamp(-150.0, 150.0);

  return (kelvin: cct, tint: tint);
}

const _srgbToXyz = [
  [0.4124, 0.3576, 0.1805],
  [0.2126, 0.7152, 0.0722],
  [0.0193, 0.1192, 0.9505],
];

List<List<double>>? _usable3x3(List<List<double>> m) {
  if (m.length < 3 || m[0].length < 3) {
    return null;
  }
  var nonZero = false;
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      if (m[i][j] != 0) nonZero = true;
    }
  }
  return nonZero ? m : null;
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
