import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../diagnostics/dev_log.dart';
import '../render/tone_curve.dart';
import 'atomic_json_file.dart';
import 'legacy_filename_migration.dart';

/// Per-photo curves (Tone Curve + Color Curve's R/G/B channels), keyed by
/// absolute RAW file path — kept in its own file
/// (`darkmoon_photo_curves.json`) rather than folded into
/// `darkmoon_catalog.json`'s flat `{sliderName: value}` shape, since a
/// curve is a list of points, not a single double.
Future<Directory> _curveDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<File> _curveFile() async {
  final dir = await _curveDir();
  await migrateLegacyFilename(
    dir,
    'flutter_photo_curves.json',
    'darkmoon_photo_curves.json',
  );
  return File(p.join(dir.path, 'darkmoon_photo_curves.json'));
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

/// One photo's curves as the catalog JSON stores them — the inverse of
/// [encodePhotoCurves]. Public for the `.xmp` sidecar (sidecar_xmp.dart),
/// which embeds the same JSON.
PhotoCurves decodePhotoCurves(Map<String, dynamic>? raw) {
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

/// One photo's curves as the catalog JSON stores them — see
/// [decodePhotoCurves].
Map<String, dynamic> encodePhotoCurves(PhotoCurves curves) => {
  'tone': _encodePoints(curves.tone),
  'red': _encodePoints(curves.red),
  'green': _encodePoints(curves.green),
  'blue': _encodePoints(curves.blue),
};

/// Loads every saved photo's curves. Returns an empty map if the file
/// doesn't exist yet or can't be parsed.
Future<Map<String, PhotoCurves>> loadPhotoCurves() async {
  try {
    final file = await _curveFile();
    final raw = await readJsonObject(file, what: 'curves');
    if (raw == null) {
      return {};
    }
    return {
      for (final entry in raw.entries)
        entry.key: decodePhotoCurves(entry.value as Map<String, dynamic>),
    };
  } catch (e, st) {
    DevLog.logError('loadCurves failed, treating curves as empty', e, st);
    return {};
  }
}

/// Saves every photo's curves — see [writeJsonFileAtomically] for the
/// crash and overlap guarantees.
Future<void> savePhotoCurves(Map<String, PhotoCurves> curves) async {
  final file = await _curveFile();
  await writeJsonFileAtomically(
    file,
    jsonEncode({
      for (final entry in curves.entries)
        entry.key: encodePhotoCurves(entry.value),
    }),
  );
}

/// Deletes every saved photo curve — used by the same Settings "clear
/// catalog" action that clears slider edits, since a curve is also a
/// per-photo edit.
Future<void> clearPhotoCurves() async {
  final file = await _curveFile();
  if (await file.exists()) {
    await file.delete();
  }
}
