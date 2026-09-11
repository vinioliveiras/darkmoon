import 'dart:io';

import 'package:path/path.dart' as p;

import '../catalog/sidecar_xmp.dart';

/// Moving photos and folders on disk — what the library's albums are
/// (2026-09-11, the user's call): an album is a folder, "add to album" is
/// a move, and an album moved is a folder moved. Nothing here touches the
/// catalog; the editor re-keys its stores from the returned paths.
class MoveOutcome {
  const MoveOutcome({required this.moved, required this.skipped});

  /// Old path → new path, for every photo that moved.
  final Map<String, String> moved;

  /// Photos left where they were because a file of the same name already
  /// sits in the target folder — never overwritten.
  final List<String> skipped;
}

/// Moves [paths] into [folder], each with its `.xmp` sidecar when it has
/// one. A photo already in [folder] is neither moved nor skipped. A
/// rename across volumes falls back to copy-then-delete.
Future<MoveOutcome> movePhotosToFolder(
  List<String> paths,
  String folder,
) async {
  final moved = <String, String>{};
  final skipped = <String>[];
  for (final path in paths) {
    if (p.equals(p.dirname(path), folder)) {
      continue;
    }
    final destination = p.join(folder, p.basename(path));
    final file = File(path);
    if (!await file.exists()) {
      continue;
    }
    if (await File(destination).exists()) {
      skipped.add(path);
      continue;
    }
    await _moveFile(file, destination);
    final sidecar = sidecarFileFor(path);
    if (await sidecar.exists()) {
      final sidecarDestination = sidecarFileFor(destination).path;
      if (!await File(sidecarDestination).exists()) {
        await _moveFile(sidecar, sidecarDestination);
      }
    }
    moved[path] = destination;
  }
  return MoveOutcome(moved: moved, skipped: skipped);
}

Future<void> _moveFile(File file, String destination) async {
  try {
    await file.rename(destination);
  } on FileSystemException {
    // Across volumes: rename cannot, so copy and delete.
    await file.copy(destination);
    await file.delete();
  }
}

/// Moves the folder [folder] inside [targetParent], keeping its name.
/// Returns the new path, or null when a folder of that name already
/// exists there, when [targetParent] is [folder] itself or inside it, or
/// when the move fails.
Future<String?> moveFolderInto(String folder, String targetParent) async {
  if (p.equals(folder, targetParent) || p.isWithin(folder, targetParent)) {
    return null;
  }
  if (p.equals(p.dirname(folder), targetParent)) {
    return folder;
  }
  final destination = p.join(targetParent, p.basename(folder));
  if (await Directory(destination).exists() ||
      await File(destination).exists()) {
    return null;
  }
  try {
    await Directory(folder).rename(destination);
    return destination;
  } on FileSystemException {
    return null;
  }
}

/// Creates the folder [name] inside [parent] — a new album. Returns its
/// path, or null when the name is empty, names a path rather than a
/// folder, or already exists.
Future<String?> createSubfolder(String parent, String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty ||
      trimmed == '.' ||
      trimmed == '..' ||
      trimmed.contains('/') ||
      trimmed.contains('\\')) {
    return null;
  }
  final destination = p.join(parent, trimmed);
  if (await Directory(destination).exists() ||
      await File(destination).exists()) {
    return null;
  }
  try {
    await Directory(destination).create();
    return destination;
  } on FileSystemException {
    return null;
  }
}

/// [path] with the prefix [oldFolder] replaced by [newFolder] when it is
/// that folder or inside it; unchanged otherwise. For re-keying catalog
/// entries after a folder move.
String rekeyUnderFolder(String path, String oldFolder, String newFolder) {
  if (p.equals(path, oldFolder)) {
    return newFolder;
  }
  if (p.isWithin(oldFolder, path)) {
    return p.join(newFolder, p.relative(path, from: oldFolder));
  }
  return path;
}
