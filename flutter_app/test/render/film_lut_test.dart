import 'dart:typed_data';

import 'package:darkmoon/render/film_lut.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A small, clearly non-identity table: swaps red and blue and lifts
/// green by a quarter.
FilmLut _swapLut(int size) {
  final data = Uint8List(size * size * size * 3);
  var k = 0;
  for (var b = 0; b < size; b++) {
    for (var g = 0; g < size; g++) {
      for (var r = 0; r < size; r++) {
        data[k++] = (b * 255 / (size - 1)).round();
        data[k++] = ((g / (size - 1)) * 0.75 * 255 + 0.25 * 255).round();
        data[k++] = (r * 255 / (size - 1)).round();
      }
    }
  }
  return FilmLut(size: size, data: data);
}

void main() {
  test('identity table leaves the buffer alone', () {
    final lut = FilmLut.identity(filmLutSize);
    expect(lut.isIdentity, isTrue);
    final buffer = Float32List.fromList([
      0,
      0,
      0,
      255,
      255,
      255,
      12.5,
      200,
      77,
      3,
      250,
      128,
    ]);
    final before = Float32List.fromList(buffer);
    applyFilmLut(buffer, lut, 1.0);
    for (var i = 0; i < buffer.length; i++) {
      expect(buffer[i], closeTo(before[i], 1.0), reason: 'index $i');
    }
  });

  test('trilinear lookup interpolates between entries', () {
    final lut = _swapLut(5);
    expect(lut.isIdentity, isFalse);
    final out = Float32List(3);
    lut.lookup(0.1, 0.5, 0.9, out, 0);
    expect(out[0], closeTo(0.9, 0.01));
    expect(out[1], closeTo(0.5 * 0.75 + 0.25, 0.01));
    expect(out[2], closeTo(0.1, 0.01));
  });

  test('amount blends toward the looked-up colour', () {
    final lut = _swapLut(5);
    final full = Float32List.fromList([255, 0, 0]);
    applyFilmLut(full, lut, 1.0);
    expect(full[0], closeTo(0, 1));
    expect(full[1], closeTo(64, 1));
    expect(full[2], closeTo(255, 1));
    final half = Float32List.fromList([255, 0, 0]);
    applyFilmLut(half, lut, 0.5);
    expect(half[0], closeTo(127.5, 1));
    expect(half[1], closeTo(32, 1));
    expect(half[2], closeTo(127.5, 1));
    final none = Float32List.fromList([255, 0, 0]);
    applyFilmLut(none, lut, 0.0);
    expect(none, [255, 0, 0]);
  });

  test('packed image round-trips the table', () {
    final lut = _swapLut(9);
    final packed = lut.toPacked();
    expect(packed.width, 81);
    expect(packed.height, 9);
    final back = FilmLut.fromPacked(
      img.decodePng(img.encodePng(packed))!,
      id: 7,
      name: 'swap',
    );
    expect(back.size, 9);
    expect(back.data, lut.data);
    expect(back.id, 7);
    expect(back.name, 'swap');
    // packedRgba is the same texels in RGBA, row-major.
    final rgba = lut.packedRgba();
    expect(rgba.length, 81 * 9 * 4);
    for (var y = 0; y < 9; y++) {
      for (var x = 0; x < 81; x++) {
        final px = packed.getPixel(x, y);
        final o = (y * 81 + x) * 4;
        expect(rgba[o], px.r);
        expect(rgba[o + 1], px.g);
        expect(rgba[o + 2], px.b);
        expect(rgba[o + 3], 255);
      }
    }
  });

  test('Hald CLUT parses in raster order', () {
    // Level 2: a 8x8 image holding a 4-per-axis table.
    final hald = img.Image(width: 8, height: 8);
    var k = 0;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final r = k % 4, g = (k ~/ 4) % 4, b = k ~/ 16;
        hald.setPixelRgb(x, y, b * 85, g * 85, r * 85); // swapped r/b
        k++;
      }
    }
    final lut = FilmLut.fromHald(hald);
    expect(lut.size, 4);
    final out = Float32List(3);
    lut.lookup(1.0, 0.0, 0.0, out, 0);
    expect(out, [0, 0, 1]);
    expect(
      () => FilmLut.fromHald(img.Image(width: 8, height: 6)),
      throwsFormatException,
    );
  });

  test('.cube parses size, domain and entries', () {
    final buf = StringBuffer()
      ..writeln('TITLE "Swap"')
      ..writeln('# comment')
      ..writeln('LUT_3D_SIZE 2')
      ..writeln('DOMAIN_MIN 0 0 0')
      ..writeln('DOMAIN_MAX 1 1 1');
    for (var b = 0; b < 2; b++) {
      for (var g = 0; g < 2; g++) {
        for (var r = 0; r < 2; r++) {
          buf.writeln('$b $g $r');
        }
      }
    }
    final lut = FilmLut.fromCube(buf.toString());
    expect(lut.size, 2);
    expect(lut.name, 'Swap');
    final out = Float32List(3);
    lut.lookup(1.0, 0.0, 0.5, out, 0);
    expect(out[0], closeTo(0.5, 0.01));
    expect(out[1], closeTo(0.0, 0.01));
    expect(out[2], closeTo(1.0, 0.01));
    expect(
      () => FilmLut.fromCube('LUT_3D_SIZE 2\n0 0 0\n'),
      throwsFormatException,
    );
    expect(() => FilmLut.fromCube('0 0 0\n'), throwsFormatException);
  });

  test('resampling a table keeps its mapping', () {
    final big = _swapLut(17);
    final small = big.resampled(5);
    expect(small.size, 5);
    final a = Float32List(3), b = Float32List(3);
    for (final c in [
      [0.2, 0.4, 0.6],
      [0.9, 0.1, 0.5],
      [0.0, 1.0, 0.0],
    ]) {
      big.lookup(c[0], c[1], c[2], a, 0);
      small.lookup(c[0], c[1], c[2], b, 0);
      for (var i = 0; i < 3; i++) {
        expect(b[i], closeTo(a[i], 0.01));
      }
    }
    expect(identical(big.resampled(17), big), isTrue);
  });
}
