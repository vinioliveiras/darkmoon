import 'dart:io';

import 'package:darkmoon/catalog/legacy_filename_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('migrateLegacyFilename', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'darkmoon_migration_test',
      );
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('renames the old file to the new name when only the old one '
        'exists', () async {
      final oldFile = File(p.join(tempDir.path, 'flutter_catalog.json'));
      await oldFile.writeAsString('{"a": 1}');

      await migrateLegacyFilename(
        tempDir,
        'flutter_catalog.json',
        'darkmoon_catalog.json',
      );

      expect(await oldFile.exists(), isFalse);
      final newFile = File(p.join(tempDir.path, 'darkmoon_catalog.json'));
      expect(await newFile.exists(), isTrue);
      expect(await newFile.readAsString(), '{"a": 1}');
    });

    test('does nothing when the new file already exists', () async {
      final oldFile = File(p.join(tempDir.path, 'flutter_catalog.json'));
      await oldFile.writeAsString('{"old": true}');
      final newFile = File(p.join(tempDir.path, 'darkmoon_catalog.json'));
      await newFile.writeAsString('{"new": true}');

      await migrateLegacyFilename(
        tempDir,
        'flutter_catalog.json',
        'darkmoon_catalog.json',
      );

      // The already-current file is never overwritten by a stale old one.
      expect(await newFile.readAsString(), '{"new": true}');
      expect(await oldFile.exists(), isTrue);
    });

    test('does nothing when neither file exists', () async {
      await migrateLegacyFilename(
        tempDir,
        'flutter_catalog.json',
        'darkmoon_catalog.json',
      );

      final newFile = File(p.join(tempDir.path, 'darkmoon_catalog.json'));
      expect(await newFile.exists(), isFalse);
    });
  });
}
