import 'color_grading.dart';
import 'color_mixer.dart';
import 'denoise.dart';
import 'tone_curve.dart';

/// The current value of every adjustment slider, passed into [renderRgb].
///
/// Field names mirror the Python app's `params` dict keys.
class RenderParams {
  const RenderParams({
    this.temperature = 5500,
    this.tint = 0,
    this.exposure = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.whites = 0,
    this.blacks = 0,
    this.texture = 0,
    this.clarity = 0,
    this.dehaze = 0,
    this.vibrance = 0,
    this.saturation = 0,
    this.curves = identityPhotoCurves,
    this.colorMixer = const ColorMixerValues(),
    this.colorGrading = const ColorGradingValues(),
    this.denoise = const DenoiseParams(),
  });

  /// Builds params from the editor's flat `{sliderName: value}` map, using
  /// this class's defaults for any slider not present. [colorMixer]'s 24
  /// keys, [colorGrading]'s 9 keys and [denoise]'s 6 keys all live in that
  /// same flat map, same as every other slider — only [curves] is passed
  /// separately, since a curve is a list of points, not a single double.
  factory RenderParams.fromValues(
    Map<String, double> values, {
    PhotoCurves? curves,
  }) {
    const defaults = RenderParams();
    return RenderParams(
      temperature: values['Temperature'] ?? defaults.temperature,
      tint: values['Tint'] ?? defaults.tint,
      exposure: values['Exposure'] ?? defaults.exposure,
      brightness: values['Brightness'] ?? defaults.brightness,
      contrast: values['Contrast'] ?? defaults.contrast,
      highlights: values['Highlights'] ?? defaults.highlights,
      shadows: values['Shadows'] ?? defaults.shadows,
      whites: values['Whites'] ?? defaults.whites,
      blacks: values['Blacks'] ?? defaults.blacks,
      texture: values['Texture'] ?? defaults.texture,
      clarity: values['Clarity'] ?? defaults.clarity,
      dehaze: values['Dehaze'] ?? defaults.dehaze,
      vibrance: values['Vibrance'] ?? defaults.vibrance,
      saturation: values['Saturation'] ?? defaults.saturation,
      curves: curves ?? defaults.curves,
      colorMixer: ColorMixerValues.fromValues(values),
      colorGrading: ColorGradingValues.fromValues(values),
      denoise: DenoiseParams.fromValues(values),
    );
  }

  final double temperature;
  final double tint;
  final double exposure;
  final double brightness;
  final double contrast;
  final double highlights;
  final double shadows;
  final double whites;
  final double blacks;
  final double texture;
  final double clarity;
  final double dehaze;
  final double vibrance;
  final double saturation;
  final PhotoCurves curves;
  final ColorMixerValues colorMixer;
  final ColorGradingValues colorGrading;
  final DenoiseParams denoise;
}
