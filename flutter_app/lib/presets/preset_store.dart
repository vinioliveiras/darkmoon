import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../diagnostics/dev_log.dart';
import 'preset.dart';
import 'preset_formats.dart';
import 'preset_xmp.dart';

/// The preset library is a plain folder of `.xmp` files at
/// `Documents/darkmoon/presets/` — the source of truth. Imported presets
/// are copied in **byte-for-byte** and never rewritten unless the user
/// explicitly saves changes; presets created in-app are written out here
/// as `.xmp` too. The old single `flutter_presets.json` library is no
/// longer read (left on disk, not deleted, so nothing is lost); re-import
/// the original files to bring them back.
Future<Directory> presetsDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon', 'presets'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// A preset's display name is its filename (without `.xmp`) — so renaming
/// is a real file rename and the on-disk file is the single source of the
/// name, not a value duplicated into a database.
String _nameFromFile(String path) => p.basenameWithoutExtension(path);

String _sanitizeFileBase(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'preset' : cleaned;
}

/// A path inside [dir] for `<base>.xmp`, appending ` (2)`, ` (3)`… until it
/// doesn't collide with an existing file.
Future<String> _uniquePath(Directory dir, String base) async {
  final safe = _sanitizeFileBase(base);
  var candidate = p.join(dir.path, '$safe.xmp');
  var counter = 2;
  while (await File(candidate).exists()) {
    candidate = p.join(dir.path, '$safe ($counter).xmp');
    counter++;
  }
  return candidate;
}

Preset? _parsePresetFile(String path, String contents) {
  final preset = presetFromXmp(contents, fallbackName: _nameFromFile(path));
  if (preset == null) {
    return null;
  }
  return preset.copyWith(id: path, name: _nameFromFile(path), sourcePath: path);
}

/// Loads every `.xmp` in the presets folder, sorted by name (case-
/// insensitive). Unreadable / non-preset files are skipped.
Future<List<Preset>> loadPresets() async {
  try {
    final dir = await presetsDir();
    final presets = <Preset>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.xmp')) {
        continue;
      }
      try {
        final preset = _parsePresetFile(
          entity.path,
          await entity.readAsString(),
        );
        if (preset != null) {
          presets.add(preset);
        }
      } catch (e, st) {
        // Skip a single bad file rather than failing the whole library —
        // but name it, or a preset that silently stops appearing in the
        // list is indistinguishable from one the user deleted.
        DevLog.logError('skipping unreadable preset ${entity.path}', e, st);
      }
    }
    presets.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return presets;
  } catch (e, st) {
    // The whole preset library reads as empty from here.
    DevLog.logError('loadPresets failed, library reads as empty', e, st);
    return [];
  }
}

/// Copies the `.xmp` at [srcPath] into the presets folder unchanged and
/// returns the parsed preset (or null if it isn't a readable preset).
///
/// A preset from another editor (`.lrtemplate`, `.pp3`, `.costyle` — see
/// `preset_formats.dart`) is read with its own reader and stored as a
/// darkmoon `.xmp` written from the result, so the library stays one
/// format whatever came in.
Future<Preset?> importPresetFromFile(String srcPath) async {
  try {
    final contents = await File(srcPath).readAsString();
    if (isForeignPresetPath(srcPath)) {
      return await _storeForeignPreset(
        contents,
        srcPath,
        fallbackName: p.basenameWithoutExtension(srcPath),
      );
    }
    // Name the copy after the preset's own `<Name>` when it has one, so the
    // library shows "Filmatic Fuji 2", not "filmatic-fuji-2".
    final parsed = presetFromXmp(
      contents,
      fallbackName: p.basenameWithoutExtension(srcPath),
    );
    if (parsed == null) {
      return null;
    }
    final dir = await presetsDir();
    final destPath = await _uniquePath(dir, parsed.name);
    await File(srcPath).copy(destPath);
    return _parsePresetFile(destPath, contents);
  } catch (_) {
    return null;
  }
}

