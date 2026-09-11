import 'dart:io';

import 'package:darkmoon/library/photo_mover.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late String source;
  late String target;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('darkmoon_mover_');
    source = p.join(dir.path, 'src');
    target = p.join(dir.path, 'dst');
    await Directory(source).create();
    await Directory(target).create();
    for (final name in ['a.jpg', 'b.jpg', 'c.jpg']) {
      await File(p.join(source, name)).writeAsString(name);
    }
    await File(p.join(source, 'a.xmp')).writeAsString('sidecar');
    await File(p.join(target, 'c.jpg')).writeAsString('already here');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('moves photos with their sidecars and never overwrites', () async {
    final outcome = await movePhotosToFolder([
      p.join(source, 'a.jpg'),
      p.join(source, 'b.jpg'),
      p.join(source, 'c.jpg'),
      p.join(target, 'b.jpg'), // already in the target: a no-op
    ], target);
    expect(outcome.moved, {
      p.join(source, 'a.jpg'): p.join(target, 'a.jpg'),
      p.join(source, 'b.jpg'): p.join(target, 'b.jpg'),
    });
    expect(outcome.skipped, [p.join(source, 'c.jpg')]);
    expect(await File(p.join(target, 'a.jpg')).readAsString(), 'a.jpg');
    expect(await File(p.join(target, 'a.xmp')).readAsString(), 'sidecar');
    expect(await File(p.join(source, 'a.jpg')).exists(), isFalse);
    expect(await File(p.join(source, 'a.xmp')).exists(), isFalse);
    expect(await File(p.join(source, 'c.jpg')).exists(), isTrue);
    expect(await File(p.join(target, 'c.jpg')).readAsString(), 'already here');
  });

  test(
    'moves a folder into another, refusing itself and its children',
    () async {
      final nested = p.join(source, 'inner');
      await Directory(nested).create();
      expect(await moveFolderInto(source, source), isNull);
      expect(await moveFolderInto(source, nested), isNull);
      // Already there: the folder's own path, nothing done.
      expect(await moveFolderInto(nested, source), nested);
      final moved = await moveFolderInto(nested, target);
      expect(moved, p.join(target, 'inner'));
      expect(await Directory(moved!).exists(), isTrue);
      expect(await Directory(nested).exists(), isFalse);
      // A second folder of the same name is refused, not merged.
      await Directory(nested).create();
      expect(await moveFolderInto(nested, target), isNull);
    },
  );

  test('creates an album folder, once', () async {
    final created = await createSubfolder(source, ' Trip ');
    expect(created, p.join(source, 'Trip'));
    expect(await Directory(created!).exists(), isTrue);
    expect(await createSubfolder(source, 'Trip'), isNull);
    expect(await createSubfolder(source, ''), isNull);
    expect(await createSubfolder(source, 'a/b'), isNull);
    expect(await createSubfolder(source, '..'), isNull);
  });

  test('rekeyUnderFolder rewrites paths under the moved folder only', () {
    final oldFolder = p.join('D:', 'photos', 'trip');
    final newFolder = p.join('D:', 'archive', 'trip');
    expect(
      rekeyUnderFolder(p.join(oldFolder, 'a.jpg'), oldFolder, newFolder),
      p.join(newFolder, 'a.jpg'),
    );
    expect(
      rekeyUnderFolder(p.join(oldFolder, 'x', 'b.jpg'), oldFolder, newFolder),
      p.join(newFolder, 'x', 'b.jpg'),
    );
    expect(rekeyUnderFolder(oldFolder, oldFolder, newFolder), newFolder);
    final other = p.join('D:', 'photos', 'tripping', 'c.jpg');
    expect(rekeyUnderFolder(other, oldFolder, newFolder), other);
  });
}
