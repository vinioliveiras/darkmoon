import 'package:darkmoon/presets/preset.dart';
import 'package:darkmoon/presets/preset_xmp.dart';
import 'package:darkmoon/render/tone_curve.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preset round-trips through XMP unchanged', () {
    final original = Preset(
      id: 'preset_1',
      name: 'My Preset',
      values: {
        'Temperature': 6500,
        'Tint': 12,
        'Exposure': 40,
        'Contrast': -20,
        'Highlights': -30,
        'Shadows': 25,
        'Whites': 10,
        'Blacks': -15,
        'Texture': 15,
        'Clarity': 20,
        'Dehaze': 5,
        'Vibrance': 30,
        'Saturation': -5,
        'MixerRedHue': 10,
        'MixerRedSaturation': -20,
        'MixerRedLuminance': 5,
        'GradeShadowsHue': 210,
        'GradeShadowsSaturation': 15,
        'GradeShadowsLuminance': -5,
      },
      curves: const PhotoCurves(
        tone: [CurvePoint(0, 0), CurvePoint(0.5, 0.6), CurvePoint(1, 1)],
        red: [CurvePoint(0, 0.1), CurvePoint(1, 0.9)],
      ),
    );

    final xml = xmpFromPreset(original);
    final decoded = presetFromXmp(xml, fallbackName: 'fallback');

    expect(decoded, isNotNull);
    expect(decoded!.name, 'My Preset');
    for (final entry in original.values.entries) {
      expect(
        decoded.values[entry.key],
        closeTo(entry.value, 0.5),
        reason: 'mismatch for ${entry.key}',
      );
    }
    expect(decoded.curves.tone.length, original.curves.tone.length);
    for (var i = 0; i < original.curves.tone.length; i++) {
      expect(
        decoded.curves.tone[i].x,
        closeTo(original.curves.tone[i].x, 0.01),
      );
      expect(
        decoded.curves.tone[i].y,
        closeTo(original.curves.tone[i].y, 0.01),
      );
    }
    expect(decoded.curves.red.length, original.curves.red.length);
  });

  test('export carries the structural attributes Meridian expects', () {
    const preset = Preset(
      id: 'preset_abc',
      name: 'Warm',
      values: {'Contrast': 10},
    );
    final xml = xmpFromPreset(preset);

    // XMP packet wrapper (Adobe writes this around every exported .xmp).
    expect(xml.trimLeft(), startsWith('<?xpacket begin='));
    expect(xml.trimRight(), endsWith('<?xpacket end="w"?>'));

    // Still valid XML and still round-trippable through our own reader.
    final decoded = presetFromXmp(xml, fallbackName: 'x');
    expect(decoded, isNotNull);
    expect(decoded!.values['Contrast'], 10);

    // Capability flags + identity so newer Meridian treats it as a
    // fully-supported develop preset rather than flagging it.
    for (final attr in const [
      'crs:PresetType="Normal"',
      'crs:HasSettings="True"',
      'crs:SupportsColor="True"',
      'crs:SupportsMonochrome="True"',
      'crs:SupportsHighDynamicRange="True"',
      'crs:UUID=',
      'crs:Version="16',
    ]) {
      expect(xml, contains(attr), reason: 'missing $attr');
    }
    expect(xml, contains('darkmoon')); // the crs:Group name
  });

  test('the exported UUID is stable across repeated exports of a preset', () {
    const preset = Preset(
      id: 'preset_stable',
      name: 'S',
      values: {'Clarity': 5},
    );
    final first = RegExp(
      r'crs:UUID="([0-9A-F]+)"',
    ).firstMatch(xmpFromPreset(preset))?.group(1);
    final second = RegExp(
      r'crs:UUID="([0-9A-F]+)"',
    ).firstMatch(xmpFromPreset(preset))?.group(1);
    expect(first, isNotNull);
    expect(first!.length, 32);
    expect(first, second);
  });

  test('identity curve is omitted from the XMP and re-read as identity', () {
    const preset = Preset(id: 'p', name: 'Neutral', values: {});
    final xml = xmpFromPreset(preset);
    final decoded = presetFromXmp(xml, fallbackName: 'fallback');
    expect(decoded, isNotNull);
    expect(isIdentityToneCurve(decoded!.curves.tone), isTrue);
  });

  test('non-XMP input is rejected rather than throwing', () {
    expect(presetFromXmp('not xml at all', fallbackName: 'x'), isNull);
    expect(presetFromXmp('<html></html>', fallbackName: 'x'), isNull);
  });

  test('attributes absent from a real (partial) Meridian preset are omitted, '
      'not defaulted to 0', () {
    // A real preset that only touches Contrast/Clarity — no Temperature,
    // no Exposure — mirroring how "Update to Preset" only writes the
    // boxes that were actually checked. Regression test for a bug where
    // every mapped attribute was force-included with a 0 fallback,
    // silently zeroing out sliders whose real neutral isn't 0 (like
    // Temperature's 5500) the moment the preset was applied.
    const xml = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about=""
        xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
        crs:PresetType="Normal"
        crs:Contrast2012="25"
        crs:Clarity2012="15">
      <crs:Name>
        <rdf:Alt>
          <rdf:li xml:lang="x-default">Punchy</rdf:li>
        </rdf:Alt>
      </crs:Name>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
''';
    final decoded = presetFromXmp(xml, fallbackName: 'fallback');
    expect(decoded, isNotNull);
    expect(decoded!.values['Contrast'], 25);
    expect(decoded.values['Clarity'], 15);
    expect(decoded.values.containsKey('Temperature'), isFalse);
    expect(decoded.values.containsKey('Exposure'), isFalse);
    expect(decoded.values.containsKey('Tint'), isFalse);
  });

  test('re-exporting a partial preset keeps untouched sliders untouched', () {
    const partial = Preset(id: 'p2', name: 'Partial', values: {'Contrast': 25});
    final xml = xmpFromPreset(partial);
    final decoded = presetFromXmp(xml, fallbackName: 'fallback');
    expect(decoded, isNotNull);
    expect(decoded!.values['Contrast'], 25);
    expect(decoded.values.containsKey('Temperature'), isFalse);
  });

  test(
    'high-impact Meridian attrs map onto sharpen, vignette and global grade',
    () {
      const xml = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about=""
        xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
        crs:PresetType="Normal"
        crs:Sharpness="40"
        crs:SharpenRadius="1.2"
        crs:SharpenDetail="25"
        crs:SharpenEdgeMasking="30"
        crs:PostCropVignetteAmount="-20"
        crs:PostCropVignetteMidpoint="40"
        crs:PostCropVignetteFeather="60"
        crs:ColorGradeGlobalHue="30"
        crs:ColorGradeGlobalSat="12"
        crs:ColorGradeGlobalLum="-5">
      <crs:Name>
        <rdf:Alt>
          <rdf:li xml:lang="x-default">Punch</rdf:li>
        </rdf:Alt>
      </crs:Name>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
''';
      final decoded = presetFromXmp(xml, fallbackName: 'fallback');
      expect(decoded, isNotNull);
      expect(decoded!.values['SharpenAmount'], 40);
      expect(decoded.values['SharpenRadius'], closeTo(1.2, 0.01));
      expect(decoded.values['SharpenDetail'], 25);
      expect(decoded.values['SharpenMasking'], 30);
      expect(decoded.values['VignetteAmount'], -20);
      expect(decoded.values['VignetteMidpoint'], 40);
      expect(decoded.values['VignetteFeather'], 60);
      expect(decoded.values['GradeGlobalHue'], 30);
      expect(decoded.values['GradeGlobalSaturation'], 12);
      expect(decoded.values['GradeGlobalLuminance'], -5);
      expect(decoded.unsupportedAttributes, isEmpty);
    },
  );

  test('legacy Split Toning falls back onto Shadows/Highlights grading', () {
    const xml = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about=""
        xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
        crs:PresetType="Normal"
        crs:SplitToningShadowHue="210"
        crs:SplitToningShadowSaturation="18"
        crs:SplitToningHighlightHue="40"
        crs:SplitToningHighlightSaturation="10">
      <crs:Name>
        <rdf:Alt>
          <rdf:li xml:lang="x-default">Split</rdf:li>
        </rdf:Alt>
      </crs:Name>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
''';
    final decoded = presetFromXmp(xml, fallbackName: 'fallback');
    expect(decoded, isNotNull);
    expect(decoded!.values['GradeShadowsHue'], 210);
    expect(decoded.values['GradeShadowsSaturation'], 18);
    expect(decoded.values['GradeHighlightsHue'], 40);
    expect(decoded.values['GradeHighlightsSaturation'], 10);
    expect(decoded.unsupportedAttributes, isEmpty);
  });

  test('modern ColorGrade wins over legacy Split Toning on the same zone', () {
    const xml = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about=""
        xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
        crs:PresetType="Normal"
        crs:ColorGradeShadowHue="90"
        crs:ColorGradeShadowSat="8"
        crs:SplitToningShadowHue="210"
        crs:SplitToningShadowSaturation="18">
      <crs:Name>
        <rdf:Alt>
          <rdf:li xml:lang="x-default">Both</rdf:li>
        </rdf:Alt>
      </crs:Name>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
''';
    final decoded = presetFromXmp(xml, fallbackName: 'fallback');
    expect(decoded, isNotNull);
    expect(decoded!.values['GradeShadowsHue'], 90);
    expect(decoded.values['GradeShadowsSaturation'], 8);
  });
}
