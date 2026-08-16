import 'package:xml/xml.dart';

import '../render/tone_curve.dart';
import 'preset.dart';

/// Reads/writes Lightroom-compatible `.xmp` Develop Preset files —
/// specifically the `crs:` (Camera Raw Settings) attributes that have a
/// real equivalent in this app's own adjustment set. Attributes this app
/// doesn't support (sharpening, lens corrections, crop, camera profile,
/// point color, masks, ...) are simply left out on export and ignored on
/// import, rather than erroring.
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
  ('DenoiseLuminance', 'LuminanceSmoothing'),
  ('DenoiseLuminanceDetail', 'LuminanceNoiseReductionDetail'),
  ('DenoiseLuminanceContrast', 'LuminanceNoiseReductionContrast'),
  ('DenoiseColor', 'ColorNoiseReduction'),
  ('DenoiseColorDetail', 'ColorNoiseReductionDetail'),
  ('DenoiseColorSmoothness', 'ColorNoiseReductionSmoothness'),
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
];

/// Our Exposure is scaled to +-3 stops of actual brightness change (see
/// render.dart) over a -100..100 slider; Lightroom's Exposure2012 is
/// stops directly, -5..5. Converting through "stops" (rather than a
/// direct 1:1 on the raw slider number) is what makes a round trip
/// (export then re-import) land back on the same value, and is at least
/// a defensible mapping for a real Lightroom preset's Exposure2012 too.
const _exposureStopsAtMax = 5.0;

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
};

double _exposureToStops(double ourValue) =>
    ourValue / 100.0 * _exposureStopsAtMax;
double _stopsToExposure(double stops) => stops / _exposureStopsAtMax * 100.0;

String _presetIdFromName(String name) =>
    'preset_${DateTime.now().microsecondsSinceEpoch}_${name.hashCode}';

/// Builds a Lightroom-compatible `.xmp` Develop Preset document for
/// [preset].
String xmpFromPreset(Preset preset) {
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element(
    'x:xmpmeta',
    namespaces: {'adobe:ns:meta/': 'x'},
    attributes: {'x:xmptk': 'Darkmoon'},
    nest: () {
      builder.element(
        'rdf:RDF',
        namespaces: {_rdfNamespace: 'rdf'},
        nest: () {
          builder.element(
            'rdf:Description',
            attributes: {
              'rdf:about': '',
              'crs:PresetType': 'Normal',
              'crs:Version': '1.0',
              'crs:ProcessVersion': '11.0',
              'crs:HasSettings': 'True',
              for (final (ourKey, crsAttr) in _directMappings)
                'crs:$crsAttr': (preset.values[ourKey] ?? 0).toString(),
              'crs:Exposure2012': _exposureToStops(
                preset.values['Exposure'] ?? 0,
              ).toStringAsFixed(2),
              for (final channel in _mixerChannels) ...{
                'crs:HueAdjustment$channel':
                    (preset.values['Mixer${channel}Hue'] ?? 0).toString(),
                'crs:SaturationAdjustment$channel':
                    (preset.values['Mixer${channel}Saturation'] ?? 0)
                        .toString(),
                'crs:LuminanceAdjustment$channel':
                    (preset.values['Mixer${channel}Luminance'] ?? 0).toString(),
              },
              for (final (ourRange, crsRange) in _gradeRanges) ...{
                'crs:ColorGrade${crsRange}Hue':
                    (preset.values['Grade${ourRange}Hue'] ?? 0).toString(),
                'crs:ColorGrade${crsRange}Sat':
                    (preset.values['Grade${ourRange}Saturation'] ?? 0)
                        .toString(),
                'crs:ColorGrade${crsRange}Lum':
                    (preset.values['Grade${ourRange}Luminance'] ?? 0)
                        .toString(),
              },
            },
            namespaces: {_crsNamespace: 'crs'},
            nest: () {
              builder.element(
                'crs:Name',
                nest: () {
                  builder.element(
                    'rdf:Alt',
                    nest: () {
                      builder.element(
                        'rdf:li',
                        attributes: {'xml:lang': 'x-default'},
                        nest: preset.name,
                      );
                    },
                  );
                },
              );
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
  return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
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

  double attr(String name, [double fallback = 0]) {
    final raw = description.attributes
        .where((a) => a.name.local == name)
        .map((a) => a.value)
        .firstOrNull;
    return raw == null ? fallback : (double.tryParse(raw) ?? fallback);
  }

  final values = <String, double>{
    for (final (ourKey, crsAttr) in _directMappings) ourKey: attr(crsAttr),
    'Exposure': _stopsToExposure(attr('Exposure2012')),
    for (final channel in _mixerChannels) ...{
      'Mixer${channel}Hue': attr('HueAdjustment$channel'),
      'Mixer${channel}Saturation': attr('SaturationAdjustment$channel'),
      'Mixer${channel}Luminance': attr('LuminanceAdjustment$channel'),
    },
    for (final (ourRange, crsRange) in _gradeRanges) ...{
      'Grade${ourRange}Hue': attr('ColorGrade${crsRange}Hue'),
      'Grade${ourRange}Saturation': attr('ColorGrade${crsRange}Sat'),
      'Grade${ourRange}Luminance': attr('ColorGrade${crsRange}Lum'),
    },
  };

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
