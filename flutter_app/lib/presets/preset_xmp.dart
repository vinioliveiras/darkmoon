import 'package:xml/xml.dart';

import '../render/tone_curve.dart';
import 'preset.dart';

/// Reads/writes Lightroom-compatible `.xmp` Develop Preset files —
/// specifically the `crs:` (Camera Raw Settings) attributes that have a
/// real equivalent in this app's own adjustment set. Attributes this app
/// doesn't support (lens corrections, crop, camera profile, camera
/// calibration, point color, masks, ...) are simply left out on export
/// and ignored on import, rather than erroring.
///
/// This is *file-format* compatibility, not *rendering* compatibility —
/// Lightroom's actual Camera Raw pipeline is proprietary, so a preset
/// built here and opened in real Lightroom (or vice versa) will carry the
/// same slider values, but won't necessarily look pixel-identical, since
/// the two apps process those values through different code entirely.
const _crsNamespace = 'http://ns.adobe.com/camera-raw-settings/1.0/';
const _rdfNamespace = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';

/// (our slider key, crs: attribute name) — same numeric meaning and
/// range on both sides, no conversion needed.
const _directMappings = [
  ('Temperature', 'Temperature'),
  ('Tint', 'Tint'),
  ('Contrast', 'Contrast2012'),
  ('Highlights', 'Highlights2012'),
  ('Shadows', 'Shadows2012'),
  ('Whites', 'Whites2012'),
  ('Blacks', 'Blacks2012'),
  ('Texture', 'Texture'),
  ('Clarity', 'Clarity2012'),
  ('Dehaze', 'Dehaze'),
  ('Vibrance', 'Vibrance'),
  ('Saturation', 'Saturation'),
  ('SharpenAmount', 'Sharpness'),
  ('SharpenRadius', 'SharpenRadius'),
  ('SharpenDetail', 'SharpenDetail'),
  ('SharpenMasking', 'SharpenEdgeMasking'),
  ('VignetteAmount', 'PostCropVignetteAmount'),
  ('VignetteMidpoint', 'PostCropVignetteMidpoint'),
  ('VignetteFeather', 'PostCropVignetteFeather'),
  ('GrainAmount', 'GrainAmount'),
  ('GrainSize', 'GrainSize'),
  ('GrainRoughness', 'GrainFrequency'),
  ('ParamCurveShadows', 'ParametricShadows'),
  ('ParamCurveDarks', 'ParametricDarks'),
  ('ParamCurveLights', 'ParametricLights'),
  ('ParamCurveHighlights', 'ParametricHighlights'),
  ('ParamCurveShadowSplit', 'ParametricShadowSplit'),
  ('ParamCurveMidtoneSplit', 'ParametricMidtoneSplit'),
  ('ParamCurveHighlightSplit', 'ParametricHighlightSplit'),
];

const _mixerChannels = [
  'Red',
  'Orange',
  'Yellow',
  'Green',
  'Aqua',
  'Blue',
  'Purple',
  'Magenta',
];

/// (our Color Grading range name, Lightroom's crs: range name).
const _gradeRanges = [
  ('Shadows', 'Shadow'),
  ('Midtones', 'Midtone'),
  ('Highlights', 'Highlight'),
  ('Global', 'Global'),
];

/// (our Color Grading range name, legacy Split Toning hue/saturation
/// attribute names) — Split Toning predates the Color Grading wheels and
/// only ever covered shadows/highlights (no midtone or global control).
/// Many presets — especially ones ported forward from older Lightroom
/// versions — still carry these instead of (or alongside) the modern
/// `ColorGrade*` attributes, so they're used as a fallback when the
/// modern ones are absent, applied onto the very same Shadows/Highlights
/// grading zones we already render.
const _splitToningFallback = [
  ('Shadows', 'SplitToningShadowHue', 'SplitToningShadowSaturation'),
  ('Highlights', 'SplitToningHighlightHue', 'SplitToningHighlightSaturation'),
];

