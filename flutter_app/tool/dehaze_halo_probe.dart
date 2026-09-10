// ignore_for_file: avoid_print
// The band Dehaze paints along a skyline: a hazy sky beside a dark
// subject, Dehaze at 100, and how far the sky next to the edge drops
// below the open sky (and the subject next to it rises above the open
// subject), with the Gaussian regional blur and the guided one.
//
//   dart run tool/dehaze_halo_probe.dart [<raw-file> ...]
//
// With RAW files given, also reports how much the finished Dehaze (at 60)
// differs between the two bases on each file's embedded preview — the
// size of the look change, not a halo measurement.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/native/libraw.dart';
import 'package:darkmoon/render/calibration.dart';
import 'package:darkmoon/render/dehaze.dart';
import 'package:image/image.dart' as img;

const w = 480;
const h = 64;

Float32List _scene() {
  final img = Float32List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final sky = x < 240;
      final i = (y * w + x) * 3;
      img[i] = sky ? 196 : 48;
      img[i + 1] = sky ? 204 : 46;
      img[i + 2] = sky ? 216 : 50;
    }
  }
  return img;
}

void _run(String label, double threshold) {
  final img = _scene();
  final sw = Stopwatch()..start();
  applyDehaze(img, w, h, 100, 1.0, threshold);
  final ms = sw.elapsedMilliseconds;
  double luma(int x) {
    final i = (32 * w + x) * 3;
    return 0.2126 * img[i] + 0.7152 * img[i + 1] + 0.0722 * img[i + 2];
  }

  final openSky = luma(20);
  final openDark = luma(460);
  var skyUp = 0.0, skyDown = 0.0, darkUp = 0.0, darkDown = 0.0;
  var skyBand = 0, darkBand = 0;
  for (var x = 0; x < 240; x++) {
    final d = luma(x) - openSky;
    skyUp = math.max(skyUp, d);
    skyDown = math.max(skyDown, -d);
    if (d.abs() > 1) skyBand++;
  }
  for (var x = 240; x < w; x++) {
    final d = luma(x) - openDark;
    darkUp = math.max(darkUp, d);
    darkDown = math.max(darkDown, -d);
    if (d.abs() > 1) darkBand++;
  }
  print(
    '${label.padRight(16)} sky ${openSky.toStringAsFixed(1)} '
    '+${skyUp.toStringAsFixed(1)}/-${skyDown.toStringAsFixed(1)} '
    '(${skyBand}px) | dark ${openDark.toStringAsFixed(1)} '
    '+${darkUp.toStringAsFixed(1)}/-${darkDown.toStringAsFixed(1)} '
    '(${darkBand}px)  ${ms}ms',
  );
}

void _photo(String path) {
  const releaseDir = 'build/windows/x64/runner/Release';
  for (final dll in ['raw_r.dll', 'vcomp140.dll']) {
    if (!File(dll).existsSync() && File('$releaseDir/$dll').existsSync()) {
      File('$releaseDir/$dll').copySync(dll);
    }
  }
  final jpeg = extractRawThumbnailJpeg(path);
  final decoded = jpeg == null ? null : img.decodeJpg(jpeg);
  if (decoded == null) {
    print('$path: no embedded preview');
    return;
  }
  final small = img.copyResize(decoded, width: 1200);
  final rgb = small.getBytes(order: img.ChannelOrder.rgb);
  final pw = small.width, ph = small.height;
  Float32List run(double threshold) {
    final f = Float32List(rgb.length);
    for (var i = 0; i < rgb.length; i++) {
      f[i] = rgb[i].toDouble();
    }
    applyDehaze(f, pw, ph, 60, 1.0, threshold);
    return f;
  }

  final gaussian = run(0);
  final guided = run(calDehazeEdgeThreshold);
  final diffs = <double>[];
  var sum = 0.0;
  for (var i = 0; i < gaussian.length; i++) {
    final d = (gaussian[i] - guided[i]).abs();
    sum += d;
    diffs.add(d);
  }
  diffs.sort();
  final name = path.split(RegExp(r'[\\/]')).last;
  print(
    '${name.padRight(16)} Dehaze 60, Gaussian vs guided thr '
    '$calDehazeEdgeThreshold: mean ${(sum / diffs.length).toStringAsFixed(2)} '
    'p99 ${diffs[(diffs.length * 0.99).floor()].toStringAsFixed(1)} '
    'max ${diffs.last.toStringAsFixed(1)}',
  );
}

void main(List<String> args) {
  _run('gaussian', 0);
  for (final t in [6.0, 8.0, 10.0, 12.0, 15.0]) {
    _run('guided thr $t', t);
  }
  for (final path in args) {
    _photo(path);
  }
}
