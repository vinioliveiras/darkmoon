// The film tables as the editor sees them: a manifest to list in a
// dropdown and one FilmLut per id to hand to RenderParams. Two sources:
//
//  - the bundled stocks (assets/film_luts/, built by
//    tool/build_film_luts.dart from the RawTherapee Film Simulation
//    Collection, CC BY-SA 4.0), ids 1..999;
//  - the user's own imports (2026-09-13): `.cube` files and Hald CLUT
//    images dropped in through the FILM section's import button, kept in
//    `<documents>/darkmoon/luts/` as packed 33^3 PNGs with their own
//    manifest, ids from [userIdBase] up. A photo or preset stores the
//    id, so both ranges are append-only and never renumbered.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

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

  /// Empty for a user import.
  final String brand;

  /// `negative`, `slide`, `instant`, `bw` — or `user` for an import.
  final String kind;

  bool get isUser => kind == 'user';

  String get label => brand.isEmpty ? name : '$brand $name';
}

class FilmLutLibrary {
  FilmLutLibrary._(this.entries, this._luts, this.userDir);

  static const assetDir = 'assets/film_luts';

  /// The first id a user import takes; bundled ids stay below it.
  static const userIdBase = 1000;

  static const _userManifest = 'manifest.json';

  /// Bundled first (manifest order), then the user's imports in the order
  /// they were imported — the order the dropdown shows.
  final List<FilmLutEntry> entries;
  final Map<int, FilmLut> _luts;

  /// Where imports live; null when the library was opened without one
  /// (imports are refused then).
  final Directory? userDir;

  FilmLut? byId(int id) => _luts[id];

  FilmLutEntry? entryFor(int id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// A library with nothing in it yet — a test's, or the fallback when the
  /// bundled manifest is missing.
  factory FilmLutLibrary.empty({Directory? userDir}) =>
      FilmLutLibrary._([], {}, userDir);

  /// Reads the bundled manifest and every table it lists, then the user's
  /// imports from [userDir] when given. A table that fails to decode is
  /// skipped (its entry stays out of [entries] too) rather than failing
  /// the whole library.
  static Future<FilmLutLibrary> loadBundled({Directory? userDir}) async {
    final raw = await rootBundle.loadString('$assetDir/manifest.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final library = FilmLutLibrary.empty(userDir: userDir);
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
        library._add(
          entry,
          FilmLut.fromPacked(image, id: entry.id, name: entry.label),
        );
      } catch (_) {
        // Not bundled or unreadable: leave that film out.
      }
    }
    await library.loadUser();
    return library;
  }

  void _add(FilmLutEntry entry, FilmLut lut) {
    entries.removeWhere((e) => e.id == entry.id);
    entries.add(entry);
    _luts[entry.id] = lut;
  }

  /// Reads the imports listed in [userDir]'s manifest. No directory or no
  /// manifest means no imports yet; an entry whose PNG is gone or broken
  /// is skipped like a bundled one.
  Future<void> loadUser() async {
    final dir = userDir;
    if (dir == null) return;
    final manifest = File(p.join(dir.path, _userManifest));
    if (!await manifest.exists()) return;
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    for (final item
        in ((json['luts'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final entry = FilmLutEntry(
        id: (item['id'] as num).toInt(),
        file: item['file'] as String,
        name: item['name'] as String,
        brand: '',
        kind: 'user',
      );
      try {
        final bytes = await File(p.join(dir.path, entry.file)).readAsBytes();
        final image = img.decodePng(bytes);
        if (image == null) continue;
        _add(entry, FilmLut.fromPacked(image, id: entry.id, name: entry.name));
      } catch (_) {
        // Deleted or unreadable: leave it out.
      }
    }
  }

  /// Parses [path] — a `.cube` file, or a Hald CLUT / packed-layout image
  /// — without importing it. Throws a [FormatException] with a readable
  /// message when it is neither.
  static Future<FilmLut> parseFile(String path) async {
    final ext = p.extension(path).toLowerCase();
    final stem = p.basenameWithoutExtension(path);
    if (ext == '.cube') {
      return FilmLut.fromCube(await File(path).readAsString(), name: stem);
    }
    final image = img.decodeImage(await File(path).readAsBytes());
    if (image == null) {
      throw FormatException(
        'not a .cube file or an image: ${p.basename(path)}',
      );
    }
    try {
      return FilmLut.fromHald(image, name: stem);
    } on FormatException {
      try {
        return FilmLut.fromPacked(image, name: stem);
      } on FormatException {
        throw FormatException(
          'not a Hald CLUT (${image.width}x${image.height}): '
          '${p.basename(path)}',
        );
      }
    }
  }

  /// Imports the table at [path]: parsed, resampled to [filmLutSize] when
  /// it is any other size, written to [userDir] as a packed PNG under the
  /// next free user id and listed in the manifest. Returns the new entry.
  /// Throws a [FormatException] for a file that is not a table and a
  /// [StateError] when the library has no user directory.
  Future<FilmLutEntry> importFile(String path) async {
    final dir = userDir;
    if (dir == null) {
      throw StateError('this library has nowhere to keep imports');
    }
    final parsed = await parseFile(path);
    final id = nextUserId;
    final lut = (parsed.size == filmLutSize
        ? parsed
        : parsed.resampled(filmLutSize));
    final file = 'user_$id.png';
    await dir.create(recursive: true);
    await File(
      p.join(dir.path, file),
    ).writeAsBytes(img.encodePng(lut.toPacked(), level: 6));
    final entry = FilmLutEntry(
      id: id,
      file: file,
      name: parsed.name.isEmpty
          ? p.basenameWithoutExtension(path)
          : parsed.name,
      brand: '',
      kind: 'user',
    );
    _add(
      entry,
      FilmLut(size: lut.size, data: lut.data, id: id, name: entry.name),
    );
    await _writeUserManifest(dir);
    return entry;
  }

  /// One past the highest user id, or [userIdBase] for the first import.
  int get nextUserId {
    var next = userIdBase;
    for (final e in entries) {
      if (e.isUser && e.id >= next) next = e.id + 1;
    }
    return next;
  }

  Future<void> _writeUserManifest(Directory dir) async {
    final luts = [
      for (final e in entries)
        if (e.isUser) {'id': e.id, 'file': e.file, 'name': e.name},
    ];
    await File(
      p.join(dir.path, _userManifest),
    ).writeAsString(const JsonEncoder.withIndent('  ').convert({'luts': luts}));
  }
}
