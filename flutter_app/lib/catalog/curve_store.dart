import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../render/tone_curve.dart';
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

/// Loads every saved photo's curves. Returns an empty map if the file
/// doesn't exist yet or can't be parsed.
Future<Map<String, PhotoCurves>> loadPhotoCurves() async {
  try {
    final file = await _curveFile();
    if (!await file.exists()) {
      return {};
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return {
      for (final entry in raw.entries)
        entry.key: PhotoCurves(
          tone: _decodePoints((entry.value as Map<String, dynamic>)['tone']),
          red: _decodePoints((entry.value as Map<String, dynamic>)['red']),
          green: _decodePoints((entry.value as Map<String, dynamic>)['green']),
          blue: _decodePoints((entry.value as Map<String, dynamic>)['blue']),
        ),
    };
  } catch (_) {
    return {};
  }
}

/// Saves every photo's curves, writing to a temp file and renaming over
/// the real one so a crash mid-write can't leave a corrupt/truncated file.
Future<void> savePhotoCurves(Map<String, PhotoCurves> curves) async {
  final file = await _curveFile();
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(
    jsonEncode({
      for (final entry in curves.entries)
        entry.key: {
          'tone': _encodePoints(entry.value.tone),
          'red': _encodePoints(entry.value.red),
          'green': _encodePoints(entry.value.green),
          'blue': _encodePoints(entry.value.blue),
        },
    }),
  );
  await tmp.rename(file.path);
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
