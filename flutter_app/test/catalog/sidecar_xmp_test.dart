import 'dart:convert';
import 'dart:io';

import 'package:darkmoon/catalog/mask_store.dart';
import 'package:darkmoon/catalog/sidecar_xmp.dart';
import 'package:darkmoon/render/mask.dart';
import 'package:darkmoon/render/tone_curve.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _radial = MaskLayer(
  id: 'm1',
  name: 'Sky',
  type: MaskType.radialGradient,
  radial: RadialGradientGeometry(
    centerX: 0.4,
    centerY: 0.3,
    radius: 0.25,
    radiusY: 0.15,
    angle: 0.3,
    feather: 0.6,
  ),
  inverted: true,
  opacity: 80,
  values: {'Exposure': -0.7, 'Clarity': 12},
);

final _brush = MaskLayer(
  id: 'm2',
  name: 'Face',
  type: MaskType.brush,
  brush: const BrushGeometry(
    strokes: [
      BrushStroke(
        radius: 0.05,
        hardness: 0.5,
        erase: false,
        flow: 60,
        points: [BrushPoint(0.1, 0.2), BrushPoint(0.15, 0.25)],
      ),
    ],
  ),
  values: const {'Shadows': 30},
  curves: const PhotoCurves(
    tone: [CurvePoint(0, 0), CurvePoint(0.4, 0.5), CurvePoint(1, 1)],
  ),
);

final _full = PhotoSidecar(
  values: const {
    'Temperature': 6200,
    'Tint': -4,
    'Exposure': 0.35,
    'Contrast': 12,
    'Clarity': 18,
    // No crs: equivalent — only the darkmoon: layer can carry these.
    'ColorProfileMode': 1,
    'AiDenoise': 55,
    'WhiteBalanceMode': 2,
  },
  curves: const PhotoCurves(
    tone: [CurvePoint(0, 0.02), CurvePoint(0.5, 0.58), CurvePoint(1, 1)],
    blue: [CurvePoint(0, 0), CurvePoint(1, 0.9)],
  ),
  masks: [_radial, _brush],
  presetId: 'preset_123',
  rating: 4,
  label: 'Red',
  tags: ['travel', 'family'],
);

void _expectCurve(List<CurvePoint> actual, List<CurvePoint> expected) {
  expect(actual.length, expected.length);
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i].x, closeTo(expected[i].x, 1e-9));
    expect(actual[i].y, closeTo(expected[i].y, 1e-9));
  }
}

