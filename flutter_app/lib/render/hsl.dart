/// RGB <-> HSL/HSV conversion shared by the Color Mixer and Color Grading
/// pipelines (and their control-wheel widgets). RGB components are 0..1;
/// hue is degrees 0..360; saturation/lightness/value are 0..1.
library;

/// Converts [r], [g], [b] (each 0..1) to `[hue, saturation, lightness]`.
List<double> rgbToHsl(double r, double g, double b) {
  final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final light = (maxC + minC) / 2;
  if (maxC == minC) {
    return [0.0, 0.0, light];
  }
  final d = maxC - minC;
  final sat = light > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC);
  double hue;
  if (maxC == r) {
    hue = (g - b) / d + (g < b ? 6 : 0);
  } else if (maxC == g) {
    hue = (b - r) / d + 2;
  } else {
    hue = (r - g) / d + 4;
  }
  hue *= 60;
  return [hue, sat, light];
}

double _hueToRgbComponent(double p, double q, double t) {
  var tt = t;
  if (tt < 0) {
    tt += 1;
  }
  if (tt > 1) {
    tt -= 1;
  }
  if (tt < 1 / 6) {
    return p + (q - p) * 6 * tt;
  }
  if (tt < 1 / 2) {
    return q;
  }
  if (tt < 2 / 3) {
    return p + (q - p) * (2 / 3 - tt) * 6;
  }
  return p;
}

/// Converts [h] (degrees, 0..360), [s] and [l] (each 0..1) to
/// `[r, g, b]` (each 0..1).
List<double> hslToRgb(double h, double s, double l) {
  if (s == 0) {
    return [l, l, l];
  }
  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  final hk = h / 360;
  return [
    _hueToRgbComponent(p, q, hk + 1 / 3),
    _hueToRgbComponent(p, q, hk),
    _hueToRgbComponent(p, q, hk - 1 / 3),
  ];
}

/// Converts [r], [g], [b] (each 0..1) to `(hue, saturation, value)` —
/// same convention as RapidRAW's `rgb_to_hsv` (WGSL), which is HSV, not
/// HSL: value is the max channel, not `(max+min)/2`.
///
/// Returns a record, not a `List<double>` — this runs once or twice per
/// pixel in `color_mixer.dart`'s (and `color_profile.dart`'s) hot loop,
/// and a heap-allocated List per pixel across a full-resolution export
/// was a measurable source of GC pressure (records are value types: no
/// allocation).
(double hue, double saturation, double value) rgbToHsv(
  double r,
  double g,
  double b,
) {
  final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final delta = maxC - minC;
  var hue = 0.0;
  if (delta > 0) {
    if (maxC == r) {
      hue = 60.0 * ((g - b) / delta % 6.0);
    } else if (maxC == g) {
      hue = 60.0 * ((b - r) / delta + 2.0);
    } else {
      hue = 60.0 * ((r - g) / delta + 4.0);
    }
    if (hue < 0) hue += 360.0;
  }
  return (hue, maxC == 0 ? 0.0 : delta / maxC, maxC);
}

/// Converts [h] (degrees, 0..360), [s] and [v] (each 0..1) to `(r, g, b)`
/// (each 0..1) — inverse of [rgbToHsv], same convention as RapidRAW's
/// `hsv_to_rgb` (WGSL).
///
/// Returns a record — see [rgbToHsv]'s doc comment; this version also
/// drops the old intermediate `rgbPrime` list, so a per-pixel call here
/// used to cost two heap allocations and now costs none.
(double r, double g, double b) hsvToRgb(double h, double s, double v) {
  final c = v * s;
  final x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
  final m = v - c;
  if (h < 60) return (c + m, x + m, m);
  if (h < 120) return (x + m, c + m, m);
  if (h < 180) return (m, c + m, x + m);
  if (h < 240) return (m, x + m, c + m);
  if (h < 300) return (x + m, m, c + m);
  return (c + m, m, x + m);
}
