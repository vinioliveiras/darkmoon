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
({double kelvin, double tint}) wbMultipliersToKelvinTint(
  List<double> camMul,
  List<List<double>> camXyz,
) {
  if (camMul.length < 3 ||
      camMul[0] <= 0 ||
      camMul[1] <= 0 ||
      camMul[2] <= 0) {
    return (kelvin: wbDefaultKelvin, tint: wbDefaultTint);
  }
  // Camera RGB of a surface the camera considers neutral = 1 / multiplier.
  final camR = 1.0 / camMul[0];
  final camG = 1.0 / camMul[1];
  final camB = 1.0 / camMul[2];

  // cam_xyz maps camera RGB -> XYZ. Fall back to a sRGB-ish matrix if it
  // looks unpopulated.
  final m = _cameraXyzOrFallback(camXyz);
  var x = m[0][0] * camR + m[0][1] * camG + m[0][2] * camB;
  var y = m[1][0] * camR + m[1][1] * camG + m[1][2] * camB;
  var z = m[2][0] * camR + m[2][1] * camG + m[2][2] * camB;
  final sum = x + y + z;
  if (sum <= 0 || y <= 0) {
    return (kelvin: wbDefaultKelvin, tint: wbDefaultTint);
  }
  x /= sum;
  y /= sum;

  // McCamy's CCT approximation.
  final n = (x - 0.3320) / (0.1858 - y);
  var cct = 449.0 * n * n * n + 3525.0 * n * n + 6823.3 * n + 5520.33;
  cct = cct.clamp(2000.0, 50000.0);

  // Tint = signed distance off the Planckian locus in the CIE 1960 uv
  // plane, scaled to roughly track the -150..150 slider.
  final denom = -2.0 * x + 12.0 * y + 3.0;
  final u = 4.0 * x / denom;
  final v = 6.0 * y / denom;
  final locus = _planckianUv(cct);
  final duv = (v - locus.v) - (u - locus.u); // rough green/magenta projection
  final tint = (-duv * 3000.0).clamp(-150.0, 150.0);

  return (kelvin: cct, tint: tint);
}

List<List<double>> _cameraXyzOrFallback(List<List<double>> camXyz) {
  if (camXyz.length >= 3 && camXyz[0].length >= 3) {
    var nonZero = false;
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        if (camXyz[i][j] != 0) {
          nonZero = true;
        }
      }
    }
    if (nonZero) {
      return camXyz;
    }
  }
  // sRGB (linear) -> XYZ D65.
  return const [
    [0.4124, 0.3576, 0.1805],
    [0.2126, 0.7152, 0.0722],
    [0.0193, 0.1192, 0.9505],
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