void main() {
  test('a sidecar file sits next to the photo with a .xmp extension', () {
    expect(
      sidecarFileFor(p.join('D:', 'photos', 'DSCF0345.RAF')).path,
      p.join('D:', 'photos', 'DSCF0345.xmp'),
    );
    expect(
      sidecarFileFor(p.join('shoot', 'IMG_0001.jpg')).path,
      p.join('shoot', 'IMG_0001.xmp'),
    );
  });

  test('everything round-trips through the darkmoon layer losslessly', () {
    final decoded = sidecarFromXmp(xmpFromSidecar(_full));
    expect(decoded, isNotNull);
    expect(decoded!.values, _full.values);
    _expectCurve(decoded.curves.tone, _full.curves.tone);
    _expectCurve(decoded.curves.blue, _full.curves.blue);
    expect(decoded.curves.red, identityToneCurve);
    expect(decoded.masks.length, 2);
    for (var i = 0; i < 2; i++) {
      expect(
        jsonEncode(encodeMaskLayer(decoded.masks[i])),
        jsonEncode(encodeMaskLayer(_full.masks[i])),
      );
    }
    expect(decoded.presetId, 'preset_123');
    expect(decoded.rating, 4);
    expect(decoded.label, 'Red');
    expect(decoded.tags, ['travel', 'family']);
  });

  test('the crs layer carries the sliders another editor can read', () {
    final xml = xmpFromSidecar(_full);
    expect(xml, contains('crs:Temperature="6200.0"'));
    expect(xml, contains('crs:Clarity2012="18.0"'));
    expect(xml, contains('crs:Exposure2012="0.35"'));
    expect(xml, contains('crs:ToneCurvePV2012'));
    expect(xml, contains('xmp:Rating="4"'));
    expect(xml, contains('<rdf:li>travel</rdf:li>'));
    // Nothing of ours leaks into the crs: namespace.
    expect(xml, isNot(contains('crs:ColorProfileMode')));
  });

  test('a sidecar written by another editor gives its sliders and '
      'metadata', () {
    const foreign = '''
<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0-c000">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
    xmp:Rating="3"
    xmp:Label="Blue"
    crs:Version="16.0"
    crs:Temperature="5400"
    crs:Tint="+8"
    crs:Exposure2012="+0.50"
    crs:Contrast2012="+15"
    crs:Highlights2012="-40"
    crs:Clarity2012="+10"
    crs:LensProfileEnable="1">
   <dc:subject>
    <rdf:Bag>
     <rdf:li>landscape</rdf:li>
     <rdf:li>sunset</rdf:li>
    </rdf:Bag>
   </dc:subject>
   <crs:ToneCurvePV2012>
    <rdf:Seq>
     <rdf:li>0, 0</rdf:li>
     <rdf:li>128, 140</rdf:li>
     <rdf:li>255, 255</rdf:li>
    </rdf:Seq>
   </crs:ToneCurvePV2012>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>''';
    final decoded = sidecarFromXmp(foreign);
    expect(decoded, isNotNull);
    expect(decoded!.values['Temperature'], 5400);
    expect(decoded.values['Tint'], 8);
    expect(decoded.values['Exposure'], closeTo(0.5, 1e-9));
    expect(decoded.values['Contrast'], 15);
    expect(decoded.values['Highlights'], -40);
    expect(decoded.values['Clarity'], 10);
    expect(decoded.values.containsKey('LensProfileEnable'), isFalse);
    expect(decoded.curves.tone.length, 3);
    expect(decoded.curves.tone[1].y, closeTo(140 / 255, 1e-6));
    expect(decoded.rating, 3);
    expect(decoded.label, 'Blue');
    expect(decoded.tags, ['landscape', 'sunset']);
    expect(decoded.presetId, isNull);
    expect(decoded.masks, isEmpty);
  });

  test('metadata as child elements is read too', () {
    const elements = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
   <xmp:Rating>5</xmp:Rating>
   <xmp:Label>Green</xmp:Label>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>''';
    final decoded = sidecarFromXmp(elements)!;
    expect(decoded.rating, 5);
    expect(decoded.label, 'Green');
    expect(decoded.hasEdits, isFalse);
  });

  test('not XMP at all is null, not a crash', () {
    expect(sidecarFromXmp('not xml'), isNull);
    expect(sidecarFromXmp('<root/>'), isNull);
  });

  group('on disk', () {
    late Directory dir;
    late String photo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('darkmoon_sidecar_');
      photo = p.join(dir.path, 'DSCF0001.RAF');
      await File(photo).writeAsBytes([0]);
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('writes, reads back, and keeps foreign metadata on rewrite', () async {
      // Another editor rated the photo before this app ever saw it.
      await sidecarFileFor(photo).writeAsString(
        xmpFromSidecar(
          const PhotoSidecar(rating: 2, label: 'Yellow', tags: ['keep']),
        ),
      );
      await writeSidecar(photo, const PhotoSidecar(values: {'Exposure': 1.0}));
      final read = await readSidecar(photo);
      expect(read, isNotNull);
      expect(read!.values, {'Exposure': 1.0});
      expect(read.rating, 2);
      expect(read.label, 'Yellow');
      expect(read.tags, ['keep']);
    });

    test('a sidecar with nothing left to say is removed', () async {
      await writeSidecar(photo, const PhotoSidecar(values: {'Contrast': 5}));
      expect(await sidecarFileFor(photo).exists(), isTrue);
      await writeSidecar(photo, const PhotoSidecar());
      expect(await sidecarFileFor(photo).exists(), isFalse);
      expect(await readSidecar(photo), isNull);
    });

    test('a photo with no sidecar reads as null', () async {
      expect(await readSidecar(photo), isNull);
    });
  });
}
