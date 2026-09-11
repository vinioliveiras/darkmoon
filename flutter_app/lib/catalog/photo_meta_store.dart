import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../diagnostics/dev_log.dart';
import 'atomic_json_file.dart';

/// What a library keeps about a photo besides its edits: a star rating,
/// a colour label and keywords — the `xmp:Rating` / `xmp:Label` /
/// `dc:subject` of the sidecar, so they travel with the file and other
/// applications read and write the same three (2026-09-11, the first
/// piece of the Library screen).
class PhotoMeta {
  const PhotoMeta({this.rating = 0, this.label = '', this.tags = const []});

  /// 0 (none) to 5.
  final int rating;

  /// One of [photoLabelNames], or empty for none. Stored by name, as
  /// Meridian writes it, so a label set elsewhere shows here.
  final String label;

  final List<String> tags;

  bool get isEmpty => rating == 0 && label.isEmpty && tags.isEmpty;

  PhotoMeta copyWith({int? rating, String? label, List<String>? tags}) =>
      PhotoMeta(
        rating: rating ?? this.rating,
        label: label ?? this.label,
        tags: tags ?? this.tags,
      );

  Map<String, dynamic> toJson() => {
    if (rating != 0) 'rating': rating,
    if (label.isNotEmpty) 'label': label,
    if (tags.isNotEmpty) 'tags': tags,
  };

  static PhotoMeta fromJson(Map<String, dynamic> raw) => PhotoMeta(
    rating: ((raw['rating'] as num?)?.toInt() ?? 0).clamp(0, 5),
    label: raw['label'] as String? ?? '',
    tags: [
      for (final tag in raw['tags'] as List? ?? const [])
        if (tag is String && tag.isNotEmpty) tag,
    ],
  );
}

/// The five colour labels, by the names every RAW editor writes into
/// `xmp:Label`. The keyboard puts the first four on 6-9, as Meridian does.
const List<String> photoLabelNames = [
  'Red',
  'Yellow',
  'Green',
  'Blue',
  'Purple',
];

Future<File> _photoMetaFile() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return File(p.join(dir.path, 'darkmoon_photo_meta.json'));
}

/// Every photo's [PhotoMeta], keyed by absolute path. Empty when the file
/// does not exist yet or cannot be parsed.
Future<Map<String, PhotoMeta>> loadPhotoMeta() async {
  try {
    final file = await _photoMetaFile();
    final raw = await readJsonObject(file, what: 'photo metadata');
    if (raw == null) {
      return {};
    }
    return {
      for (final entry in raw.entries)
        entry.key: PhotoMeta.fromJson(entry.value as Map<String, dynamic>),
    };
  } catch (e, st) {
    DevLog.logError('loadPhotoMeta failed, treating metadata as empty', e, st);
    return {};
  }
}

Future<void> savePhotoMeta(Map<String, PhotoMeta> meta) async {
  final file = await _photoMetaFile();
  await writeJsonFileAtomically(
    file,
    jsonEncode({
      for (final entry in meta.entries)
        if (!entry.value.isEmpty) entry.key: entry.value.toJson(),
    }),
  );
}
