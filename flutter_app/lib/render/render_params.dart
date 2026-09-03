import 'ai_denoise.dart';
import 'calibration.dart';
import 'color_grading.dart';
import 'color_mixer.dart';
import 'color_profile.dart';
import 'grain.dart';
import 'sharpen.dart';
import 'tone_curve.dart';
import 'vignette.dart';

/// The current value of every adjustment slider, passed into [renderRgb].
///
/// Field names mirror the Python app's `params` dict keys.
class RenderParams {
  const RenderParams({
    this.temperature = 5500,
    this.tint = 0,
    this.asShotKelvin = 5500,
    this.asShotTint = 0,
    this.baseContrast = calBaseContrast,
    this.colorProfile,
    this.colorProfileStrength = 1.0,
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
    this.parametricCurve = identityParametricCurve,
    this.colorMixer = const ColorMixerValues(),
    this.colorGrading = const ColorGradingValues(),
    this.aiDenoise = const AiDenoiseParams(),
    this.sharpen = const SharpenParams(),
    this.vignette = const VignetteParams(),
    this.grain = const GrainParams(),
  });

  /// Builds params from the editor's flat `{sliderName: value}` map, using
  /// this class's defaults for any slider not present. [colorMixer]'s 24
  /// keys, [colorGrading]'s 12 keys, [aiDenoise]'s 1 key, [sharpen]'s 4
  /// keys and [vignette]'s 3 keys all live in that same flat map, same as
  /// every other slider — only [curves] is passed separately, since a
  /// curve is a list of points, not a single double.
  factory RenderParams.fromValues(
    Map<String, double> values, {
    PhotoCurves? curves,
    double asShotKelvin = 5500,
    double asShotTint = 0,
    double baseContrast = calBaseContrast,
    ColorProfile? colorProfile,
    double colorProfileStrength = 1.0,
  }) {
    const defaults = RenderParams();
    return RenderParams(
      temperature: values['Temperature'] ?? asShotKelvin,
      tint: values['Tint'] ?? asShotTint,
      asShotKelvin: asShotKelvin,
      asShotTint: asShotTint,
      baseContrast: baseContrast,
      colorProfile: colorProfile,
      colorProfileStrength: colorProfileStrength,
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
      parametricCurve: ParametricCurve.fromValues(values),
      colorMixer: ColorMixerValues.fromValues(values),
      colorGrading: ColorGradingValues.fromValues(values),
      aiDenoise: AiDenoiseParams.fromValues(values),
      sharpen: SharpenParams.fromValues(values),
      vignette: VignetteParams.fromValues(values),
      grain: GrainParams.fromValues(values),
    );
  }

  final double temperature;
  final double tint;

  /// Strength of the fixed "profile" S-curve every photo gets before the
  /// tone sliders — darkmoon's stand-in for the contrast the Adobe Color
  /// profile bakes into Meridian's own zero-edit rendering (see
  /// [calBaseContrast]). Same scale as the Contrast slider. Not a user
  /// slider and not read from the values map — it's per-pipeline context,
  /// like [asShotKelvin]; only tests that isolate a non-tonal step set it
  /// to 0 to keep their reference numbers exact.
  final double baseContrast;

  /// The fitted "darkmoon Color" per-hue correction — darkmoon's stand-in
  /// for the Adobe Color profile's HueSatMap (see `color_profile.dart`).
  /// Null = no correction (the pre-profile behaviour). Loaded from a
  /// bundled asset on the main isolate and threaded through like [curves],
  /// not carried in the values map.
  final ColorProfile? colorProfile;

  /// 0..1 blend of [colorProfile] toward identity — backs the "darkmoon
  /// Color" amount slider. Ignored when [colorProfile] is null.
  final double colorProfileStrength;

  /// The photo's camera as-shot white balance (from `RawMetadata`), used
  /// as the neutral reference for [temperature]/[tint]: at
  /// `temperature == asShotKelvin && tint == asShotTint` the White Balance
  /// step is a no-op. 5500 K / 0 for non-RAW files and RAWs without camera
  /// multipliers — the pre-existing fixed reference.
  final double asShotKelvin;
  final double asShotTint;

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

  /// Meridian's parametric Tone Curve (region sliders). Applied just
  /// before [curves]'s point Tone Curve — see `applyPostDenoisePointOps`.
  final ParametricCurve parametricCurve;
  final ColorMixerValues colorMixer;
  final ColorGradingValues colorGrading;
  final AiDenoiseParams aiDenoise;
  final SharpenParams sharpen;
  final VignetteParams vignette;
  final GrainParams grain;
}
