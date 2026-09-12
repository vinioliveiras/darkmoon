import 'package:darkmoon/presets/preset.dart';
import 'package:darkmoon/presets/preset_masks.dart';
import 'package:darkmoon/presets/preset_xmp.dart';
import 'package:darkmoon/render/mask.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Meridian preset with one correction per mask kind, in the layout
/// Camera Raw writes: attributes on the `rdf:li`, nested Seqs for the
/// components and the paint dabs.
const _meridianPreset = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
    crs:PresetType="Normal" crs:Contrast2012="10" crs:HasSettings="True">
   <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">Masked Look</rdf:li></rdf:Alt></crs:Name>
   <crs:MaskGroupBasedCorrections>
    <rdf:Seq>
     <rdf:li crs:What="Correction" crs:CorrectionAmount="1.000000" crs:CorrectionActive="true"
       crs:LocalExposure2012="-0.500000" crs:LocalContrast2012="0.200000" crs:LocalSaturation="-0.300000"
       crs:LocalSharpness="0.250000" crs:CorrectionName="Sky darken">
      <crs:CorrectionMasks>
       <rdf:Seq>
        <rdf:li crs:What="Mask/Gradient" crs:MaskActive="true" crs:MaskName="Linear Gradient 1"
          crs:MaskBlendMode="0" crs:MaskInverted="false" crs:MaskValue="1.000000"
          crs:ZeroX="0.500000" crs:ZeroY="0.600000" crs:FullX="0.500000" crs:FullY="0.100000"/>
       </rdf:Seq>
      </crs:CorrectionMasks>
     </rdf:li>
     <rdf:li crs:What="Correction" crs:CorrectionAmount="0.500000" crs:CorrectionActive="true"
       crs:LocalShadows2012="0.400000" crs:CorrectionName="Face">
      <crs:CorrectionMasks>
       <rdf:Seq>
        <rdf:li crs:What="Mask/CircularGradient" crs:MaskActive="true" crs:MaskBlendMode="0"
          crs:MaskInverted="false" crs:MaskValue="1.000000" crs:Top="0.200000" crs:Left="0.300000"
          crs:Bottom="0.600000" crs:Right="0.500000" crs:Angle="0.000000" crs:Midpoint="50"
          crs:Feather="40" crs:Flipped="true" crs:Version="2"/>
       </rdf:Seq>
      </crs:CorrectionMasks>
     </rdf:li>
     <rdf:li crs:What="Correction" crs:CorrectionAmount="1.000000" crs:CorrectionActive="true"
       crs:LocalClarity2012="0.300000" crs:CorrectionName="Painted">
      <crs:CorrectionMasks>
       <rdf:Seq>
        <rdf:li crs:What="Mask/Paint" crs:MaskActive="true" crs:MaskBlendMode="0" crs:MaskValue="1"
          crs:Radius="0.040000" crs:Flow="1.000000" crs:Feather="0.250000">
         <crs:Dabs><rdf:Seq><rdf:li>d 0.100000 0.200000</rdf:li><rdf:li>d 0.150000 0.250000</rdf:li></rdf:Seq></crs:Dabs>
        </rdf:li>
        <rdf:li crs:What="Mask/Paint" crs:MaskActive="true" crs:MaskBlendMode="1" crs:MaskValue="1"
          crs:Radius="0.020000" crs:Flow="1.000000" crs:Feather="0.500000">
         <crs:Dabs><rdf:Seq><rdf:li>d 0.120000 0.220000</rdf:li></rdf:Seq></crs:Dabs>
        </rdf:li>
       </rdf:Seq>
      </crs:CorrectionMasks>
     </rdf:li>
     <rdf:li crs:What="Correction" crs:CorrectionAmount="1.000000" crs:CorrectionActive="true"
       crs:LocalTexture="0.150000" crs:CorrectionName="Subject">
      <crs:CorrectionMasks>
       <rdf:Seq>
        <rdf:li crs:What="Mask/Image" crs:MaskActive="true" crs:MaskBlendMode="0" crs:MaskValue="1"
          crs:MaskSubType="3"/>
        <rdf:li crs:What="Mask/Range" crs:MaskActive="true" crs:MaskBlendMode="0" crs:MaskValue="1"
          crs:MaskSubType="1" crs:LuminanceRangeMin="0.200000" crs:LuminanceRangeMax="0.600000"
          crs:LuminanceFeather="0.300000"/>
        <rdf:li crs:What="Mask/Range" crs:MaskActive="true" crs:MaskBlendMode="0" crs:MaskValue="1"
          crs:MaskSubType="2"/>
       </rdf:Seq>
      </crs:CorrectionMasks>
     </rdf:li>
    </rdf:Seq>
   </crs:MaskGroupBasedCorrections>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
