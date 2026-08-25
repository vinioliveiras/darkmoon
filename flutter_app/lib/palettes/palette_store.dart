import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'palette.dart';

/// The user's imported color palettes, kept in their own file
/// (`flutter_palettes.json`) — a list rather than a per-photo map, since
/// palettes (like presets) aren't tied to any one photo.
Future<Directory> _paletteDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<File> _paletteFile() async {
  final dir = await _paletteDir();
  return File(p.join(dir.path, 'flutter_palettes.json'));
}

ColorPalette _decodePalette(Map<String, dynamic> raw) => ColorPalette(
  id: raw['id'] as String,
  name: raw['name'] as String,
  swatches: [
    for (final entry in raw['swatches'] as List)
      PaletteSwatch(
        name: (entry as Map<String, dynamic>)['name'] as String,
        rgb: entry['rgb'] as int,
      ),
  ],
);

Map<String, dynamic> _encodePalette(ColorPalette palette) => {
  'id': palette.id,
  'name': palette.name,
  'swatches': [
    for (final swatch in palette.swatches)
      {'name': swatch.name, 'rgb': swatch.rgb},
  ],
};

/// Loads the saved palette library, in import order. Returns an empty list
/// if the file doesn't exist yet or can't be parsed.
Future<List<ColorPalette>> loadPalettes() async {
  try {
    final file = await _paletteFile();
    if (!await file.exists()) {
      return [];
    }
    final raw = jsonDecode(await file.readAsString()) as List;
    return [
      for (final entry in raw) _decodePalette(entry as Map<String, dynamic>),
    ];
  } catch (_) {
    return [];
  }
}

/// Saves the full palette library, writing to a temp file and renaming
/// over the real one so a crash mid-write can't leave a corrupt file.
Future<void> savePalettes(List<ColorPalette> palettes) async {
  final file = await _paletteFile();
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(
    jsonEncode([for (final palette in palettes) _encodePalette(palette)]),
  );
  await tmp.rename(file.path);
}
