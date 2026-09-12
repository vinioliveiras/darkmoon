// Masks in `.xmp` presets (2026-09-12).
//
// Two sources. darkmoon's own presets carry the mask stack verbatim as
// `darkmoon:Masks` (the same JSON the sidecar writes), read straight
// back. Meridian presets carry `crs:MaskGroupBasedCorrections`: a list
// of corrections, each with its local slider values and the mask
// components that select where they apply. Those are parsed into
// [MeridianCorrection]s here and turned into [MaskLayer]s only when the
// preset is applied to a photo — a radial mask is stored as normalised
// bounds, and our ellipse keeps both radii in width units, so the
// photo's aspect ratio is needed for the conversion.
//
// What carries over: linear and radial gradients, brush strokes (with a
// subtracting brush of the same group as erase strokes on it), Subject,
// Sky and Background image masks, luminance ranges, and the local
// Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Clarity,
// Dehaze, Texture and Saturation. What does not, and is listed in the
// preset's unsupported attributes: colour ranges, intersect blends, a
// subtracting component that is not a brush, local white balance,
// sharpness, noise and defringe.

import 'package:xml/xml.dart';

import '../render/mask.dart';
import 'preset_xmp.dart' show crsNamespace, rdfNamespace;

/// One entry of `crs:CorrectionMasks`.
class MeridianMaskComponent {
  const MeridianMaskComponent({
    required this.what,
    required this.attrs,
    this.dabs = const [],
  });

  /// `Mask/Gradient`, `Mask/CircularGradient`, `Mask/Paint`,
  /// `Mask/Image`, `Mask/Range`, …
  final String what;

  /// Every `crs:` attribute on the component, by local name.
  final Map<String, String> attrs;

  /// `crs:Dabs` of a paint mask: normalised (x, y) pairs.
  final List<List<double>> dabs;

  double? num(String name) {
    final raw = attrs[name];
    return raw == null ? null : double.tryParse(raw);
  }

  bool get active => attrs['MaskActive']?.toLowerCase() != 'false';

  /// 0 add, 1 subtract, 2 intersect.
  int get blendMode => num('MaskBlendMode')?.round() ?? 0;

  bool get inverted => attrs['MaskInverted']?.toLowerCase() == 'true';

  String? get name => attrs['MaskName'];
}

/// One entry of `crs:MaskGroupBasedCorrections`.
class MeridianCorrection {
  const MeridianCorrection({
    required this.name,
    required this.active,
    required this.amount,
    required this.local,
    required this.components,
  });

  final String name;
  final bool active;

  /// `crs:CorrectionAmount`, 0..1.
  final double amount;

  /// `crs:Local*` attributes by local name, as numbers.
  final Map<String, double> local;
  final List<MeridianMaskComponent> components;
}

/// The attributes of an `rdf:li`, whether Meridian put them on the `li`
/// itself or on an `rdf:Description` inside it.
Map<String, String> _liAttrs(XmlElement li) {
  final out = <String, String>{
    for (final a in li.attributes)
      if (a.name.namespaceUri == crsNamespace || a.name.prefix == 'crs')
        a.name.local: a.value,
  };
  final inner = li.findElements('Description', namespace: rdfNamespace);
  for (final d in inner) {
    for (final a in d.attributes) {
      if (a.name.namespaceUri == crsNamespace || a.name.prefix == 'crs') {
        out[a.name.local] = a.value;
      }
    }
  }
  return out;
}

Iterable<XmlElement> _seqItems(XmlElement parent, String tag) sync* {
  for (final holder in parent.findElements(tag, namespace: crsNamespace)) {
    for (final seq in holder.findElements('Seq', namespace: rdfNamespace)) {
      yield* seq.findElements('li', namespace: rdfNamespace);
    }
  }
}

/// Where a correction's nested elements live: on the `li` or on the
/// `rdf:Description` it wraps.
XmlElement _body(XmlElement li) =>
    li.findElements('Description', namespace: rdfNamespace).firstOrNull ?? li;

