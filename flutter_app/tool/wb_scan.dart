// Prints "<file>: <cam_mul>" for every RAW under a folder, so a file can
// be located by its as-shot multipliers.
//
// Usage: dart run tool/wb_scan.dart <folder> [substring-to-match]
import 'dart:io';

import 'package:darkmoon/native/libraw.dart';

const _rawExt = {'.raf', '.cr2', '.cr3', '.nef', '.arw', '.dng', '.rw2', '.orf'};

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/wb_scan.dart <folder> [match]');
    exit(1);
  }
  for (final dll in ['raw_r.dll', 'vcomp140.dll']) {
    final built = File('build/windows/x64/runner/Release/$dll');
    if (!File(dll).existsSync() && built.existsSync()) {
      built.copySync(dll);
    }
  }
  final dir = Directory(args[0]);
  final match = args.length > 1 ? args[1].toLowerCase() : null;
  for (final e in dir.listSync()) {
    if (e is! File) continue;
    final ext = e.path.toLowerCase();
    if (!_rawExt.any(ext.endsWith)) continue;
    final m = readCamMul(e.path);
    if (m == null) continue;
    final line = '${e.uri.pathSegments.last}: '
        '[${m.map((v) => v.toStringAsFixed(0)).join(', ')}]';
    if (match == null || line.toLowerCase().contains(match)) {
      // ignore: avoid_print
      print(line);
    }
  }
}
