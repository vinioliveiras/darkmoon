import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:darkmoon/raw_files.dart';

void main() {
  group('isRawFile / isCommonImageFile', () {
    test('recognizes RAW extensions case-insensitively', () {
      expect(isRawFile('photo.RAF'), isTrue);
      expect(isRawFile('photo.raf'), isTrue);
      expect(isRawFile('photo.CR2'), isTrue);
      expect(isRawFile('photo.dng'), isTrue);
    });

    test('recognizes common image extensions case-insensitively', () {
      expect(isCommonImageFile('photo.JPG'), isTrue);
      expect(isCommonImageFile('photo.jpeg'), isTrue);
      expect(isCommonImageFile('photo.PNG'), isTrue);
      expect(isCommonImageFile('photo.tiff'), isTrue);
      expect(isCommonImageFile('photo.webp'), isTrue);
    });

    test('a RAW extension is not a common image and vice versa', () {
      expect(isCommonImageFile('photo.raf'), isFalse);
      expect(isRawFile('photo.jpg'), isFalse);
    });

    test('an unsupported extension is neither', () {
      expect(isRawFile('notes.txt'), isFalse);
      expect(isCommonImageFile('notes.txt'), isFalse);
    });
  });

  group('RawFile', () {
    test('isRaw reflects the extension', () {
      final raw = RawFile('/x/photo.RAF', DateTime.now());
      final common = RawFile('/x/photo.jpg', DateTime.now());
      expect(raw.isRaw, isTrue);
      expect(common.isRaw, isFalse);
    });

    test('typeLabel is the uppercase extension without the dot', () {
      final raw = RawFile('/x/photo.raf', DateTime.now());
      final common = RawFile('/x/photo.jpeg', DateTime.now());
      expect(raw.typeLabel, 'RAF');
      expect(common.typeLabel, 'JPEG');
    });

    test('name is the basename', () {
      final file = RawFile('/a/b/photo.raf', DateTime.now());
      expect(file.name, 'photo.raf');
    });
  });

  group('listRawFiles', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('darkmoon_raw_test');
      for (final name in ['a.raf', 'b.jpg', 'c.png', 'd.txt', 'e.CR2']) {
        await File(p.join(tempDir.path, name)).writeAsBytes([0]);
      }
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('lists both RAW and common images by default', () async {
      final files = await listRawFiles(tempDir.path);
      final names = files.map((f) => f.name).toSet();
      expect(names, {'a.raf', 'b.jpg', 'c.png', 'e.CR2'});
      expect(names.contains('d.txt'), isFalse);
    });

    test('rawOnly excludes common image formats', () async {
      final files = await listRawFiles(tempDir.path, rawOnly: true);
      final names = files.map((f) => f.name).toSet();
      expect(names, {'a.raf', 'e.CR2'});
    });

    test('returns an empty list for a nonexistent folder', () async {
      final files = await listRawFiles(p.join(tempDir.path, 'nope'));
      expect(files, isEmpty);
    });

    test('ignores a subfolder by default', () async {
      final sub = Directory(p.join(tempDir.path, 'sub'))..createSync();
      await File(p.join(sub.path, 'nested.raf')).writeAsBytes([0]);
      final files = await listRawFiles(tempDir.path);
      final names = files.map((f) => f.name).toSet();
      expect(names.contains('nested.raf'), isFalse);
    });

    test('includeSubfolders descends into nested folders', () async {
      final sub = Directory(p.join(tempDir.path, 'sub'))..createSync();
      await File(p.join(sub.path, 'nested.raf')).writeAsBytes([0]);
      final files = await listRawFiles(tempDir.path, includeSubfolders: true);
      final names = files.map((f) => f.name).toSet();
      expect(names.contains('nested.raf'), isTrue);
      // Still finds the top-level files too, not just the nested ones.
      expect(names.contains('a.raf'), isTrue);
    });
  });
}
