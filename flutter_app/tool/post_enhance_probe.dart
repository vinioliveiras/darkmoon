// Runs the "apply to the edited photo" post-render pass
// (lib/render/post_enhance.dart) once on a real crop, with noise added,
// and reports what it did: mean absolute change against the noisy input,
// residual noise (mean absolute difference to the clean crop) before and
// after, and the wall time — the same models the editor loads, so this
// is the pass's end-to-end check outside the app.
//
// Usage:
//   dart run tool/post_enhance_probe.dart [image] [size]
// Defaults: assets/splash/featured.jpg, a 512 px centred crop.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/render/post_enhance.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final imagePath = args.isNotEmpty ? args[0] : 'assets/splash/featured.jpg';
  final size = args.length > 1 ? int.parse(args[1]) : 512;
  final decoded = img.decodeImage(File(imagePath).readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode $imagePath');
    exit(2);
  }
  final full = decoded.convert(format: img.Format.uint8, numChannels: 3);
  final x0 = math.max(0, (full.width - size) ~/ 2);
  final y0 = math.max(0, (full.height - size) ~/ 2);
  final w = math.min(size, full.width), h = math.min(size, full.height);
  final crop = img.copyCrop(full, x: x0, y: y0, width: w, height: h);
  final clean = crop.getBytes(order: img.ChannelOrder.rgb);
  final rng = math.Random(7);
  final noisy = Uint8List(clean.length);
  for (var i = 0; i < clean.length; i++) {
    noisy[i] = (clean[i] + (rng.nextDouble() * 2 - 1) * 24).round().clamp(
      0,
      255,
    );
  }
  double mad(Uint8List a, Uint8List b) {
    var s = 0.0;
    for (var i = 0; i < a.length; i++) {
      s += (a[i] - b[i]).abs();
    }
    return s / a.length;
  }

  const spec = PostEnhanceSpec(
    denoise: true,
    denoiseStrength: 1.0,
    restoreDetail: true,
    restoreAmount: 0.5,
    detailSharpen: false,
    sharpenAmount: 0.5,
  );
  final sw = Stopwatch()..start();
  final out = applyPostEnhance(noisy, w, h, spec);
  sw.stop();
  stdout.writeln('crop ${w}x$h, ${sw.elapsedMilliseconds} ms');
  stdout.writeln(
    'noise vs clean: before ${mad(noisy, clean).toStringAsFixed(2)}, '
    'after ${mad(out, clean).toStringAsFixed(2)}',
  );
  stdout.writeln(
    'change vs noisy input: ${mad(out, noisy).toStringAsFixed(2)}',
  );
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: out.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final outPath = 'build/post_enhance_probe.png';
  File(outPath).writeAsBytesSync(img.encodePng(image));
  stdout.writeln('wrote $outPath');
}
