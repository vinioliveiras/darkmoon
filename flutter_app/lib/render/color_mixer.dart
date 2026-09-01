import 'dart:math' as math;
import 'dart:typed_data';

import 'calibration.dart';
import 'color_space.dart';
import 'hsl.dart';

/// One color band's Hue/Saturation/Luminance adjustment, each -100..100
/// with 0 meaning no change — mirrors the sliders in the editor's Color
/// Mixer panel.
class ChannelAdjust {
  const ChannelAdjust({this.hue = 0, this.saturation = 0, this.luminance = 0});

  final double hue;
  final double saturation;
  final double luminance;

  bool get isIdentity => hue == 0 && saturation == 0 && luminance == 0;
}

/// The 8 HSL color bands Meridian's Color Mixer / HSL panel exposes —
/// see [_hslRanges] for each band's actual hue center/width.
class ColorMixerValues {
  const ColorMixerValues({
    this.red = const ChannelAdjust(),
    this.orange = const ChannelAdjust(),
    this.yellow = const ChannelAdjust(),
    this.green = const ChannelAdjust(),
    this.aqua = const ChannelAdjust(),
    this.blue = const ChannelAdjust(),
    this.purple = const ChannelAdjust(),
    this.magenta = const ChannelAdjust(),
  });

  /// Builds mixer values from the editor's flat `{sliderName: value}` map
  /// — each channel's three sliders are keyed "Mixer" + channel name +
  /// "Hue/Saturation/Luminance" (e.g. `'MixerRedHue'`), same convention as
  /// every other slider.
  factory ColorMixerValues.fromValues(Map<String, double> values) {
    ChannelAdjust channel(String name) => ChannelAdjust(
      hue: values['Mixer${name}Hue'] ?? 0,
      saturation: values['Mixer${name}Saturation'] ?? 0,
      luminance: values['Mixer${name}Luminance'] ?? 0,
    );
    return ColorMixerValues(
      red: channel('Red'),
      orange: channel('Orange'),
      yellow: channel('Yellow'),
      green: channel('Green'),
      aqua: channel('Aqua'),
      blue: channel('Blue'),
      purple: channel('Purple'),
      magenta: channel('Magenta'),
    );
  }

  final ChannelAdjust red;
  final ChannelAdjust orange;
  final ChannelAdjust yellow;
  final ChannelAdjust green;
  final ChannelAdjust aqua;
  final ChannelAdjust blue;
  final ChannelAdjust purple;
  final ChannelAdjust magenta;

  /// In hue order (0-360) — must line up 1:1 with [_hslRanges].
  List<ChannelAdjust> get _channels => [
    red,
    orange,
    yellow,
    green,
    aqua,
    blue,
    purple,
    magenta,
  ];

  bool get isIdentity => _channels.every((c) => c.isIdentity);
}

/// One color band's hue center and half-influence width (degrees) — the
/// exact values Solstice's `HSL_RANGES` uses in shader.wgsl. Notably not
/// evenly spaced (Red centers on 358°, not 0°; Green is the widest band
/// at 90°) and not paired with a matching per-band width the way a naive
/// "45° apart, 45° wide" model would assume.
class _HslRange {
  const _HslRange(this.center, this.width);
  final double center;
  final double width;
}

/// In the same order as [ColorMixerValues._channels].
const _hslRanges = [
  _HslRange(358.0, 35.0), // Red
  _HslRange(25.0, 45.0), // Orange
  _HslRange(60.0, 40.0), // Yellow
  _HslRange(115.0, 90.0), // Green
  _HslRange(180.0, 60.0), // Aqua
  _HslRange(225.0, 60.0), // Blue
  _HslRange(280.0, 55.0), // Purple
  _HslRange(330.0, 50.0), // Magenta
];

/// A band's raw (pre-normalization) influence on a pixel at [hue] —
/// Solstice's `get_raw_hsl_influence`: a Gaussian falloff around [center],
/// scaled by [width], rather than a hard cutoff — every band has *some*
/// (if vanishingly small) influence on every hue, which is what makes the
/// per-pixel normalization in [applyColorMixer] meaningful (all 8 raw
/// influences always sum to something usable, never all-zero).
double _rawHslInfluence(double hue, double center, double width) {
  var dist = (hue - center).abs();
  if (dist > 180) {
    dist = 360 - dist;
  }
  const sharpness = calMixerBandSharpness;
  final falloff = dist / (width * 0.5);
  return math.exp(-sharpness * falloff * falloff);
}

/// Per-band influence sampled at every integer hue (0..360) — the
/// Gaussian is smooth enough that nearest-degree lookup replaces 8
/// `exp()` calls per pixel with 8 array reads (the `exp` was a big chunk
/// of a full-resolution render's Color Mixer cost). Built once, lazily.
final List<Float64List> _influenceByHue = [
  for (final range in _hslRanges)
    Float64List.fromList([
      for (var h = 0; h <= 360; h++)
        _rawHslInfluence(h.toDouble(), range.center, range.width),
    ]),
];

double _smoothstep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

double _linearLuma(double r, double g, double b) =>
    0.2126 * r + 0.7152 * g + 0.0722 * b;

