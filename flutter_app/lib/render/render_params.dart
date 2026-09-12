import 'ai_denoise.dart';
import 'calibration.dart';
import 'color_grading.dart';
import 'color_mixer.dart';
import 'color_profile.dart';
import 'film_lut.dart';
import 'grain.dart';
import 'sharpen.dart';
import 'tone_curve.dart';
import 'vignette.dart';

/// The current value of every adjustment slider, passed into [renderRgb].
///
/// Field names mirror the Python app's `params` dict keys.
///
/// **Adding a field?** If any GPU stage before Dehaze reads it (Exposure/WB,
/// chroma smoothing, AI denoise, Sharpen, Texture, Clarity, the colour
/// profile, Dehaze itself), add it to `GpuStageCache.keyFor` in
/// `lib/render/gpu/gpu_stage_cache.dart` and to its key test — the cache
/// resumes renders from stored stage outputs, and a field it does not know
/// about is a stale image on screen.
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
    this.saturationBoost = 0,
    this.curves = identityPhotoCurves,
    this.parametricCurve = identityParametricCurve,
    this.colorMixer = const ColorMixerValues(),
    this.colorGrading = const ColorGradingValues(),
    this.aiDenoise = const AiDenoiseParams(),
    this.sharpen = const SharpenParams(),
    this.vignette = const VignetteParams(),
    this.grain = const GrainParams(),
    this.filmLut,
    this.filmAmount = 0.5,
    this.renderScale = 1.0,
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
    double baseExposureStops = 0,
    double baseContrast = calBaseContrast,
    ColorProfile? colorProfile,
    double colorProfileStrength = 1.0,
    double renderScale = 1.0,
    bool cameraColorHasFit = false,
    FilmLut? filmLut,
  }) {
    const defaults = RenderParams();
    return RenderParams(
      filmLut: filmLut,
      filmAmount: ((values['FilmAmount'] ?? defaultFilmAmount) / 100).clamp(
        0.0,
        1.0,
      ),
      temperature: values['Temperature'] ?? asShotKelvin,
      tint: values['Tint'] ?? asShotTint,
      asShotKelvin: asShotKelvin,
      asShotTint: asShotTint,
      baseContrast: baseContrast,
      colorProfile: colorProfile,
      colorProfileStrength: colorProfileStrength,
      renderScale: renderScale,
      // The camera's own rendering of this shot sets where the Exposure
      // slider's zero sits, the same way as-shot white balance sets where
      // Temperature's does. Added here rather than written into the values
      // map so the global Amount slider cannot scale it: it is a baseline,
      // not an edit, and damping it would make a photo's starting
      // brightness depend on how strongly its edit is being applied.
      // Converted here, not by the caller: the slider is in slider units
      // (calExposureUnitsPerStop of them per stop — 1.0 since 2026-09-10,
      // so the two coincide today) and this arrives in stops. Adding them
      // without the conversion once divided the camera's offset by 12,
      // which read as the correction not working at all.
      exposure:
          (values['Exposure'] ?? defaults.exposure) +
          baseExposureStops * calExposureUnitsPerStop,
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
      // With a fit the slider rides the profile (the editor blends it in
      // before these params are built); without one it is a lift here.
      saturationBoost: cameraColorHasFit
          ? 0
          : ((values['CameraColor'] ?? 0) / 100).clamp(0.0, 1.0),
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

  /// 0..1: the Camera Color slider on a file with no camera fit to blend
  /// — spent as a saturation lift of [calCameraColorBoost] at 1, inside
  /// the Saturation stage. 0 when the photo carries a fit, which the
  /// slider blends into the colour profile instead (see
  /// [RenderParams.fromValues]'s `cameraColorHasFit`).
  final double saturationBoost;
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

  /// The "Film" look-up table (see `film_lut.dart`), applied last on both
  /// paths; null for no film. Resolved by the editor from the `Film`
  /// slider's id — the id itself never reaches here, only the table.
  final FilmLut? filmLut;

  /// 0..1 blend of [filmLut] over the untouched image — the Film section's
  /// Amount slider. Ignored when [filmLut] is null.
  final double filmAmount;

  /// Multiplier applied to every neighbourhood-based radius/sigma —
  /// `frameLongEdge / calRadiusReferenceLongEdge`.
  ///
  /// Set once per render from the *full frame's* long edge, never from a
  /// band's own height (`render_parallel.dart` splits the image into bands
  /// but every band must scale identically), and carried unchanged into
  /// each mask layer's own params.
  ///
  /// 1.0 means "render at the reference size", which is what the editing
  /// preview does at its default resolution — see
  /// [calRadiusReferenceLongEdge] for why the whole thing exists.
  final double renderScale;

  /// [renderScale] for the pixel-domain stages only — the always-on chroma
  /// smoothing, AI Denoise and Sharpen — capped at
  /// [calDetailRadiusMaxScale]. Noise and sharpening reach a fixed number
  /// of real pixels, not a fixed fraction of the frame; see that constant
  /// for the measurements that forced the split. Everything else
  /// (Clarity, Dehaze, Texture, the tonal blur) still uses the uncapped
  /// [renderScale].
  double get detailScale => renderScale < calDetailRadiusMaxScale
      ? renderScale
      : calDetailRadiusMaxScale;

  /// Every field carried across unchanged except [renderScale]. Written
  /// out rather than generated because this class is a plain value type
  /// with no code generation in the project; adding a field here without
  /// adding it below would silently reset it on any scaled render.
  RenderParams _copyWithRenderScale(double scale) => RenderParams(
    temperature: temperature,
    tint: tint,
    asShotKelvin: asShotKelvin,
    asShotTint: asShotTint,
    baseContrast: baseContrast,
    colorProfile: colorProfile,
    colorProfileStrength: colorProfileStrength,
    exposure: exposure,
    brightness: brightness,
    contrast: contrast,
    highlights: highlights,
    shadows: shadows,
    whites: whites,
    blacks: blacks,
    texture: texture,
    clarity: clarity,
    dehaze: dehaze,
    vibrance: vibrance,
    saturation: saturation,
    saturationBoost: saturationBoost,
    curves: curves,
    parametricCurve: parametricCurve,
    colorMixer: colorMixer,
    colorGrading: colorGrading,
    aiDenoise: aiDenoise,
    sharpen: sharpen,
    vignette: vignette,
    grain: grain,
    filmLut: filmLut,
    filmAmount: filmAmount,
    renderScale: scale,
  );

  /// A copy of these params with [renderScale] derived from the frame this
  /// render will actually run on.
  ///
  /// Set by the render entry points, after crop/lens geometry has settled
  /// the real dimensions — the editor cannot compute it when it builds the
  /// params, since a crop changes them.
  RenderParams withRenderScaleFor(int frameWidth, int frameHeight) {
    final longEdge = frameWidth > frameHeight ? frameWidth : frameHeight;
    return _copyWithRenderScale(longEdge / calRadiusReferenceLongEdge);
  }
}