/// Just Ignore the next comment, its wrong!
/// Our Exposure is scaled to +-3 stops of actual brightness change (see
/// the `exposure / 100.0 * 3.0` factor in render.dart and render_gpu.dart)
/// over a -100..100 slider; Lightroom's Exposure2012 is stops directly,
/// -5..5. Converting through "stops" (rather than a direct 1:1 on the raw
/// slider number) is what makes a round trip (export then re-import) land
/// back on the same value, and is at least a defensible mapping for a real
/// Lightroom preset's Exposure2012 too. This must stay in sync with the
/// `3.0` stops-at-max factor in the renderers, or an imported preset's
/// Exposure2012 lands on the wrong slider value.
const _exposureStopsAtMax = 100.0;

/// `crs:` attributes that are structural/metadata rather than an actual
/// develop setting — present on real Lightroom preset exports but with
/// nothing for a user to see "not applied" about, so they're excluded
/// from [Preset.unsupportedAttributes] even though we don't map them.
const _structuralCrsAttributes = {
  'PresetType',
  'Cluster',
  'UUID',
  'Version',
  'ProcessVersion',
  'HasSettings',
  'SupportsAmount2',
  'SupportsColor',
  'SupportsMonochrome',
  'SupportsHighDynamicRange',
  'SupportsNormalDynamicRange',
  'SupportsSceneReferred',
  'SupportsOutputReferred',
  'CameraModelRestriction',
  'RequiresRGBTables',
  // Mode flags, labels and provenance metadata rather than settings with
  // a visible effect we're missing — either purely informational, or
  // (WhiteBalance) a mode name whose actual numeric effect is the
  // Temperature/Tint attributes we already read directly.
  'WhiteBalance',
  'ToneCurveName2012',
  'CompatibleVersion',
  'ShowInQuickActions',
  'ShowInPresets',
  'AllowFilters',
  'AsShotTemperature',
  'AsShotTint',
  'HDREditMode',
  'Copyright',
  'ContactInfo',
};

double _exposureToStops(double ourValue) =>
    ourValue / 100.0 * _exposureStopsAtMax;
double _stopsToExposure(double stops) => stops / _exposureStopsAtMax * 100.0;

String _presetIdFromName(String name) =>
    'preset_${DateTime.now().microsecondsSinceEpoch}_${name.hashCode}';

/// The Camera Raw version string written into exported presets. Lightroom
/// and Camera Raw treat a preset tagged with a plausibly-recent version as
/// a first-class develop preset; an implausibly old one (the "1.0" this
/// used to write) can make newer versions flag it as possibly-incompatible
/// on import. Bump this to track a real ACR release now and then.
const _crsVersion = '16.5';

