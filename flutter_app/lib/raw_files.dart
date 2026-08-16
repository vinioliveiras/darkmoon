import 'dart:io';

import 'package:path/path.dart' as p;

const rawExtensions = {'.cr2', '.cr3', '.nef', '.arw', '.dng', '.raf', '.orf', '.rw2'};

/// A RAW photo file found on disk. Mirrors the Python app's list_raw_files:
/// no decoding happens here, just filesystem metadata.
class RawFile {
  RawFile(this.path, this.modified);

  final String path;
  final DateTime modified;

  String get name => p.basename(path);
}

/// Lists RAW files directly inside [folderPath], most recently modified first.
Future<List<RawFile>> listRawFiles(String folderPath) async {
  final dir = Directory(folderPath);
  if (!dir.existsSync()) {
    return const [];
  }
  final files = <RawFile>[];
  await for (final entry in dir.list(followLinks: false)) {
    if (entry is! File) {
      continue;
    }
    if (!rawExtensions.contains(p.extension(entry.path).toLowerCase())) {
      continue;
    }
    final stat = await entry.stat();
    files.add(RawFile(entry.path, stat.modified));
  }
  files.sort((a, b) => b.modified.compareTo(a.modified));
  return files;
}
