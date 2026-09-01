import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'preset.dart';
import 'preset_xmp.dart';

/// Encodes [presets] into a `.zip` of one `.xmp` per preset — the bulk
/// counterpart to [presetsFromZip], used by the Presets panel's
/// multi-select "export" action. Names are sanitised and de-duplicated so
/// two presets called the same thing don't collide inside the archive.
List<int> presetsToZipBytes(List<Preset> presets) {
  final archive = Archive();
  final usedNames = <String>{};
  for (final preset in presets) {
    var base = preset.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (base.isEmpty) {
      base = 'preset';
    }
    var name = '$base.xmp';
    var counter = 2;
    while (!usedNames.add(name.toLowerCase())) {
      name = '$base ($counter).xmp';
      counter++;
    }
    final bytes = utf8.encode(xmpFromPreset(preset));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}

/// Extracts every `.xmp` preset found anywhere inside a Meridian preset
/// export `.zip` — Meridian bundles multiple presets this way, often
/// nested under a group/folder structure inside the archive, so this
/// walks every entry rather than assuming a flat layout. Best-effort:
/// an unreadable zip or a non-preset entry is skipped rather than failing
/// the whole import.
Future<List<Preset>> presetsFromZip(String zipPath) async {
  final presets = <Preset>[];
  try {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      if (!entry.isFile || !entry.name.toLowerCase().endsWith('.xmp')) {
        continue;
      }
      try {
        final content = utf8.decode(
          entry.content as List<int>,
          allowMalformed: true,
        );
        final preset = presetFromXmp(
          content,
          fallbackName: p.basenameWithoutExtension(entry.name),
        );
        if (preset != null) {
          presets.add(preset);
        }
      } catch (_) {
        // Skip unreadable entries — best effort.
      }
    }
  } catch (_) {
    // Not a valid zip / unreadable file — return whatever was found so far
    // (likely nothing).
  }
  return presets;
}
