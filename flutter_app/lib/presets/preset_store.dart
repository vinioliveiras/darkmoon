import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../render/tone_curve.dart';
import 'preset.dart';

/// The user's saved preset library, kept in its own file
/// (`flutter_presets.json`) — a list rather than a per-photo map, since
/// presets aren't tied to any one photo.
Future<Directory> _presetDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<File> _presetFile() async {
  final dir = await _presetDir();
  return File(p.join(dir.path, 'flutter_presets.json'));
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

Preset _decodePreset(Map<String, dynamic> raw) {
  final curvesRaw = raw['curves'] as Map<String, dynamic>?;
  return Preset(
    id: raw['id'] as String,
    name: raw['name'] as String,
    values: {
      for (final entry in (raw['values'] as Map<String, dynamic>).entries)
        entry.key: (entry.value as num).toDouble(),
    },
    curves: curvesRaw == null
        ? identityPhotoCurves
        : PhotoCurves(
            tone: _decodePoints(curvesRaw['tone']),
            red: _decodePoints(curvesRaw['red']),
            green: _decodePoints(curvesRaw['green']),
            blue: _decodePoints(curvesRaw['blue']),
          ),
    unsupportedAttributes: [
      for (final name in (raw['unsupportedAttributes'] as List? ?? const []))
        name as String,
    ],
  );
}

Map<String, dynamic> _encodePreset(Preset preset) => {
  'id': preset.id,
  'name': preset.name,
  'values': preset.values,
  'curves': {
    'tone': _encodePoints(preset.curves.tone),
    'red': _encodePoints(preset.curves.red),
    'green': _encodePoints(preset.curves.green),
    'blue': _encodePoints(preset.curves.blue),
  },
  'unsupportedAttributes': preset.unsupportedAttributes,
};

/// Loads the saved preset library, in save order. Returns an empty list
/// if the file doesn't exist yet or can't be parsed.
Future<List<Preset>> loadPresets() async {
  try {
    final file = await _presetFile();
    if (!await file.exists()) {
      return [];
    }
    final raw = jsonDecode(await file.readAsString()) as List;
    return [
      for (final entry in raw) _decodePreset(entry as Map<String, dynamic>),
    ];
  } catch (_) {
    return [];
  }
}

/// Saves the full preset library, writing to a temp file and renaming
/// over the real one so a crash mid-write can't leave a corrupt file.
Future<void> savePresets(List<Preset> presets) async {
  final file = await _presetFile();
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(
    jsonEncode([for (final preset in presets) _encodePreset(preset)]),
  );
  await tmp.rename(file.path);
}
