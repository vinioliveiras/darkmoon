// Negative conversion (2026-09-12): a scanned or photographed colour
// negative turned into a positive. Like Solstice's converter it is a
// library action, not an edit: the Albums context menu opens
// `library/negative_conversion_dialog.dart`, which previews these
// functions and then writes a `<name>_Positive.tiff` beside each
// original (`library/negative_converter.dart`), and that file is what
// gets edited afterwards. (It was a render stage for a few hours on
// 2026-09-12; the user asked for Solstice's shape instead.)
//
// The method is Solstice's `negative_conversion.rs`, stage for stage:
//
// 1. Density: each channel becomes `-log10(linear)`, the film's optical
//    density. The orange mask and the base fog are then a per-channel
//    offset, not a colour cast.
// 2. Normalise per channel between the 0.1st and 99.9th percentile of
//    the density seen in the central 76% of the frame ([NegativeBounds],
//    measured once per photo). This is what neutralises the mask: each
//    channel's own black and white are mapped to 0 and 1.
// 3. Per-channel weights (the user's colour balance), then one sigmoid
//    tone curve with a contrast (its steepness) and an exposure (where
//    its midpoint sits), rescaled so 0 and 1 stay put.
// 4. Highlights above 0.9 lose saturation toward their luma, so a
//    clipped channel does not turn a bright area into a colour.
// 5. Output as 1/2.2 gamma, which is what the pipeline's display-referred
//    buffer holds.
//
// [applyNegative] (float buffer, the dialog's preview) and
// [convertNegativeRgb16] (bytes in, 16-bit out, the file) run the same
// arithmetic; keep the two identical.

import 'dart:math' as math;
import 'dart:typed_data';

import 'color_space.dart';

/// Where the density curve's midpoint sits at exposure 0.
const negativeCurveCentre = 0.6;

/// How far one unit of the Exposure slider moves that midpoint.
const negativeExposureShift = 0.25;

/// Curve steepness per unit of Contrast (1.0 = Solstice's default look).
const negativeContrastGain = 4.0;

class NegativeParams {
  const NegativeParams({
    this.enabled = false,
    this.redWeight = 1.0,
    this.greenWeight = 1.0,
    this.blueWeight = 1.0,
    this.exposure = 0.0,
    this.contrast = 1.0,
  });

  /// Builds from the editor's flat `{sliderName: value}` map. `Negative`
  /// is the section switch (0/1); the rest are its sliders.
  factory NegativeParams.fromValues(Map<String, double> values) {
    const d = NegativeParams();
    return NegativeParams(
      enabled: (values['Negative'] ?? 0) != 0,
      redWeight: values['NegativeRed'] ?? d.redWeight,
      greenWeight: values['NegativeGreen'] ?? d.greenWeight,
      blueWeight: values['NegativeBlue'] ?? d.blueWeight,
      exposure: values['NegativeExposure'] ?? d.exposure,
      contrast: values['NegativeContrast'] ?? d.contrast,
    );
  }

  final bool enabled;
  final double redWeight;
  final double greenWeight;
  final double blueWeight;

  /// -1..1: shifts the curve's midpoint, brighter for positive values.
  final double exposure;

  /// 0.5..2: the curve's steepness.
  final double contrast;

  /// The sigmoid's constants, shared by the CPU loop and the shader
  /// uniforms: steepness [k], midpoint [x0], and the [y0]/[scale] that
  /// pin the curve's ends to 0 and 1.
  ({double k, double x0, double y0, double scale}) get curve {
    final k = negativeContrastGain * math.max(contrast, 0.1);
    final x0 = negativeCurveCentre - exposure * negativeExposureShift;
    final y0 = 1.0 / (1.0 + math.exp(k * x0));
    final y1 = 1.0 / (1.0 + math.exp(-k * (1.0 - x0)));
    return (k: k, x0: x0, y0: y0, scale: 1.0 / (y1 - y0));
  }

  @override
  bool operator ==(Object other) =>
      other is NegativeParams &&
      other.enabled == enabled &&
      other.redWeight == redWeight &&
      other.greenWeight == greenWeight &&
      other.blueWeight == blueWeight &&
      other.exposure == exposure &&
      other.contrast == contrast;

