// ignore_for_file: avoid_print
// Halo and texture response of applyLocalContrast's two bases — the
// Gaussian one and the guided (edge-preserving) one — on synthetic
// frames: a step edge (halo = over/undershoot beside the edge) and
// sinusoidal textures (amplitude gain = the effect Clarity is for).
//
//   dart run tool/clarity_halo_probe.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/render/local_contrast.dart';

const w = 320;
const h = 64;

Float32List _gray(double Function(int x, int y) f) {
  final img = Float32List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = f(x, y);
      final i = (y * w + x) * 3;
      img[i] = v;
      img[i + 1] = v;
      img[i + 2] = v;
    }
  }
  return img;
}

void _run(String label, double sigma, double threshold) {
  final sw = Stopwatch()..start();
  // Step edge 60 | 200 at x = 160.
  final step = _gray((x, y) => x < 160 ? 60.0 : 200.0);
  applyLocalContrast(
    step,
    w,
    h,
    65,
    sigma,
    protectMidtones: true,
    edgeThreshold: threshold,
  );
  var over = 0.0, under = 0.0;
  for (var x = 0; x < w; x++) {
    final v = step[(32 * w + x) * 3];
    over = math.max(over, v - 200);
    under = math.max(under, 60 - v);
  }
  final ms = sw.elapsedMilliseconds;
  final gains = <String>[];
  for (final period in [8, 20, 60, 160]) {
    final tex = _gray((x, y) => 128 + 20 * math.sin(2 * math.pi * x / period));
    applyLocalContrast(
      tex,
      w,
      h,
      65,
      sigma,
      protectMidtones: true,
      edgeThreshold: threshold,
    );
    var lo = 255.0, hi = 0.0;
    for (var x = 40; x < w - 40; x++) {
      final v = tex[(32 * w + x) * 3];
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    gains.add('p$period ${((hi - lo) / 40).toStringAsFixed(2)}');
  }
  print(
    '${label.padRight(28)} halo +${over.toStringAsFixed(1)}/-'
    '${under.toStringAsFixed(1)}  gain ${gains.join('  ')}  ${ms}ms',
  );
}

void main() {
  _run('gaussian sigma 25', 25, 0);
  for (final t in [12.0, 20.0, 30.0, 45.0]) {
    _run('guided sigma 25 thr $t', 25, t);
  }
}