/// The Meridian corrections of [description] (the `rdf:Description`
/// holding the `crs:` settings); empty when it has none.
List<MeridianCorrection> parseMeridianCorrections(XmlElement description) {
  final out = <MeridianCorrection>[];
  for (final li in _seqItems(description, 'MaskGroupBasedCorrections')) {
    final attrs = _liAttrs(li);
    if (attrs['What'] != 'Correction') continue;
    final local = <String, double>{
      for (final e in attrs.entries)
        if (e.key.startsWith('Local'))
          if (double.tryParse(e.value) case final v?) e.key: v,
    };
    final components = <MeridianMaskComponent>[];
    for (final maskLi in _seqItems(_body(li), 'CorrectionMasks')) {
      final maskAttrs = _liAttrs(maskLi);
      final what = maskAttrs['What'];
      if (what == null) continue;
      final dabs = <List<double>>[];
      for (final dabLi in _seqItems(_body(maskLi), 'Dabs')) {
        final parts = dabLi.innerText.trim().split(RegExp(r'\s+'));
        if (parts.length >= 3 && parts[0] == 'd') {
          final x = double.tryParse(parts[1]);
          final y = double.tryParse(parts[2]);
          if (x != null && y != null) dabs.add([x, y]);
        }
      }
      components.add(
        MeridianMaskComponent(what: what, attrs: maskAttrs, dabs: dabs),
      );
    }
    out.add(
      MeridianCorrection(
        name: attrs['CorrectionName'] ?? 'Mask ${out.length + 1}',
        active: attrs['CorrectionActive']?.toLowerCase() != 'false',
        amount: double.tryParse(attrs['CorrectionAmount'] ?? '') ?? 1.0,
        local: local,
        components: components,
      ),
    );
  }
  return out;
}

/// (`crs:Local*` name, our slider key, factor). Meridian stores the ±100
/// sliders as -1..1 and exposure in stops, which is our Exposure unit.
const _localMappings = [
  ('LocalExposure2012', 'Exposure', 1.0),
  ('LocalContrast2012', 'Contrast', 100.0),
  ('LocalHighlights2012', 'Highlights', 100.0),
  ('LocalShadows2012', 'Shadows', 100.0),
  ('LocalWhites2012', 'Whites', 100.0),
  ('LocalBlacks2012', 'Blacks', 100.0),
  ('LocalClarity2012', 'Clarity', 100.0),
  ('LocalDehaze', 'Dehaze', 100.0),
  ('LocalTexture', 'Texture', 100.0),
  ('LocalSaturation', 'Saturation', 100.0),
];

/// Our slider values for a correction's `Local*` settings.
Map<String, double> localValuesOf(MeridianCorrection correction) => {
  for (final (theirs, ours, factor) in _localMappings)
    if (correction.local[theirs] case final v? when v != 0) ours: v * factor,
};

/// The `Local*` names in [corrections] this app cannot carry over, plus
/// the mask components it drops — for the preset's unsupported list.
List<String> unsupportedMaskParts(List<MeridianCorrection> corrections) {
  final supported = {for (final (theirs, _, _) in _localMappings) theirs};
  final out = <String>{};
  for (final c in corrections) {
    for (final key in c.local.keys) {
      if (!supported.contains(key)) out.add(key);
    }
    for (final m in c.components) {
      final convertible = switch (m.what) {
        'Mask/Gradient' || 'Mask/CircularGradient' || 'Mask/Paint' => true,
        'Mask/Image' => _imageType(m) != null,
        'Mask/Range' => m.num('MaskSubType') == 1,
        _ => false,
      };
      if (!convertible) {
        out.add(m.what);
      } else if (m.blendMode == 2) {
        out.add('${m.what} (intersect)');
      } else if (m.blendMode == 1 && m.what != 'Mask/Paint') {
        out.add('${m.what} (subtract)');
      }
    }
  }
  return out.toList()..sort();
}

/// (type, inverted) for a `Mask/Image` component, null when unknown.
(MaskType, bool)? _imageType(MeridianMaskComponent m) =>
    switch (m.num('MaskSubType')?.round()) {
      1 => (MaskType.subject, false),
      2 => (MaskType.sky, false),
      3 => (MaskType.subject, true), // Background: everything but the subject
      _ => null,
    };

