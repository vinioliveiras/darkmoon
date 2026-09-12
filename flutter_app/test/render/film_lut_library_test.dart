import 'dart:io';

import 'package:darkmoon/render/film_lut.dart';
import 'package:darkmoon/render/film_lut_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// A 2-entry .cube that swaps red and blue.
const _swapCube = '''
TITLE "Swap RB"
LUT_3D_SIZE 2
0 0 0
0 0 1
0 1 0
0 1 1
1 0 0
1 0 1
1 1 0
1 1 1
''';

/// A level-2 Hald CLUT (8x8, 4 entries per axis) that inverts red.
img.Image _invertRedHald() {
  const level = 2, n = level * level, side = level * level * level;
  final image = img.Image(width: side, height: side, numChannels: 3);
  var i = 0;
  for (var b = 0; b < n; b++) {
    for (var g = 0; g < n; g++) {
      for (var r = 0; r < n; r++, i++) {
        image.setPixelRgb(
          i % side,
          i ~/ side,
          255 - (r * 255 / (n - 1)).round(),
          (g * 255 / (n - 1)).round(),
          (b * 255 / (n - 1)).round(),
        );
      }
    }
  }
  return image;
}

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('darkmoon_luts');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('imports a .cube, resampled to the film size under a user id', () async {
    final cube = File(p.join(dir.path, 'swap.cube'))
      ..writeAsStringSync(_swapCube);
    final library = FilmLutLibrary.empty(
      userDir: Directory(p.join(dir.path, 'luts')),
    );
    final entry = await library.importFile(cube.path);
    expect(entry.id, FilmLutLibrary.userIdBase);
    expect(entry.name, 'Swap RB');
    expect(entry.isUser, isTrue);
    expect(entry.label, 'Swap RB');
    final lut = library.byId(entry.id)!;
    expect(lut.size, filmLutSize);
    // Pure red maps to pure blue.
    final o = ((filmLutSize - 1)) * 3;
    expect(lut.data[o], 0);
    expect(lut.data[o + 2], 255);
    expect(
      File(p.join(dir.path, 'luts', 'user_1000.png')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(dir.path, 'luts', 'manifest.json')).existsSync(),
      isTrue,
    );
  });

  test(
    'imports a Hald CLUT image and numbers it after the last import',
    () async {
      final hald = File(p.join(dir.path, 'invert red.png'))
        ..writeAsBytesSync(img.encodePng(_invertRedHald()));
      final userDir = Directory(p.join(dir.path, 'luts'));
      final library = FilmLutLibrary.empty(userDir: userDir);
      File(p.join(dir.path, 'a.cube')).writeAsStringSync(_swapCube);
      await library.importFile(p.join(dir.path, 'a.cube'));
      final entry = await library.importFile(hald.path);
      expect(entry.id, FilmLutLibrary.userIdBase + 1);
      expect(entry.name, 'invert red');
      final lut = library.byId(entry.id)!;
      expect(lut.size, filmLutSize);
      // Black maps to red.
      expect(lut.data[0], 255);
      expect(lut.data[1], 0);
      expect(library.entries.map((e) => e.id), [1000, 1001]);

      // A fresh library reads both back from the manifest.
      final again = FilmLutLibrary.empty(userDir: userDir);
      await again.loadUser();
      expect(again.entries.map((e) => e.name), ['Swap RB', 'invert red']);
      expect(again.byId(1001)!.data[0], 255);
      expect(again.nextUserId, 1002);
    },
  );

  test(
    'refuses files that are not tables, and a library with no home',
    () async {
      final junk = File(p.join(dir.path, 'notes.cube'))
        ..writeAsStringSync('hello');
      final library = FilmLutLibrary.empty(
        userDir: Directory(p.join(dir.path, 'luts')),
      );
      expect(() => library.importFile(junk.path), throwsFormatException);
      final photo = File(p.join(dir.path, 'photo.png'))
        ..writeAsBytesSync(img.encodePng(img.Image(width: 10, height: 6)));
      expect(() => library.importFile(photo.path), throwsFormatException);
      expect(library.entries, isEmpty);
      expect(
        () => FilmLutLibrary.empty().importFile(junk.path),
        throwsStateError,
      );
    },
  );
}
