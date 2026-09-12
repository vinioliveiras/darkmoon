// Builds the bundled film tables in assets/film_luts/ from the RawTherapee
// Film Simulation Collection (CC BY-SA 4.0, Pat David / Pavlov Dmitry /
// Michael Ezra — https://rawtherapee.com/shared/HaldCLUT.zip).
//
// Each Hald CLUT (level 12 = 144 entries per axis, 1728x1728 PNG) is
// resampled to filmLutSize^3 and written in film_lut.dart's packed
// layout, plus a manifest.json the app reads to list them. The push/pull
// variants in the collection are numbered (`1 -`, `2`, `3 +`, `4 ++`);
// only the normal-exposure one of each stock is bundled.
//
// Usage:
//   dart run tool/build_film_luts.dart <extracted HaldCLUT dir>

import 'dart:convert';
import 'dart:io';

import 'package:darkmoon/render/film_lut.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class _Stock {
  const _Stock(this.id, this.file, this.name, this.brand, this.kind);
  final int id;
  final String file; // relative to the HaldCLUT dir
  final String name;
  final String brand;
  final String kind; // negative | slide | instant | bw
}

/// Ids are stable forever: a photo or preset stores the id, so a renumber
/// would silently change which film every saved edit means. Append only.
const _stocks = [
  _Stock(
    1,
    'Color/Kodak/Kodak Portra 160 2.png',
    'Portra 160',
    'Kodak',
    'negative',
  ),
  _Stock(
    2,
    'Color/Kodak/Kodak Portra 400 2.png',
    'Portra 400',
    'Kodak',
    'negative',
  ),
  _Stock(
    3,
    'Color/Kodak/Kodak Portra 800 2.png',
    'Portra 800',
    'Kodak',
    'negative',
  ),
  _Stock(
    4,
    'Color/Kodak/Kodak Ektar 100.png',
    'Ektar 100',
    'Kodak',
    'negative',
  ),
  _Stock(
    5,
    'Color/Kodak/Kodak Kodachrome 64.png',
    'Kodachrome 64',
    'Kodak',
    'slide',
  ),
  _Stock(
    6,
    'Color/Kodak/Kodak Ektachrome 100 VS.png',
    'Ektachrome 100 VS',
    'Kodak',
    'slide',
  ),
  _Stock(7, 'Color/Fuji/Fuji Velvia 50.png', 'Velvia 50', 'Fuji', 'slide'),
  _Stock(8, 'Color/Fuji/Fuji Provia 100F.png', 'Provia 100F', 'Fuji', 'slide'),
  _Stock(9, 'Color/Fuji/Fuji Astia 100F.png', 'Astia 100F', 'Fuji', 'slide'),
  _Stock(
    10,
    'Color/Fuji/Fuji Superia 200.png',
    'Superia 200',
    'Fuji',
    'negative',
  ),
  _Stock(
    11,
    'Color/Fuji/Fuji Superia 400 2.png',
    'Superia 400',
    'Fuji',
    'negative',
  ),
  _Stock(12, 'Color/Agfa/Agfa Vista 200.png', 'Vista 200', 'Agfa', 'negative'),
  _Stock(13, 'Color/Polaroid/Polaroid 690 3.png', '690', 'Polaroid', 'instant'),
  _Stock(
    14,
    'Black-and-White/Kodak/Kodak TRI-X 400 2.png',
    'Tri-X 400',
    'Kodak',
    'bw',
  ),
  _Stock(
    15,
    'Black-and-White/Ilford/Ilford HP5 Plus 400.png',
    'HP5 Plus 400',
    'Ilford',
    'bw',
  ),
];

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/build_film_luts.dart <HaldCLUT dir>');
    exit(2);
  }
  final srcDir = args[0];
  final outDir = p.join('assets', 'film_luts');
  Directory(outDir).createSync(recursive: true);
  final manifest = <Map<String, Object>>[];
  for (final stock in _stocks) {
    final path = p.join(srcDir, stock.file);
    final image = img.decodePng(File(path).readAsBytesSync());
    if (image == null) {
      stderr.writeln('cannot decode $path');
      exit(1);
    }
    final full = FilmLut.fromHald(image);
    final small = full.resampled(filmLutSize);
    final fileName = 'film_${stock.id.toString().padLeft(2, '0')}.png';
    final png = img.encodePng(small.toPacked(), level: 9);
    File(p.join(outDir, fileName)).writeAsBytesSync(png);
    manifest.add({
      'id': stock.id,
      'file': fileName,
      'name': stock.name,
      'brand': stock.brand,
      'kind': stock.kind,
    });
    stdout.writeln(
      '${stock.brand} ${stock.name}: ${full.size}^3 -> ${small.size}^3, '
      '${png.length ~/ 1024} KB',
    );
  }
  File(p.join(outDir, 'manifest.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'source':
          'RawTherapee Film Simulation Collection (Pat David, Pavlov Dmitry, '
          'Michael Ezra), CC BY-SA 4.0, resampled to $filmLutSize^3',
      'films': manifest,
    }),
  );
  stdout.writeln('wrote ${manifest.length} films to $outDir');
}