  @override
  int get hashCode => Object.hash(
    enabled,
    redWeight,
    greenWeight,
    blueWeight,
    exposure,
    contrast,
  );
}

/// Per-channel density range of one photo — what [applyNegative]
/// normalises against. Measured by [analyzeNegativeBounds] from the
/// source pixels, once, and carried in `RenderParams` beside the sliders
/// so the GPU pass gets it as uniforms.
class NegativeBounds {
  const NegativeBounds({required this.min, required this.max});

  /// Density (`-log10(linear)`) at the 0.1st percentile, per channel.
  final List<double> min;

  /// Density at the 99.9th percentile, per channel; always > [min].
  final List<double> max;

  @override
  bool operator ==(Object other) =>
      other is NegativeBounds &&
      other.min[0] == min[0] &&
      other.min[1] == min[1] &&
      other.min[2] == min[2] &&
      other.max[0] == max[0] &&
      other.max[1] == max[1] &&
      other.max[2] == max[2];

  @override
  int get hashCode =>
      Object.hash(min[0], min[1], min[2], max[0], max[1], max[2]);

  @override
  String toString() =>
      'NegativeBounds(min: ${min.map((v) => v.toStringAsFixed(3)).join(',')}'
      ' max: ${max.map((v) => v.toStringAsFixed(3)).join(',')})';
}

double _density(double srgb8) =>
    -_log10(srgbToLinear(srgb8 / 255.0).clamp(1e-6, 1.0));

double _log10(double v) => math.log(v) / math.ln10;

/// Measures [NegativeBounds] on packed sRGB 8-bit [rgb] of [width] x
/// [height]: the 0.1st and 99.9th percentile of density per channel over
/// the central 76% of the frame (a 12% margin on each side keeps the
/// scanner's border and the film rebate out), sampled every third row
/// and about 40 000 pixels in all, exactly Solstice's `analyze_bounds`.
NegativeBounds analyzeNegativeBounds(Uint8List rgb, int width, int height) {
  final marginX = (width * 0.12).floor();
  final marginY = (height * 0.12).floor();
  final innerW = math.max(width - marginX * 2, 1);
  final innerH = math.max(height - marginY * 2, 1);
  final step = math.max(innerW * innerH ~/ 40000, 1);
  final r = <double>[], g = <double>[], b = <double>[];
  for (var y = marginY; y < height - marginY; y += 3) {
    final row = y * width * 3;
    for (var x = marginX; x < width - marginX; x += step) {
      final i = row + x * 3;
      if (i + 2 >= rgb.length) continue;
      r.add(_density(rgb[i].toDouble()));
      g.add(_density(rgb[i + 1].toDouble()));
      b.add(_density(rgb[i + 2].toDouble()));
    }
  }
  (double, double) bounds(List<double> vals) {
    if (vals.isEmpty) return (0.0, 1.0);
    vals.sort();
    final lo = vals[((vals.length * 0.001).floor()).clamp(0, vals.length - 1)];
    final hi = vals[((vals.length * 0.999).floor()).clamp(0, vals.length - 1)];
    return (lo, hi <= lo + 0.0001 ? lo + 1.0 : hi);
  }

  final (rMin, rMax) = bounds(r);
  final (gMin, gMax) = bounds(g);
  final (bMin, bMax) = bounds(b);
  return NegativeBounds(min: [rMin, gMin, bMin], max: [rMax, gMax, bMax]);
}

