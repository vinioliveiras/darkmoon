import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../diagnostics/dev_log.dart';
import '../render/mask.dart';
import '../render/tone_curve.dart';
import 'legacy_filename_migration.dart';

/// Per-photo mask layers (Linear/Radial Gradient for now), keyed by
/// absolute RAW file path — kept in its own file (`darkmoon_masks.json`)
/// since a mask is structured data (geometry + its own slider values),
/// not a single double like the rest of the catalog.
Future<Directory> _maskDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<File> _maskFile() async {
  final dir = await _maskDir();
  await migrateLegacyFilename(dir, 'flutter_masks.json', 'darkmoon_masks.json');
  return File(p.join(dir.path, 'darkmoon_masks.json'));
}

BrushGeometry _decodeBrush(List<dynamic>? raw) {
  if (raw == null) {
    return const BrushGeometry();
  }
  return BrushGeometry(
    strokes: [
      for (final strokeRaw in raw)
        BrushStroke(
          radius: ((strokeRaw as Map<String, dynamic>)['radius'] as num)
              .toDouble(),
          hardness: (strokeRaw['hardness'] as num).toDouble(),
          erase: strokeRaw['erase'] as bool? ?? false,
          flow: (strokeRaw['flow'] as num?)?.toDouble() ?? 100,
          points: [
            for (final pointRaw in strokeRaw['points'] as List)
              BrushPoint(
                ((pointRaw as List)[0] as num).toDouble(),
                (pointRaw[1] as num).toDouble(),
              ),
          ],
        ),
    ],
  );
}

List<CurvePoint> _decodePoints(dynamic raw) {
  if (raw == null) {
    return identityToneCurve;
  }
  return [
    for (final pair in raw as List)
      CurvePoint((pair[0] as num).toDouble(), (pair[1] as num).toDouble()),
  ];
}

List<List<double>> _encodePoints(List<CurvePoint> points) => [
  for (final point in points) [point.x, point.y],
];

PhotoCurves _decodeCurves(Map<String, dynamic>? raw) {
  if (raw == null) {
    return identityPhotoCurves;
  }
  return PhotoCurves(
    tone: _decodePoints(raw['tone']),
    red: _decodePoints(raw['red']),
    green: _decodePoints(raw['green']),
    blue: _decodePoints(raw['blue']),
  );
}

Map<String, dynamic> _encodeCurves(PhotoCurves curves) => {
  'tone': _encodePoints(curves.tone),
  'red': _encodePoints(curves.red),
  'green': _encodePoints(curves.green),
  'blue': _encodePoints(curves.blue),
};

List<Map<String, dynamic>> _encodeBrush(BrushGeometry brush) => [
  for (final stroke in brush.strokes)
    {
      'radius': stroke.radius,
      'hardness': stroke.hardness,
      'erase': stroke.erase,
      'flow': stroke.flow,
      'points': [
        for (final point in stroke.points) [point.x, point.y],
      ],
    },
];

