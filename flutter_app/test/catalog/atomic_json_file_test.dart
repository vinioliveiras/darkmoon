import 'dart:convert';
import 'dart:io';

import 'package:darkmoon/catalog/atomic_json_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('darkmoon_atomic_json_');
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('writeJsonFileAtomically', () {
    test('overlapping writes to one path land in order, last one wins, '
        'and no temp file is left behind', () async {
      final file = File(p.join(dir.path, 'store.json'));
      // Fired without awaiting one another — the shape of the editor's
      // debounced save racing a photo switch and a paste-edits.
      final writes = [
        for (var i = 0; i < 25; i++)
          writeJsonFileAtomically(file, jsonEncode({'n': i})),
      ];
      await Future.wait(writes);
      expect(jsonDecode(await file.readAsString()), {'n': 24});
      final leftovers = dir
          .listSync()
          .map((e) => p.basename(e.path))
          .where((name) => name != 'store.json')
          .toList();
      expect(leftovers, isEmpty, reason: 'temp files must be cleaned up');
    });

    test('two different paths do not wait on each other', () async {
      final a = File(p.join(dir.path, 'a.json'));
      final b = File(p.join(dir.path, 'b.json'));
      await Future.wait([
        writeJsonFileAtomically(a, '{"a":1}'),
        writeJsonFileAtomically(b, '{"b":2}'),
      ]);
      expect(await a.readAsString(), '{"a":1}');
      expect(await b.readAsString(), '{"b":2}');
    });

    test('a failed write reports its error and does not block the next '
        'write to the same path', () async {
      final nested = Directory(p.join(dir.path, 'missing'));
      final file = File(p.join(nested.path, 'store.json'));
      await expectLater(
        writeJsonFileAtomically(file, '{"first":true}'),
        throwsA(isA<FileSystemException>()),
      );
      await nested.create();
      await writeJsonFileAtomically(file, '{"second":true}');
      expect(await file.readAsString(), '{"second":true}');
    });
  });

  group('readJsonObject', () {
    test('a missing file reads as null without creating anything', () async {
      final file = File(p.join(dir.path, 'none.json'));
      expect(await readJsonObject(file, what: 'test'), isNull);
      expect(await file.exists(), isFalse);
    });

    test('a valid file comes back as its object', () async {
      final file = File(p.join(dir.path, 'ok.json'));
      await file.writeAsString('{"x": 1, "y": "two"}');
      expect(await readJsonObject(file, what: 'test'), {'x': 1, 'y': 'two'});
    });

    test('a corrupt file is moved aside, not left for the next save to '
        'overwrite', () async {
      final file = File(p.join(dir.path, 'store.json'));
      const damaged = '{"photo.cr2": {"Exposure": 1.5}, "oth';
      await file.writeAsString(damaged);

      expect(await readJsonObject(file, what: 'test'), isNull);

      expect(await file.exists(), isFalse, reason: 'the original is renamed');
      final quarantined = dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('store.json.corrupt-'))
          .toList();
      expect(quarantined, hasLength(1));
      expect(await quarantined.single.readAsString(), damaged);

      // The store's next save now creates a fresh file beside the
      // quarantined one instead of destroying the damaged original.
      await writeJsonFileAtomically(file, '{}');
      expect(await file.readAsString(), '{}');
      expect(await quarantined.single.exists(), isTrue);
    });

    test('a file holding valid JSON that is not an object is also '
        'quarantined', () async {
      final file = File(p.join(dir.path, 'list.json'));
      await file.writeAsString('[1, 2, 3]');
      expect(await readJsonObject(file, what: 'test'), isNull);
      expect(await file.exists(), isFalse);
    });
  });
}