/// Converts the packed sRGB 0..255 [buffer] in place — see the file
/// comment for the stages. A no-op unless [params] is enabled.
void applyNegative(
  Float32List buffer,
  NegativeParams params,
  NegativeBounds bounds,
) {
  if (!params.enabled) return;
  final c = params.curve;
  final k = c.k, x0 = c.x0, y0 = c.y0, scale = c.scale;
  final weights = [params.redWeight, params.greenWeight, params.blueWeight];
  final out = Float64List(3);
  for (var i = 0; i < buffer.length; i += 3) {
    for (var ch = 0; ch < 3; ch++) {
      final d = _density(buffer[i + ch]);
      var n = (d - bounds.min[ch]) / (bounds.max[ch] - bounds.min[ch]);
      n = math.max(n, 0.0) * weights[ch];
      final sigmoid = 1.0 / (1.0 + math.exp(-k * (n - x0)));
      out[ch] = ((sigmoid - y0) * scale).clamp(0.0, 1.0);
    }
    var r = out[0], g = out[1], b = out[2];
    final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final maxCh = math.max(r, math.max(g, b));
    if (maxCh > 0.9) {
      final overflow = ((maxCh - 0.9) * 10.0).clamp(0.0, 1.0);
      final satReduction = overflow * overflow;
      r += (luma - r) * satReduction;
      g += (luma - g) * satReduction;
      b += (luma - b) * satReduction;
    }
    buffer[i] = math.pow(r.clamp(0.0, 1.0), 1 / 2.2) * 255.0;
    buffer[i + 1] = math.pow(g.clamp(0.0, 1.0), 1 / 2.2) * 255.0;
    buffer[i + 2] = math.pow(b.clamp(0.0, 1.0), 1 / 2.2) * 255.0;
  }
}

/// [analyzeNegativeBounds] on a copy of [rgb] shrunk so its long edge is
/// at most [maxDim] — what the file converter measures on, like
/// Solstice's 1080 px reference: the percentiles are the same to well
/// within a level, and a 24 MP frame does not need 24 M samples to say
/// where its black and white are.
NegativeBounds analyzeNegativeBoundsDownscaled(
  Uint8List rgb,
  int width,
  int height, {
  int maxDim = 1080,
}) {
  final scale = math.max(width, height) / maxDim;
  if (scale <= 1) {
    return analyzeNegativeBounds(rgb, width, height);
  }
  final w = math.max(1, (width / scale).round());
  final h = math.max(1, (height / scale).round());
  final small = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    final sy = math.min(height - 1, (y * scale).floor());
    for (var x = 0; x < w; x++) {
      final sx = math.min(width - 1, (x * scale).floor());
      final s = (sy * width + sx) * 3, d = (y * w + x) * 3;
      small[d] = rgb[s];
      small[d + 1] = rgb[s + 1];
      small[d + 2] = rgb[s + 2];
    }
  }
  return analyzeNegativeBounds(small, w, h);
}

/// [applyNegative]'s arithmetic on packed 8-bit sRGB [rgb], written out
/// as 16-bit samples (0..65535) — the converter's path: the same stages
/// without a 3-float-per-pixel working buffer, and with the tone curve's
/// smooth output kept for the 16-bit TIFF instead of rounded to a byte.
Uint16List convertNegativeRgb16(
  Uint8List rgb,
  NegativeParams params,
  NegativeBounds bounds,
) {
  final out = Uint16List(rgb.length);
  final c = params.curve;
  final k = c.k, x0 = c.x0, y0 = c.y0, scale = c.scale;
  final weights = [params.redWeight, params.greenWeight, params.blueWeight];
  // Density per input level, once: 256 entries per channel share it.
  final density = Float64List(256);
  for (var v = 0; v < 256; v++) {
    density[v] = _density(v.toDouble());
  }
  final px = Float64List(3);
  for (var i = 0; i < rgb.length; i += 3) {
    for (var ch = 0; ch < 3; ch++) {
      var n =
          (density[rgb[i + ch]] - bounds.min[ch]) /
          (bounds.max[ch] - bounds.min[ch]);
      n = math.max(n, 0.0) * weights[ch];
      final sigmoid = 1.0 / (1.0 + math.exp(-k * (n - x0)));
      px[ch] = ((sigmoid - y0) * scale).clamp(0.0, 1.0);
    }
    var r = px[0], g = px[1], b = px[2];
    final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final maxCh = math.max(r, math.max(g, b));
    if (maxCh > 0.9) {
      final overflow = ((maxCh - 0.9) * 10.0).clamp(0.0, 1.0);
      final satReduction = overflow * overflow;
      r += (luma - r) * satReduction;
      g += (luma - g) * satReduction;
      b += (luma - b) * satReduction;
    }
    out[i] = (math.pow(r.clamp(0.0, 1.0), 1 / 2.2) * 65535).round();
    out[i + 1] = (math.pow(g.clamp(0.0, 1.0), 1 / 2.2) * 65535).round();
    out[i + 2] = (math.pow(b.clamp(0.0, 1.0), 1 / 2.2) * 65535).round();
  }
  return out;
}
