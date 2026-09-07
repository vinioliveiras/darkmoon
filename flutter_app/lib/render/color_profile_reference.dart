import 'dart:typed_data';

import 'color_profile.dart';
import 'hsl.dart';

/// The reference chart the colour profile editor previews against.
///
/// Generated rather than a photograph, and that is the right call for this
/// particular job rather than a shortcut. A profile carries a correction
/// for all [colorProfileBins] hue bins and a tone curve across the whole
/// luminance range; no single photograph contains all of that, so editing
/// against one would leave most of the controls with nothing to show. The
/// chart holds every hue at once, the memory colours people actually
/// judge a profile by, and a neutral ramp for the tone curve.
///
/// The editor can preview against the open photo instead — that is what
/// the source switch in the dialog is for. The chart is what it opens
/// with, because it answers "what does this profile *do*" and the photo
/// answers "what does it do to *this*".
const int referenceChartWidth = 384;
const int referenceChartHeight = 144;

const int _bandHeight = referenceChartHeight ~/ 3;

/// Memory colours — the ones people notice first when a profile is wrong.
/// Three skin tones because skin is the least forgiving, then sky and
/// foliage, then three saturated patches that land in ranges the first
/// five miss.
const _memoryColours = <(double, double, double)>[
  (240, 200, 175), // pale skin
  (200, 150, 120), // mid skin
  (140, 95, 70), // deep skin
  (110, 150, 200), // sky
  (85, 120, 60), // foliage
  (180, 60, 55), // red
  (215, 180, 70), // yellow
  (130, 95, 165), // purple
];

/// Builds the chart as the pipeline's own packed RGB buffer — 0..255
/// valued floats, three per pixel — so [applyColorProfile] can be run on
/// it directly and the preview is produced by exactly the code that
/// renders the photo.
Float32List buildReferenceChart() {
  final rgb = Float32List(referenceChartWidth * referenceChartHeight * 3);

  void set(int x, int y, double r, double g, double b) {
    final i = (y * referenceChartWidth + x) * 3;
    rgb[i] = r;
    rgb[i + 1] = g;
    rgb[i + 2] = b;
  }

  for (var y = 0; y < referenceChartHeight; y++) {
    final band = y ~/ _bandHeight;
    for (var x = 0; x < referenceChartWidth; x++) {
      final t = x / (referenceChartWidth - 1);
      switch (band) {
        case 0:
          // Every hue, left to right, so all 24 bins are on screen at
          // once. Held at a saturation the per-hue correction actually
          // acts on: applyColorProfile gates itself on saturation, so a
          // washed-out sweep would show almost nothing.
          final (r, g, b) = hsvToRgb(t * 360.0, 0.75, 0.85);
          set(x, y, r * 255, g * 255, b * 255);
        case 1:
          final patch =
              _memoryColours[(t * _memoryColours.length).floor().clamp(
                0,
                _memoryColours.length - 1,
              )];
          set(x, y, patch.$1, patch.$2, patch.$3);
        default:
          // Neutral ramp for the tone curve. Neutral on purpose: the
          // per-hue correction leaves grey alone, so whatever moves here
          // is the tone curve and nothing else.
          final v = t * 255.0;
          set(x, y, v, v, v);
      }
    }
  }
  return rgb;
}