MaskLayer _decodeMask(Map<String, dynamic> raw) {
  final type = MaskType.values.byName(raw['type'] as String);
  final linearRaw = raw['linear'] as Map<String, dynamic>?;
  final radialRaw = raw['radial'] as Map<String, dynamic>?;
  final colorRangeRaw = raw['colorRange'] as Map<String, dynamic>?;
  final luminanceRaw = raw['luminance'] as Map<String, dynamic>?;
  return MaskLayer(
    id: raw['id'] as String,
    name: raw['name'] as String,
    type: type,
    enabled: raw['enabled'] as bool? ?? true,
    inverted: raw['inverted'] as bool? ?? false,
    opacity: (raw['opacity'] as num?)?.toDouble() ?? 100,
    linear: linearRaw == null
        ? const LinearGradientGeometry()
        : LinearGradientGeometry(
            startX: (linearRaw['startX'] as num).toDouble(),
            startY: (linearRaw['startY'] as num).toDouble(),
            endX: (linearRaw['endX'] as num).toDouble(),
            endY: (linearRaw['endY'] as num).toDouble(),
          ),
    radial: radialRaw == null
        ? const RadialGradientGeometry()
        : RadialGradientGeometry(
            centerX: (radialRaw['centerX'] as num).toDouble(),
            centerY: (radialRaw['centerY'] as num).toDouble(),
            radius: (radialRaw['radius'] as num).toDouble(),
            // Ellipse + rotation shipped after circles-only masks were
            // already in catalogs — nullable casts so old entries load
            // (null radiusY = circle, angle 0 = unrotated).
            radiusY: (radialRaw['radiusY'] as num?)?.toDouble(),
            angle: (radialRaw['angle'] as num?)?.toDouble() ?? 0.0,
            feather: (radialRaw['feather'] as num).toDouble(),
          ),
    brush: _decodeBrush(raw['brush'] as List<dynamic>?),
    colorRange: colorRangeRaw == null
        ? const ColorRangeGeometry()
        : ColorRangeGeometry(
            r: (colorRangeRaw['r'] as num).toDouble(),
            g: (colorRangeRaw['g'] as num).toDouble(),
            b: (colorRangeRaw['b'] as num).toDouble(),
            tolerance: (colorRangeRaw['tolerance'] as num).toDouble(),
            feather: (colorRangeRaw['feather'] as num).toDouble(),
          ),
    luminance: luminanceRaw == null
        ? const LuminanceGeometry()
        : LuminanceGeometry(
            targetLuma: (luminanceRaw['targetLuma'] as num).toDouble(),
            tolerance: (luminanceRaw['tolerance'] as num).toDouble(),
            feather: (luminanceRaw['feather'] as num).toDouble(),
          ),
    values: {
      for (final entry in (raw['values'] as Map<String, dynamic>).entries)
        entry.key: (entry.value as num).toDouble(),
    },
    curves: _decodeCurves(raw['curves'] as Map<String, dynamic>?),
  );
}

Map<String, dynamic> _encodeMask(MaskLayer mask) => {
  'id': mask.id,
  'name': mask.name,
  'type': mask.type.name,
  'enabled': mask.enabled,
  'inverted': mask.inverted,
  'opacity': mask.opacity,
  'linear': {
    'startX': mask.linear.startX,
    'startY': mask.linear.startY,
    'endX': mask.linear.endX,
    'endY': mask.linear.endY,
  },
  'radial': {
    'centerX': mask.radial.centerX,
    'centerY': mask.radial.centerY,
    'radius': mask.radial.radius,
    // Written only once the user actually stretched/rotated the shape,
    // keeping untouched circles identical to pre-ellipse catalog entries.
    if (mask.radial.radiusY != null) 'radiusY': mask.radial.radiusY,
    if (mask.radial.angle != 0.0) 'angle': mask.radial.angle,
    'feather': mask.radial.feather,
  },
  'brush': _encodeBrush(mask.brush),
  'colorRange': {
    'r': mask.colorRange.r,
    'g': mask.colorRange.g,
    'b': mask.colorRange.b,
    'tolerance': mask.colorRange.tolerance,
    'feather': mask.colorRange.feather,
  },
  'luminance': {
    'targetLuma': mask.luminance.targetLuma,
    'tolerance': mask.luminance.tolerance,
    'feather': mask.luminance.feather,
  },
  'values': mask.values,
  'curves': _encodeCurves(mask.curves),
};

/// Loads every saved photo's mask stack. Returns an empty map if the file
/// doesn't exist yet or can't be parsed.
Future<Map<String, List<MaskLayer>>> loadPhotoMasks() async {
  try {
    final file = await _maskFile();
    if (!await file.exists()) {
      return {};
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return {
      for (final entry in raw.entries)
        entry.key: [
          for (final mask in entry.value as List)
            _decodeMask(mask as Map<String, dynamic>),
        ],
    };
  } catch (e, st) {
    DevLog.logError('loadMasks failed, treating masks as empty', e, st);
    return {};
  }
}

/// Saves every photo's mask stack, writing to a temp file and renaming
/// over the real one so a crash mid-write can't leave a corrupt file.
Future<void> savePhotoMasks(Map<String, List<MaskLayer>> masks) async {
  final file = await _maskFile();
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(
    jsonEncode({
      for (final entry in masks.entries)
        entry.key: [for (final mask in entry.value) _encodeMask(mask)],
    }),
  );
  await tmp.rename(file.path);
}

/// Deletes every saved mask — used by the same Settings "clear catalog"
/// action that clears slider edits and curves, since a mask is also a
/// per-photo edit.
Future<void> clearPhotoMasks() async {
  final file = await _maskFile();
  if (await file.exists()) {
    await file.delete();
  }
}
