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
  });

  /// Builds params from the editor's flat `{sliderName: value}` map, using
  /// this class's defaults for any slider not present.
  factory RenderParams.fromValues(Map<String, double> values) {
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
}
