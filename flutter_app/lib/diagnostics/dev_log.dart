import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The folder dev-mode logs are written to — also used by Settings' "Open
/// Log Folder" button, so both sides agree on the location without
/// duplicating the path logic.
Future<Directory> resolveDevLogDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon', 'logs'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// How long a log file is kept before [DevLog] deletes it on startup —
/// generous enough to cover "it happened a few days ago", short enough
/// that leaving Developer Mode on doesn't quietly accumulate logs forever.
const _maxLogAgeDays = 14;

/// Opt-in diagnostic logging for bug reports (Settings' Developer Mode
/// toggle, off by default — normal use never writes anything to disk).
///
/// Deliberately main-isolate-only: every event worth logging already flows
/// back to the main isolate through a SendPort (progress/result messages
/// from the RAW decode, render, export and AI Enhance isolates all work
/// this way already), so logging only from here sidesteps any concurrent-
/// append corruption risk from multiple isolates writing the same file,
/// without needing a lock file.
class DevLog {
  DevLog._();

  static bool _enabled = false;
  static Future<File>? _fileFuture;

  static bool get enabled => _enabled;

  /// Call once at startup, and again whenever the Settings toggle changes.
  static void setEnabled(bool value) {
    _enabled = value;
  }

  /// Appends one timestamped line, tagged by [tag], to today's log file —
  /// a no-op unless [setEnabled] turned logging on. Fire-and-forget: a
  /// logger must never make the caller wait, and errors writing the log
  /// itself are swallowed — it must never be the thing that crashes the
  /// app it's trying to help debug.
  static void log(String message, {String tag = 'app'}) {
    if (!_enabled) return;
    unawaited(_append('[$tag] $message'));
  }

  /// Convenience for catch blocks and global error handlers.
  static void logError(String context, Object error, [StackTrace? stack]) {
    log('$context: $error${stack == null ? '' : '\n$stack'}', tag: 'error');
  }

  static Future<void> _append(String line) async {
    try {
      final file = await (_fileFuture ??= _resolveFile());
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString(
        '$timestamp $line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // See [log]'s doc — never let a logging failure surface further.
    }
  }

  static Future<File> _resolveFile() async {
    final dir = await resolveDevLogDir();
    unawaited(_pruneOldLogs(dir));
    final today = DateTime.now().toIso8601String().split('T').first;
    return File(p.join(dir.path, 'darkmoon-$today.log'));
  }

  static Future<void> _pruneOldLogs(Directory dir) async {
    try {
      final cutoff = DateTime.now().subtract(
        const Duration(days: _maxLogAgeDays),
      );
      await for (final entry in dir.list()) {
        if (entry is! File || !entry.path.endsWith('.log')) {
          continue;
        }
        final stat = await entry.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entry.delete();
        }
      }
    } catch (_) {
      // Best-effort housekeeping — a failed cleanup shouldn't block logging.
    }
  }
}
