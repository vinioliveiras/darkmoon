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
  // 16-57 added 2026-09-13 (more of the popular stocks). Still one
  // normal-exposure table per stock; ids append-only as above.
  _Stock(
    16,
    'Color/Kodak/Kodak Portra 400 NC 2.png',
    'Portra 400 NC',
    'Kodak',
    'negative',
  ),
  _Stock(
    17,
    'Color/Kodak/Kodak Portra 400 VC 2.png',
    'Portra 400 VC',
    'Kodak',
    'negative',
  ),
  _Stock(
    18,
    'Color/Kodak/Kodak Portra 400 UC 2.png',
    'Portra 400 UC',
    'Kodak',
    'negative',
  ),
  _Stock(
    19,
    'Color/Kodak/Kodak E-100 GX Ektachrome 100.png',
    'Ektachrome E100 GX',
    'Kodak',
    'slide',
  ),
  _Stock(
    20,
    'Color/Kodak/Kodak Elite Chrome 200.png',
    'Elite Chrome 200',
    'Kodak',
    'slide',
  ),
  _Stock(
    21,
    'Color/Kodak/Kodak Elite Chrome 400.png',
    'Elite Chrome 400',
    'Kodak',
    'slide',
  ),
  _Stock(
    22,
    'Color/Kodak/Kodak Kodachrome 25.png',
    'Kodachrome 25',
    'Kodak',
    'slide',
  ),
  _Stock(
    23,
    'Color/Kodak/Kodak Kodachrome 200.png',
    'Kodachrome 200',
    'Kodak',
    'slide',
  ),
  _Stock(
    24,
    'Color/Fuji/Fuji Superia 100 2.png',
    'Superia 100',
    'Fuji',
    'negative',
  ),
  _Stock(
    25,
    'Color/Fuji/Fuji Superia 800 2.png',
    'Superia 800',
    'Fuji',
    'negative',
  ),
  _Stock(
    26,
    'Color/Fuji/Fuji Superia 1600 2.png',
    'Superia 1600',
    'Fuji',
    'negative',
  ),
  _Stock(
    27,
    'Color/Fuji/Fuji Superia X-Tra 800.png',
    'Superia X-Tra 800',
    'Fuji',
    'negative',
  ),
  _Stock(
    28,
    'Color/Fuji/Fuji Superia Reala 100.png',
    'Superia Reala 100',
    'Fuji',
    'negative',
  ),
  _Stock(29, 'Color/Fuji/Fuji 160C 2.png', 'Pro 160C', 'Fuji', 'negative'),
  _Stock(30, 'Color/Fuji/Fuji 400H 2.png', 'Pro 400H', 'Fuji', 'negative'),
  _Stock(31, 'Color/Fuji/Fuji 800Z 2.png', 'Pro 800Z', 'Fuji', 'negative'),
  _Stock(32, 'Color/Fuji/Fuji Sensia 100.png', 'Sensia 100', 'Fuji', 'slide'),
  _Stock(
    33,
    'Color/Fuji/Fuji Velvia 100 Generic.png',
    'Velvia 100',
    'Fuji',
    'slide',
  ),
  _Stock(34, 'Color/Fuji/Fuji Provia 400X.png', 'Provia 400X', 'Fuji', 'slide'),
  _Stock(35, 'Color/Fuji/Fuji FP-100c 3.png', 'FP-100C', 'Fuji', 'instant'),
  _Stock(36, 'Color/Agfa/Agfa Precisa 100.png', 'Precisa 100', 'Agfa', 'slide'),
  _Stock(
    37,
    'Color/Agfa/Agfa Ultra Color 100.png',
    'Ultra Color 100',
    'Agfa',
    'negative',
  ),
  _Stock(
    38,
    'Color/Lomography/Lomography X-Pro Slide 200.png',
    'X-Pro Slide 200',
    'Lomography',
    'slide',
  ),
  _Stock(
    39,
    'Color/Lomography/Lomography Redscale 100.png',
    'Redscale 100',
    'Lomography',
    'negative',
  ),
  _Stock(40, 'Color/Polaroid/Polaroid 669 3.png', '669', 'Polaroid', 'instant'),
  _Stock(
    41,
    'Color/Polaroid/Polaroid PX-70 3.png',
    'PX-70',
    'Polaroid',
    'instant',
  ),
  _Stock(
    42,
    'Color/Polaroid/Polaroid PX-680 3.png',
    'PX-680',
    'Polaroid',
    'instant',
  ),
  _Stock(
    43,
    'Black-and-White/Ilford/Ilford Delta 100.png',
    'Delta 100',
    'Ilford',
    'bw',
  ),
  _Stock(
    44,
    'Black-and-White/Ilford/Ilford Delta 400.png',
    'Delta 400',
    'Ilford',
    'bw',
  ),
  _Stock(
    45,
    'Black-and-White/Ilford/Ilford Delta 3200 2.png',
    'Delta 3200',
    'Ilford',
    'bw',
  ),
  _Stock(
    46,
    'Black-and-White/Ilford/Ilford FP4 Plus 125.png',
    'FP4 Plus 125',
    'Ilford',
    'bw',
  ),
  _Stock(
    47,
    'Black-and-White/Ilford/Ilford Pan F Plus 50.png',
    'Pan F Plus 50',
    'Ilford',
    'bw',
  ),
  _Stock(
    48,
    'Black-and-White/Ilford/Ilford XP2.png',
    'XP2 Super',
    'Ilford',
    'bw',
  ),
  _Stock(
    49,
    'Black-and-White/Kodak/Kodak T-Max 100.png',
    'T-Max 100',
    'Kodak',
    'bw',
  ),
  _Stock(
    50,
    'Black-and-White/Kodak/Kodak T-Max 400.png',
    'T-Max 400',
    'Kodak',
    'bw',
  ),
  _Stock(
    51,
    'Black-and-White/Kodak/Kodak TMAX 3200 2.png',
    'T-Max 3200',
    'Kodak',
    'bw',
  ),
  _Stock(
    52,
    'Black-and-White/Fuji/Fuji Neopan Acros 100.png',
    'Neopan Acros 100',
    'Fuji',
    'bw',
  ),
  _Stock(
    53,
    'Black-and-White/Fuji/Fuji Neopan 1600 2.png',
    'Neopan 1600',
    'Fuji',
    'bw',
  ),
  _Stock(54, 'Black-and-White/Agfa/Agfa APX 100.png', 'APX 100', 'Agfa', 'bw'),
  _Stock(55, 'Black-and-White/Agfa/Agfa APX 25.png', 'APX 25', 'Agfa', 'bw'),
  _Stock(
    56,
    'Black-and-White/Rollei/Rollei Retro 80s.png',
    'Retro 80s',
    'Rollei',
    'bw',
  ),
  _Stock(
    57,
    'Black-and-White/Polaroid/Polaroid 665 3.png',
    '665',
    'Polaroid',
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
  // The dropdown shows manifest order: brand, then kind, then name — the
  // ids stay whatever they are.
  const kindOrder = ['negative', 'slide', 'instant', 'bw'];
  manifest.sort((a, b) {
    final brand = (a['brand'] as String).compareTo(b['brand'] as String);
    if (brand != 0) return brand;
    final kind = kindOrder
        .indexOf(a['kind'] as String)
        .compareTo(kindOrder.indexOf(b['kind'] as String));
    if (kind != 0) return kind;
    return (a['name'] as String).compareTo(b['name'] as String);
  });
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
