import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App-wide settings, mirroring the Python app's `DEFAULT_SETTINGS` (minus
/// the thumbnail disk cache setting, since this port's cache doesn't have
/// a size/eviction knob yet to expose).
class AppSettings {
  const AppSettings({
    this.language = 'auto',
    this.fastPreview = true,
    this.thumbnailConcurrency = 4,
  });

  /// 'auto' (follow the system language), 'en', or 'pt'.
  final String language;

  /// While true, actively dragging a slider re-renders against the smaller
  /// "live" resolution for speed; while false, every render uses full
  /// preview quality (slower to update while dragging).
  final bool fastPreview;

  /// How many thumbnails to decode concurrently when a folder is opened.
  final int thumbnailConcurrency;

  AppSettings copyWith({String? language, bool? fastPreview, int? thumbnailConcurrency}) => AppSettings(
        language: language ?? this.language,
        fastPreview: fastPreview ?? this.fastPreview,
        thumbnailConcurrency: thumbnailConcurrency ?? this.thumbnailConcurrency,
      );
}

Future<File> _settingsFile() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return File(p.join(dir.path, 'flutter_settings.json'));
}

Future<AppSettings> loadSettings() async {
  try {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return const AppSettings();
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    const defaults = AppSettings();
    return AppSettings(
      language: raw['language'] as String? ?? defaults.language,
      fastPreview: raw['fastPreview'] as bool? ?? defaults.fastPreview,
      thumbnailConcurrency: (raw['thumbnailConcurrency'] as num?)?.toInt() ?? defaults.thumbnailConcurrency,
    );
  } catch (_) {
    return const AppSettings();
  }
}

Future<void> saveSettings(AppSettings settings) async {
  final file = await _settingsFile();
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(
    jsonEncode({
      'language': settings.language,
      'fastPreview': settings.fastPreview,
      'thumbnailConcurrency': settings.thumbnailConcurrency,
    }),
  );
  await tmp.rename(file.path);
}