''';

void main() {
  late Preset preset;
  late List<MaskLayer> layers;

  setUpAll(() {
    preset = presetFromXmp(_meridianPreset, fallbackName: 'x')!;
    var n = 0;
    layers = maskLayersForImage(
      preset.meridianMasks,
      aspect: 1.5,
      newId: () => 'm${n++}',
    );
  });

  test('the corrections are parsed with their local values', () {
    expect(preset.name, 'Masked Look');
    expect(preset.values['Contrast'], 10);
    expect(preset.meridianMasks.length, 4);
    expect(preset.hasMasks, isTrue);
    final sky = preset.meridianMasks.first;
    expect(sky.name, 'Sky darken');
    expect(sky.local['LocalExposure2012'], -0.5);
    expect(localValuesOf(sky), {
      'Exposure': -0.5,
      'Contrast': closeTo(20, 1e-9),
      'Saturation': closeTo(-30, 1e-9),
    });
    expect(preset.unsupportedAttributes, contains('LocalSharpness'));
    expect(preset.unsupportedAttributes, contains('Mask/Range'));
  });

  test('a gradient keeps its full and zero points', () {
    final g = layers.firstWhere((l) => l.type == MaskType.linearGradient);
    expect(g.name, 'Sky darken');
    expect(g.linear.startX, 0.5);
    expect(g.linear.startY, 0.1);
    expect(g.linear.endX, 0.5);
    expect(g.linear.endY, 0.6);
    expect(g.values['Exposure'], -0.5);
    expect(g.opacity, 100);
    expect(g.id, 'm0');
  });

  test('a radial converts its bounds for the photo aspect', () {
    final r = layers.firstWhere((l) => l.type == MaskType.radialGradient);
    expect(r.radial.centerX, closeTo(0.4, 1e-9));
    expect(r.radial.centerY, closeTo(0.4, 1e-9));
    expect(r.radial.radius, closeTo(0.1, 1e-9));
    // Half-height 0.2 of the frame's height is 0.2 / 1.5 of its width.
    expect(r.radial.radiusY, closeTo(0.2 / 1.5, 1e-9));
    expect(r.radial.feather, closeTo(0.4, 1e-9));
    expect(r.inverted, isFalse); // Flipped: inside affected, like ours
    expect(r.opacity, 50);
    expect(r.values['Shadows'], closeTo(40, 1e-9));
  });

  test('a subtracting brush becomes erase strokes on the group brush', () {
    final b = layers.firstWhere((l) => l.type == MaskType.brush);
    expect(b.brush.strokes.length, 2);
    final paint = b.brush.strokes[0];
    expect(paint.erase, isFalse);
    expect(paint.points.length, 2);
    expect(paint.points[1].x, closeTo(0.15, 1e-9));
    expect(paint.radius, closeTo(0.04, 1e-9));
    expect(paint.hardness, closeTo(0.75, 1e-9));
    expect(b.brush.strokes[1].erase, isTrue);
    expect(b.values['Clarity'], closeTo(30, 1e-9));
  });

  test('image and luminance masks map to ours, colour ranges are dropped', () {
    final subjectLayers = layers.where((l) => l.name.startsWith('Subject'));
    expect(subjectLayers.length, 2);
    final bg = subjectLayers.first;
    expect(bg.type, MaskType.subject);
    expect(bg.inverted, isTrue); // Background = not the subject
    final lum = subjectLayers.last;
    expect(lum.type, MaskType.luminance);
    expect(lum.luminance.targetLuma, closeTo(0.4 * 255, 1e-6));
    expect(lum.luminance.tolerance, closeTo(0.2 * 255, 1e-6));
    expect(lum.luminance.feather, closeTo(30, 1e-6));
    expect(layers.length, 5);
  });

  test('our own masks round-trip through the preset XMP', () {
    const mask = MaskLayer(
      id: 'orig',
      name: 'Warm corner',
      type: MaskType.radialGradient,
      radial: RadialGradientGeometry(
        centerX: 0.3,
        centerY: 0.7,
        radius: 0.2,
        radiusY: 0.1,
        angle: 0.5,
        feather: 0.6,
      ),
      values: {'Exposure': 0.3, 'Saturation': 20},
    );
    final written = xmpFromPreset(
      const Preset(
        id: 'p',
        name: 'With mask',
        values: {'Contrast': 5},
        masks: [mask],
      ),
    );
    final back = presetFromXmp(written, fallbackName: 'x')!;
    expect(back.masks.length, 1);
    final m = back.masks.single;
    expect(m.name, 'Warm corner');
    expect(m.type, MaskType.radialGradient);
    expect(m.radial.centerX, 0.3);
    expect(m.radial.radiusY, 0.1);
    expect(m.radial.angle, 0.5);
    expect(m.values['Saturation'], 20);
    expect(back.meridianMasks, isEmpty);
  });
}