/// A `crs:UUID` derived deterministically from the preset's own id, so
/// exporting the same preset twice yields the same UUID and Lightroom
/// recognises the re-import as the *same* preset (updating it in place)
/// rather than making a duplicate. FNV-1a over the seed, expanded to the
/// 32 uppercase hex digits Lightroom writes.
String _deterministicUuid(String seed) {
  final bytes = <int>[];
  var hash = 0x811c9dc5;
  for (var round = 0; round < 16; round++) {
    for (final unit in '$seed:$round'.codeUnits) {
      hash = (hash ^ unit) & 0xffffffff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    bytes.add(hash & 0xff);
    bytes.add((hash >> 8) & 0xff);
  }
  return bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase()
      .substring(0, 32);
}

/// Builds a Lightroom-compatible `.xmp` Develop Preset document for
/// [preset].
String xmpFromPreset(Preset preset) {
  final hasCurve =
      !isIdentityToneCurve(preset.curves.tone) ||
      !isIdentityToneCurve(preset.curves.red) ||
      !isIdentityToneCurve(preset.curves.green) ||
      !isIdentityToneCurve(preset.curves.blue);
  final builder = XmlBuilder();
  builder.element(
    'x:xmpmeta',
    namespaces: {'adobe:ns:meta/': 'x'},
    attributes: {'x:xmptk': 'darkmoon'},
    nest: () {
      builder.element(
        'rdf:RDF',
        namespaces: {_rdfNamespace: 'rdf'},
        nest: () {
          builder.element(
            'rdf:Description',
            // Only slider keys actually present in [preset.values] get
            // written — a preset re-exported after being imported partial
            // (e.g. a "Punchy" preset that never touched Temperature)
            // must stay partial, or writing a 0 fallback for an untouched
            // slider whose real neutral isn't 0 (Temperature's is 5500)
            // would bake in the same corruption `presetFromXmp` guards
            // against on the way back in.
            attributes: {
              'rdf:about': '',
              'crs:PresetType': 'Normal',
              'crs:Cluster': '',
              'crs:UUID': _deterministicUuid(preset.id),
              // The "this preset supports ..." capability flags newer
              // Lightroom / Camera Raw expect on a develop preset. Without
              // them the preset still imports but can show a
              // "may not be compatible" caution; with them it's treated
              // as a normal, fully-supported preset. `SupportsAmount` is
              // False — darkmoon has no preset-strength (Amount) slider.
              'crs:SupportsAmount': 'False',
              'crs:SupportsColor': 'True',
              'crs:SupportsMonochrome': 'True',
              'crs:SupportsHighDynamicRange': 'True',
              'crs:SupportsNormalDynamicRange': 'True',
              'crs:SupportsSceneReferred': 'True',
              'crs:SupportsOutputReferred': 'True',
              'crs:CameraModelRestriction': '',
              'crs:Copyright': '',
              'crs:ContactInfo': '',
              'crs:Version': _crsVersion,
              'crs:ProcessVersion': '11.0',
              if (hasCurve) 'crs:ToneCurveName2012': 'Custom',
              'crs:HasSettings': 'True',
              for (final (ourKey, crsAttr) in _directMappings)
                if (preset.values[ourKey] case final v?)
                  'crs:$crsAttr': v.toString(),
              if (preset.values['Exposure'] case final v?)
                'crs:Exposure2012': _exposureToStops(v).toStringAsFixed(2),
              for (final channel in _mixerChannels) ...{
                if (preset.values['Mixer${channel}Hue'] case final v?)
                  'crs:HueAdjustment$channel': v.toString(),
                if (preset.values['Mixer${channel}Saturation'] case final v?)
                  'crs:SaturationAdjustment$channel': v.toString(),
                if (preset.values['Mixer${channel}Luminance'] case final v?)
                  'crs:LuminanceAdjustment$channel': v.toString(),
              },
              for (final (ourRange, crsRange) in _gradeRanges) ...{
                if (preset.values['Grade${ourRange}Hue'] case final v?)
                  'crs:ColorGrade${crsRange}Hue': v.toString(),
                if (preset.values['Grade${ourRange}Saturation'] case final v?)
                  'crs:ColorGrade${crsRange}Sat': v.toString(),
                if (preset.values['Grade${ourRange}Luminance'] case final v?)
                  'crs:ColorGrade${crsRange}Lum': v.toString(),
              },
            },
            namespaces: {_crsNamespace: 'crs'},
            nest: () {
              _writeLangAlt(builder, 'crs:Name', preset.name);
              // Files every darkmoon preset under one named group in the
              // Lightroom preset browser instead of scattering them loose
              // in "User Presets".
              _writeLangAlt(builder, 'crs:Group', 'darkmoon');
              _writeCurve(builder, 'crs:ToneCurvePV2012', preset.curves.tone);
              _writeCurve(builder, 'crs:ToneCurvePV2012Red', preset.curves.red);
              _writeCurve(
                builder,
                'crs:ToneCurvePV2012Green',
                preset.curves.green,
              );
              _writeCurve(
                builder,
                'crs:ToneCurvePV2012Blue',
                preset.curves.blue,
              );
            },
          );
        },
      );
    },
  );
  final body = builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  // The XMP packet wrapper Adobe writes around every `.xmp` it exports.
  // Lightroom reads presets with or without it, but Camera Raw and a
  // number of third-party tools (Capture One, RawTherapee, ON1) expect a
  // well-formed packet, so wrapping it is the safer default for "import
  // anywhere".
  return '<?xpacket begin="\u{feff}" id="W5M0MpCehiHzreSzNTczkc9d"?>\n'
      '$body\n'
      '<?xpacket end="w"?>';
}

/// Writes a `<tag><rdf:Alt><rdf:li xml:lang="x-default">value</rdf:li>` —
/// the language-alternative structure Lightroom uses for a preset's Name
/// and Group.
void _writeLangAlt(XmlBuilder builder, String tag, String value) {
  builder.element(
    tag,
    nest: () {
      builder.element(
        'rdf:Alt',
        nest: () {
          builder.element(
            'rdf:li',
            attributes: {'xml:lang': 'x-default'},
            nest: value,
          );
        },
      );
    },
  );
}

void _writeCurve(XmlBuilder builder, String tag, List<CurvePoint> points) {
  if (isIdentityToneCurve(points)) {
    return;
  }
  builder.element(
    tag,
    nest: () {
      builder.element(
        'rdf:Seq',
        nest: () {
          for (final point in points) {
            final x = (point.x * 255).round().clamp(0, 255);
            final y = (point.y * 255).round().clamp(0, 255);
            builder.element('rdf:li', nest: '$x, $y');
          }
        },
      );
    },
  );
}

/// Parses a Lightroom `.xmp` Develop Preset. [fallbackName] is used when
/// the file has no `crs:Name`. Returns null if [xmlSource] isn't a
/// recognizable Camera Raw settings document.
Preset? presetFromXmp(String xmlSource, {required String fallbackName}) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xmlSource);
  } catch (_) {
    return null;
  }
  final description = document
      .findAllElements('Description', namespace: _rdfNamespace)
      .firstOrNull;
  if (description == null) {
    return null;
  }

  // Only present attributes make it into [values] — a real preset only
  // ever carries the boxes that were checked when it was made (e.g. a
  // "Punchy" preset touching just Contrast/Clarity has no Temperature
  // attribute at all). Filling absent ones in with a numeric fallback
  // instead of omitting them was a real bug: several of our sliders have
  // a *non-zero* neutral default (Temperature's is 5500, not 0), so a
  // fallback of 0 silently overwrote it with a wildly wrong value —
  // e.g. crushing white balance to 0K — the moment `_applyPreset` merged
  // `values` over `_defaultParamValues()`. Omitting the key instead lets
  // that merge fall through to the real default, exactly like Lightroom
  // leaves untouched settings alone.
  double? attr(String name) {
    final raw = description.attributes
        .where((a) => a.name.local == name)
        .map((a) => a.value)
        .firstOrNull;
    return raw == null ? null : double.tryParse(raw);
  }

  final values = <String, double>{
    for (final (ourKey, crsAttr) in _directMappings)
      if (attr(crsAttr) case final v?) ourKey: v,
    if (attr('Exposure2012') case final v?) 'Exposure': _stopsToExposure(v),
    for (final channel in _mixerChannels) ...{
      if (attr('HueAdjustment$channel') case final v?) 'Mixer${channel}Hue': v,
      if (attr('SaturationAdjustment$channel') case final v?)
        'Mixer${channel}Saturation': v,
      if (attr('LuminanceAdjustment$channel') case final v?)
        'Mixer${channel}Luminance': v,
    },
    for (final (ourRange, crsRange) in _gradeRanges) ...{
      if (attr('ColorGrade${crsRange}Hue') case final v?)
        'Grade${ourRange}Hue': v,
      if (attr('ColorGrade${crsRange}Sat') case final v?)
        'Grade${ourRange}Saturation': v,
      if (attr('ColorGrade${crsRange}Lum') case final v?)
        'Grade${ourRange}Luminance': v,
    },
  };

  // Legacy Split Toning only kicks in where the modern Color Grading
  // wheel for that same zone wasn't already set above — a preset with
  // both is trusting the modern attributes, not the legacy ones they were
  // upgraded from.
  for (final (ourRange, hueAttr, satAttr) in _splitToningFallback) {
    final hue = attr(hueAttr);
    if (hue != null && !values.containsKey('Grade${ourRange}Hue')) {
      values['Grade${ourRange}Hue'] = hue;
    }
    final sat = attr(satAttr);
    if (sat != null && !values.containsKey('Grade${ourRange}Saturation')) {
      values['Grade${ourRange}Saturation'] = sat;
    }
  }

  final name =
      description
          .findAllElements('li', namespace: _rdfNamespace)
          .where((e) => e.parentElement?.parentElement?.name.local == 'Name')
          .map((e) => e.innerText.trim())
          .firstOrNull ??
      fallbackName;

  return Preset(
    id: _presetIdFromName(name),
    name: name,
    values: values,
    curves: PhotoCurves(
      tone: _readCurve(description, 'ToneCurvePV2012'),
      red: _readCurve(description, 'ToneCurvePV2012Red'),
      green: _readCurve(description, 'ToneCurvePV2012Green'),
      blue: _readCurve(description, 'ToneCurvePV2012Blue'),
    ),
    unsupportedAttributes: _unsupportedAttributes(description),
  );
}

