// The bundled film tables (assets/film_luts/, built by
// tool/build_film_luts.dart from the RawTherapee Film Simulation
// Collection, CC BY-SA 4.0) as the editor sees them: a manifest to list
// in a dropdown and one FilmLut per id to hand to RenderParams.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import 'film_lut.dart';

class FilmLutEntry {
  const FilmLutEntry({
    required this.id,
    required this.file,
    required this.name,
    required this.brand,
    required this.kind,
  });

  final int id;
  final String file;
  final String name;
  final String brand;

  /// `negative`, `slide`, `instant` or `bw`.
  final String kind;

  String get label => '$brand $name';
}

class FilmLutLibrary {
  FilmLutLibrary._(this.entries, this._luts);

  static const assetDir = 'assets/film_luts';

  /// Manifest order — the order the dropdown shows.
  final List<FilmLutEntry> entries;
  final Map<int, FilmLut> _luts;

  FilmLut? byId(int id) => _luts[id];

  FilmLutEntry? entryFor(int id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Reads the manifest and every table it lists. A table that fails to
  /// decode is skipped (its entry stays out of [entries] too) rather than
  /// failing the whole library.
  static Future<FilmLutLibrary> loadBundled() async {
    final raw = await rootBundle.loadString('$assetDir/manifest.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final entries = <FilmLutEntry>[];
    final luts = <int, FilmLut>{};
    for (final item in (json['films'] as List).cast<Map<String, dynamic>>()) {
      final entry = FilmLutEntry(
        id: (item['id'] as num).toInt(),
        file: item['file'] as String,
        name: item['name'] as String,
        brand: item['brand'] as String,
        kind: item['kind'] as String,
      );
      try {
        final bytes = await rootBundle.load('$assetDir/${entry.file}');
        final image = img.decodePng(bytes.buffer.asUint8List());
        if (image == null) continue;
        luts[entry.id] = FilmLut.fromPacked(
          image,
          id: entry.id,
          name: entry.label,
        );
        entries.add(entry);
      } catch (_) {
        // Not bundled or unreadable: leave that film out.
      }
    }
    return FilmLutLibrary._(entries, luts);
  }
}
