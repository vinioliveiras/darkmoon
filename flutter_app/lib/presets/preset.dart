import '../render/tone_curve.dart';

/// A named, reusable bundle of develop settings — the same shape as one
/// photo's edits (slider values + curves), just not tied to a specific
/// file. Doesn't include masks: real Lightroom presets don't carry local
/// adjustments either, since a mask's geometry is inherently tied to one
/// photo's composition.
class Preset {
  const Preset({
    required this.id,
    required this.name,
    required this.values,
    this.curves = identityPhotoCurves,
    this.unsupportedAttributes = const [],
    this.sourcePath,
  });

  final String id;
  final String name;
  final Map<String, double> values;
  final PhotoCurves curves;

  /// Absolute path of the `.xmp` file this preset is backed by, under
  /// `Documents/darkmoon/presets/`. The preset library *is* that folder —
  /// imported files are copied in byte-for-byte and never rewritten unless
  /// the user explicitly saves changes; presets created in-app are written
  /// out as `.xmp` there too. Null only transiently, before a freshly
  /// parsed preset has been placed in the folder.
  final String? sourcePath;

  /// Names of settings found in an imported file (e.g. a real Lightroom
  /// `.xmp`) that this app has no equivalent for — sharpening, lens
  /// corrections, camera profile, masks, etc. Empty for presets created
  /// in-app, since those can only ever contain settings we support.
  final List<String> unsupportedAttributes;

  Preset copyWith({
    String? id,
    String? name,
    Map<String, double>? values,
    PhotoCurves? curves,
    List<String>? unsupportedAttributes,
    String? sourcePath,
  }) => Preset(
    id: id ?? this.id,
    name: name ?? this.name,
    values: values ?? this.values,
    curves: curves ?? this.curves,
    unsupportedAttributes: unsupportedAttributes ?? this.unsupportedAttributes,
    sourcePath: sourcePath ?? this.sourcePath,
  );
}