/// Applies Meridian-style selective HSL adjustments to packed RGB [img]
/// in place — a no-op when every channel is at its default.
///
/// A faithful port of Solstice's `apply_hsl_panel` (shader.wgsl): works in
/// scene-linear light (not the gamma-encoded byte buffer directly), uses
/// HSV rather than HSL (so brightness is tracked as luma and explicitly
/// restored after the hue/saturation shift, rather than relying on HSL's
/// lightness channel — the two aren't the same thing perceptually), and
/// weighs each of the 8 bands by a per-pixel-normalized Gaussian influence
/// ([_rawHslInfluence]) instead of a linear cutoff. The whole adjustment is
/// also gated by how saturated the source pixel already is
/// ([_smoothstep]-based masks), same as Solstice: a Hue/Saturation shift on
/// a desaturated pixel has nothing to grab onto and is left alone.
///
/// Luminance is included (re-enabled in editor_screen.dart's Mixer/HSL
/// panel alongside this port) — a different code path from the one
/// previously disabled after reports of it blowing out/pixelating pixels:
/// that one relied on HSL lightness directly; this one tracks luma
/// explicitly and restores it via a proportional rescale after the
/// hue/saturation shift, same as Solstice.
///
/// Designed to run via `compute()`: pure function over simple,
/// isolate-transferable data (same as the rest of render.dart).
void applyColorMixer(Float32List img, ColorMixerValues mixer) {
  if (mixer.isIdentity) {
    return;
  }
  final channels = mixer._channels;
  final n = channels.length;
  // Per-channel adjustment amounts, hoisted out of the pixel loop.
  final hueAmt = Float64List(n);
  final satAmt = Float64List(n);
  final lumAmt = Float64List(n);
  for (var c = 0; c < n; c++) {
    hueAmt[c] = channels[c].hue * calMixerHueStrength;
    satAmt[c] = channels[c].saturation / 100.0;
    lumAmt[c] = channels[c].luminance / 100.0;
  }
  final rawInfluences = Float64List(n);

  for (var i = 0; i < img.length; i += 3) {
    final r = srgbToLinear(img[i] / 255.0);
    final g = srgbToLinear(img[i + 1] / 255.0);
    final b = srgbToLinear(img[i + 2] / 255.0);
    if ((r - g).abs() < 0.001 && (g - b).abs() < 0.001) {
      continue;
    }

    final (originalHue, originalSat, originalVal) = rgbToHsv(r, g, b);
    final originalLuma = _linearLuma(r, g, b);

    final saturationMask = _smoothstep(0.05, 0.20, originalSat);
    final luminanceWeight = _smoothstep(0.0, 1.0, originalSat);
    if (saturationMask < 0.001 && luminanceWeight < 0.001) {
      continue;
    }

    final hueIdx = originalHue.round() % 360;
    var totalRawInfluence = 0.0;
    for (var c = 0; c < n; c++) {
      final influence = _influenceByHue[c][hueIdx];
      rawInfluences[c] = influence;
      totalRawInfluence += influence;
    }

    var totalHueShift = 0.0;
    var totalSatMultiplier = 0.0;
    var totalLumAdjust = 0.0;
    for (var c = 0; c < n; c++) {
      final normalizedInfluence = rawInfluences[c] / totalRawInfluence;
      final hueSatInfluence = normalizedInfluence * saturationMask;
      final lumaInfluence = normalizedInfluence * luminanceWeight;
      // hueAmt/satAmt/lumAmt are precomputed per channel above: hue folds
      // in `calMixerHueStrength` (was Solstice's 0.3 × the shader's ×2.0 =
      // 0.6, raised toward the Meridian Color Mixer — see calibration.dart),
      // sat/lum are just /100.
      totalHueShift += hueAmt[c] * hueSatInfluence;
      totalSatMultiplier += satAmt[c] * hueSatInfluence;
      totalLumAdjust += lumAmt[c] * lumaInfluence;
    }

    if (originalSat * (1.0 + totalSatMultiplier) < 0.0001) {
      // Matches apply_hsl_panel's own near-zero-saturation fallback: the
      // pixel collapses to gray at its (Luminance-adjusted) luma, not its
      // HSV value (the max channel) — those two aren't the same number
      // for a non-gray color.
      final finalLuma = (originalLuma * (1.0 + totalLumAdjust)).clamp(0.0, 1.0);
      final v = linearToSrgb(finalLuma) * 255.0;
      img[i] = v;
      img[i + 1] = v;
      img[i + 2] = v;
      continue;
    }

    var hue = (originalHue + totalHueShift + 360.0) % 360.0;
    if (hue < 0) {
      hue += 360.0;
    }
    final sat = (originalSat * (1.0 + totalSatMultiplier)).clamp(0.0, 1.0);
    final (sr, sg, sb) = hsvToRgb(hue, sat, originalVal);
    final newLuma = _linearLuma(sr, sg, sb);
    final targetLuma = originalLuma * (1.0 + totalLumAdjust);

    final double fr;
    final double fg;
    final double fb;
    if (newLuma < 0.0001) {
      fr = fg = fb = math.max(0.0, targetLuma);
    } else {
      final scale = targetLuma / newLuma;
      fr = sr * scale;
      fg = sg * scale;
      fb = sb * scale;
    }
    img[i] = linearToSrgb(fr) * 255.0;
    img[i + 1] = linearToSrgb(fg) * 255.0;
    img[i + 2] = linearToSrgb(fb) * 255.0;
  }
}