/// Every `crs:` attribute present on [description] that this app has no
/// mapping for and isn't purely structural/metadata — e.g. sharpening,
/// lens corrections, crop, or camera profile settings from a real
/// Lightroom export. Surfaced to the user so they know a preset didn't
/// carry over 1:1.
List<String> _unsupportedAttributes(XmlElement description) {
  final supported = <String>{
    for (final (_, crsAttr) in _directMappings) crsAttr,
    'Exposure2012',
    for (final channel in _mixerChannels) ...{
      'HueAdjustment$channel',
      'SaturationAdjustment$channel',
      'LuminanceAdjustment$channel',
    },
    for (final (_, crsRange) in _gradeRanges) ...{
      'ColorGrade${crsRange}Hue',
      'ColorGrade${crsRange}Sat',
      'ColorGrade${crsRange}Lum',
    },
    for (final (_, hueAttr, satAttr) in _splitToningFallback) ...{
      hueAttr,
      satAttr,
    },
  };
  final unsupported = <String>[];
  for (final attribute in description.attributes) {
    if (attribute.name.namespaceUri != _crsNamespace) {
      continue;
    }
    final local = attribute.name.local;
    if (supported.contains(local) || _structuralCrsAttributes.contains(local)) {
      continue;
    }
    unsupported.add(local);
  }
  return unsupported;
}

List<CurvePoint> _readCurve(XmlElement description, String tag) {
  final curveElement = description
      .findElements(tag, namespace: _crsNamespace)
      .firstOrNull;
  if (curveElement == null) {
    return identityToneCurve;
  }
  final points = <CurvePoint>[];
  for (final li in curveElement.findAllElements(
    'li',
    namespace: _rdfNamespace,
  )) {
    final parts = li.innerText.split(',');
    if (parts.length != 2) {
      continue;
    }
    final x = double.tryParse(parts[0].trim());
    final y = double.tryParse(parts[1].trim());
    if (x == null || y == null) {
      continue;
    }
    points.add(
      CurvePoint((x / 255).clamp(0.0, 1.0), (y / 255).clamp(0.0, 1.0)),
    );
  }
  return points.length >= 2 ? points : identityToneCurve;
}
