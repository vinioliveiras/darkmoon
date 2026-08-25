import 'dart:typed_data';

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

/// The 8 HSL color bands Lightroom's Color Mixer / HSL panel exposes,
/// centered on these approximate hue angles (degrees, 0-360).
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

  /// In hue order (0-360) — must line up 1:1 with [_channelCenterHues].
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

const _channelCenterHues = [0.0, 30.0, 60.0, 120.0, 180.0, 240.0, 275.0, 315.0];

/// How much weight a pixel at [hue] gives to a band centered at
/// [center] — 1 at the center, falling off linearly to 0 at 45° away
/// (adjacent bands' influence overlaps near their shared boundary, for a
/// smooth transition instead of a hard cutoff).
double _bandWeight(double hue, double center) {
  var diff = (hue - center).abs();
  if (diff > 180) {
    diff = 360 - diff;
  }
  const halfWidth = 45.0;
  return diff >= halfWidth ? 0.0 : 1.0 - diff / halfWidth;
}

/// Applies Lightroom-style selective HSL adjustments to packed RGB [img]
/// in place — a no-op when every channel is at its default.
///
/// Designed to run via `compute()`: pure function over simple,
/// isolate-transferable data (same as the rest of render.dart).
void applyColorMixer(Float32List img, ColorMixerValues mixer) {
  if (mixer.isIdentity) {
    return;
  }
  final channels = mixer._channels;
  for (var i = 0; i < img.length; i += 3) {
    final r = (img[i] / 255.0).clamp(0.0, 1.0);
    final g = (img[i + 1] / 255.0).clamp(0.0, 1.0);
    final b = (img[i + 2] / 255.0).clamp(0.0, 1.0);
    final hsl = rgbToHsl(r, g, b);
    var hue = hsl[0];
    final sat = hsl[1];
    final light = hsl[2];

    var hueShift = 0.0;
    var satShift = 0.0;
    // Luminance intentionally not applied — disabled per-channel in the
    // UI too (see editor_screen.dart's Mixer/HSL panel) after repeated
    // reports of it blowing out/pixelating pixels, even after fixing the
    // underlying GPU shader bug (a uniform array indexed by a non-
    // constant loop variable). A preset's MixerXLuminance value is still
    // parsed/stored (preset_xmp.dart) — just never applied — so nothing
    // breaks if it's re-enabled later.
    for (var c = 0; c < channels.length; c++) {
      final weight = _bandWeight(hue, _channelCenterHues[c]);
      if (weight <= 0) {
        continue;
      }
      hueShift += weight * channels[c].hue;
      satShift += weight * channels[c].saturation;
    }

    // Scaled down from the raw -100..100 slider range so a full-strength
    // adjustment shifts hue noticeably without blowing out — saturation
    // is left at 1:1 since it's already a relative multiplier.
    hue = (hue + hueShift * 0.3) % 360;
    if (hue < 0) {
      hue += 360;
    }
    final newSat = (sat * (1 + satShift / 100)).clamp(0.0, 1.0);
    final newLight = light;

    final rgb = hslToRgb(hue, newSat, newLight);
    img[i] = rgb[0] * 255.0;
    img[i + 1] = rgb[1] * 255.0;
    img[i + 2] = rgb[2] * 255.0;
  }
}