/// True for a file one of `preset_formats.dart`'s readers handles.
bool isForeignPresetPath(String path) {
  final lower = path.toLowerCase();
  return foreignPresetExtensions.any((ext) => lower.endsWith('.$ext'));
}

/// Reads a foreign preset and writes it into the library as an `.xmp`.
Future<Preset?> _storeForeignPreset(
  String contents,
  String sourceName, {
  required String fallbackName,
}) async {
  final parsed = presetFromForeignFile(
    sourceName,
    contents,
    fallbackName: fallbackName,
  );
  if (parsed == null) {
    return null;
  }
  final dir = await presetsDir();
  final destPath = await _uniquePath(dir, parsed.name);
  final xmp = xmpFromPreset(parsed);
  await File(destPath).writeAsString(xmp);
  final stored = _parsePresetFile(destPath, xmp);
  // The XMP round trip drops what we could not map; keep that list so
  // the panel can still say the import was partial.
  return stored?.copyWith(unsupportedAttributes: parsed.unsupportedAttributes);
}

/// Unpacks a preset `.zip` (how Meridian exports several at once) or a
/// Capture One `.costylepack` — every `.xmp` entry is written into the
/// presets folder (byte-for-byte) and parsed; every foreign-format entry
/// is converted the way [importPresetFromFile] converts a single file.
Future<List<Preset>> importPresetsFromZipFile(String zipPath) async {
  final imported = <Preset>[];
  try {
    final dir = await presetsDir();
    final archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    for (final entry in archive) {
      if (!entry.isFile) {
        continue;
      }
      if (isForeignPresetPath(entry.name)) {
        try {
          final foreign = await _storeForeignPreset(
            utf8.decode(entry.content as List<int>, allowMalformed: true),
            entry.name,
            fallbackName: p.basenameWithoutExtension(entry.name),
          );
          if (foreign != null) {
            imported.add(foreign);
          }
        } catch (_) {
          // One bad entry must not sink the rest of the archive.
        }
        continue;
      }
      if (!entry.name.toLowerCase().endsWith('.xmp')) {
        continue;
      }
      try {
        final raw = entry.content as List<int>;
        final contents = utf8.decode(raw, allowMalformed: true);
        final parsed = presetFromXmp(
          contents,
          fallbackName: p.basenameWithoutExtension(entry.name),
        );
        if (parsed == null) {
          continue;
        }
        final destPath = await _uniquePath(dir, parsed.name);
        await File(destPath).writeAsBytes(raw);
        final stored = _parsePresetFile(destPath, contents);
        if (stored != null) {
          imported.add(stored);
        }
      } catch (_) {
        // Skip a bad entry.
      }
    }
  } catch (_) {
    // Not a valid zip — return whatever parsed.
  }
  return imported;
}

/// Writes a preset created in-app (or an explicit "save changes") to a new
/// `.xmp` in the presets folder and returns it with its `sourcePath`/`id`
/// set. Never overwrites an existing file — [preset.name] is de-duplicated.
Future<Preset> savePresetToFile(Preset preset) async {
  final dir = await presetsDir();
  final destPath = await _uniquePath(dir, preset.name);
  await File(destPath).writeAsString(xmpFromPreset(preset));
  return preset.copyWith(
    id: destPath,
    name: _nameFromFile(destPath),
    sourcePath: destPath,
  );
}

/// Renames the preset's file (its display name *is* the filename). The
/// file contents are moved untouched — no re-serialisation, so an imported
/// preset keeps every attribute Darkmoon doesn't model.
Future<Preset> renamePresetFile(Preset preset, String newName) async {
  final src = preset.sourcePath;
  if (src == null) {
    return preset.copyWith(name: newName);
  }
  final dir = await presetsDir();
  final destPath = await _uniquePath(dir, newName);
  await File(src).rename(destPath);
  return preset.copyWith(
    id: destPath,
    name: _nameFromFile(destPath),
    sourcePath: destPath,
  );
}

Future<void> deletePresetFile(Preset preset) async {
  final src = preset.sourcePath;
  if (src == null) {
    return;
  }
  try {
    final file = File(src);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Best-effort.
  }
}
