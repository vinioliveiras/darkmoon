/// RGB <-> HSL conversion shared by the Color Mixer and Color Grading
/// pipelines (and their control-wheel widgets). RGB components are 0..1;
/// hue is degrees 0..360; saturation/lightness are 0..1.
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
