import 'dart:io';

import 'package:path/path.dart' as p;

const rawExtensions = {
  '.cr2',
  '.cr3',
  '.nef',
  '.arw',
  '.dng',
  '.raf',
  '.orf',
  '.rw2',
};

/// Common (non-RAW) image formats decoded via `package:image` rather than
/// LibRaw — already-processed images with no sensor data to demosaic, but
/// otherwise pushed through the exact same edit pipeline (see
/// `native/edit_source.dart`'s `decodeEditSources`).
const commonImageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.tif',
  '.tiff',
  '.webp',
  '.bmp',
};

/// Whether [path] is a RAW file this app can open, by extension.
bool isRawFile(String path) =>
    rawExtensions.contains(p.extension(path).toLowerCase());

/// Whether [path] is a supported common (non-RAW) image, by extension.
bool isCommonImageFile(String path) =>
    commonImageExtensions.contains(p.extension(path).toLowerCase());

/// A photo file found on disk — either RAW or a common image format (see
/// [isRaw]). Mirrors the Python app's list_raw_files: no decoding happens
/// here, just filesystem metadata.
class RawFile {
  RawFile(this.path, this.modified) : isRaw = isRawFile(path);

  final String path;
  final DateTime modified;

  /// True for a RAW file (decoded via LibRaw), false for a common image
  /// format (decoded via `package:image`) — drives both which decode path
  /// `edit_source.dart`/`export_job.dart` take and the filmstrip's
  /// type badge.
  final bool isRaw;

  String get name => p.basename(path);

  /// The file extension, uppercase and without the leading dot (e.g.
  /// "RAF", "JPG") — shown as the filmstrip's type badge.
  String get typeLabel => p.extension(path).replaceFirst('.', '').toUpperCase();
}

/// Lists photo files directly inside [folderPath], most recently modified
/// first. When [rawOnly] is true, common (non-RAW) image formats are
/// excluded — the "work with RAW only" library preference.
Future<List<RawFile>> listRawFiles(
  String folderPath, {
  bool rawOnly = false,
}) async {
  final dir = Directory(folderPath);
  if (!dir.existsSync()) {
    return const [];
  }
  final candidates = <File>[];
  await for (final entry in dir.list(followLinks: false)) {
    if (entry is! File) {
      continue;
    }
    final ext = p.extension(entry.path).toLowerCase();
    final matches =
        rawExtensions.contains(ext) ||
        (!rawOnly && commonImageExtensions.contains(ext));
    if (!matches) {
      continue;
    }
    candidates.add(entry);
  }
  // stat() calls are independent I/O, so fan them out concurrently rather
  // than awaiting one at a time — for a folder with thousands of RAWs that
  // was thousands of sequential syscalls serialized before the thumbnail
  // worker pool even got its file list.
  final files = await Future.wait(
    candidates.map(
      (entry) async => RawFile(entry.path, (await entry.stat()).modified),
    ),
  );
  files.sort((a, b) => b.modified.compareTo(a.modified));
  return files;
}