/// [corrections] as mask layers for a photo whose width / height is
/// [aspect]. Every additive component becomes one layer carrying the
/// correction's values (their union is close enough to Meridian's
/// summed coverage); a subtracting brush becomes erase strokes on the
/// group's brush layer; anything else that subtracts or intersects is
/// left out. [newId] mints one id per layer.
List<MaskLayer> maskLayersForImage(
  List<MeridianCorrection> corrections, {
  required double aspect,
  required String Function() newId,
}) {
  final layers = <MaskLayer>[];
  for (final c in corrections) {
    final values = localValuesOf(c);
    final opacity = (c.amount * 100).clamp(0.0, 100.0);
    MaskLayer? brushLayer;
    final eraseStrokes = <BrushStroke>[];
    var count = 0;
    for (final m in c.components) {
      if (m.blendMode == 2) continue;
      if (m.blendMode == 1) {
        if (m.what == 'Mask/Paint') {
          final stroke = _strokeOf(m, erase: true);
          if (stroke != null) eraseStrokes.add(stroke);
        }
        continue;
      }
      count++;
      final name = count == 1 ? c.name : '${c.name} $count';
      MaskLayer build({
        required MaskType type,
        LinearGradientGeometry? linear,
        RadialGradientGeometry? radial,
        BrushGeometry? brush,
        SubjectGeometry? subject,
        LuminanceGeometry? luminance,
        bool? inverted,
      }) => MaskLayer(
        id: newId(),
        name: name,
        type: type,
        enabled: c.active && m.active,
        inverted: inverted ?? m.inverted,
        opacity: opacity,
        values: values,
        linear: linear ?? const LinearGradientGeometry(),
        radial: radial ?? const RadialGradientGeometry(),
        brush: brush ?? const BrushGeometry(),
        subject: subject ?? const SubjectGeometry(),
        luminance: luminance ?? const LuminanceGeometry(),
      );
      MaskLayer? layer;
      switch (m.what) {
        case 'Mask/Gradient':
          final zx = m.num('ZeroX'), zy = m.num('ZeroY');
          final fx = m.num('FullX'), fy = m.num('FullY');
          if (zx == null || zy == null || fx == null || fy == null) break;
          layer = build(
            type: MaskType.linearGradient,
            linear: LinearGradientGeometry(
              startX: fx,
              startY: fy,
              endX: zx,
              endY: zy,
              feather: 100,
            ),
          );
        case 'Mask/CircularGradient':
          final top = m.num('Top'), left = m.num('Left');
          final bottom = m.num('Bottom'), right = m.num('Right');
          if (top == null || left == null || bottom == null || right == null) {
            break;
          }
          // Meridian's default radial (Flipped) affects the inside, like
          // ours; an un-flipped one affects the outside.
          final flipped = m.attrs['Flipped']?.toLowerCase() != 'false';
          layer = build(
            type: MaskType.radialGradient,
            inverted: m.inverted != !flipped,
            radial: RadialGradientGeometry(
              centerX: (left + right) / 2,
              centerY: (top + bottom) / 2,
              radius: (right - left) / 2,
              // Normalised height to width units.
              radiusY: (bottom - top) / 2 / aspect,
              angle: -(m.num('Angle') ?? 0) * 3.141592653589793 / 180,
              feather: ((m.num('Feather') ?? 50) / 100).clamp(0.0, 1.0),
            ),
          );
        case 'Mask/Paint':
          final stroke = _strokeOf(m, erase: false);
          if (stroke == null) break;
          layer = build(
            type: MaskType.brush,
            brush: BrushGeometry(strokes: [stroke]),
          );
          brushLayer ??= layer;
        case 'Mask/Image':
          final image = _imageType(m);
          if (image == null) break;
          layer = build(
            type: image.$1,
            inverted: m.inverted != image.$2,
            subject: const SubjectGeometry(
              startX: 0,
              startY: 0,
              endX: 1,
              endY: 1,
            ),
          );
        case 'Mask/Range':
          if (m.num('MaskSubType') != 1) break;
          final lo = (m.num('LuminanceRangeMin') ?? 0).clamp(0.0, 1.0);
          final hi = (m.num('LuminanceRangeMax') ?? 1).clamp(0.0, 1.0);
          layer = build(
            type: MaskType.luminance,
            // Our luminance geometry is on 0..255.
            luminance: LuminanceGeometry(
              targetLuma: (lo + hi) / 2 * 255,
              tolerance: (hi - lo) / 2 * 255,
              feather: ((m.num('LuminanceFeather') ?? 0.5) * 100).clamp(
                0.0,
                100.0,
              ),
            ),
          );
      }
      if (layer != null) layers.add(layer);
    }
    if (eraseStrokes.isNotEmpty && brushLayer != null) {
      final index = layers.indexOf(brushLayer);
      layers[index] = brushLayer.copyWith(
        brush: BrushGeometry(
          strokes: [...brushLayer.brush.strokes, ...eraseStrokes],
        ),
      );
    }
  }
  return layers;
}

BrushStroke? _strokeOf(MeridianMaskComponent m, {required bool erase}) {
  if (m.dabs.isEmpty) return null;
  return BrushStroke(
    points: [for (final d in m.dabs) BrushPoint(d[0], d[1])],
    // Meridian's brush Radius is a fraction of the image width, like ours.
    radius: (m.num('Radius') ?? 0.05).clamp(0.001, 1.0),
    hardness: (1 - (m.num('Feather') ?? 0.5)).clamp(0.0, 1.0),
    erase: erase,
    flow: ((m.num('Flow') ?? 1) * 100).clamp(1.0, 100.0),
  );
}
