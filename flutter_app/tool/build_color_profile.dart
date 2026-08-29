// Fits a "darkmoon Color" profile (lib/render/color_profile.dart) from
// pairs of the same RAW rendered neutrally in darkmoon and exported from
// Lightroom with the Adobe Color profile.
//
// For each pair the tool renders the RAW through darkmoon's neutral
// pipeline (all sliders 0, WB As Shot, no colour profile), lines it up
// with the Lightroom export, and measures the drift: a global tone curve
// (dm perceptual-luma -> Lightroom's) plus per-hue hue/sat/lum residuals.
//
// Prep in Lightroom: varied shots (skin, sky, foliage, vivid colour,
// shadow, high contrast), Profile = Adobe Color, every slider reset,
// WB = As Shot, tone curve Linear, export **16-bit TIFF or PNG** (JPEG
// adds a noise floor), sRGB, same filename as the RAW.
//
// Usage:
//   dart run tool/build_color_profile.dart <pairs-dir> [out.json] [name]
//
// Writes the profile JSON and, for the first pair,
// `<out>_before/after/reference.jpg` so the fit can be eyeballed —
// `_after` should look like `_reference`.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/native/edit_source.dart';
import 'package:darkmoon/render/color_profile.dart';
import 'package:darkmoon/render/color_space.dart';
import 'package:darkmoon/render/hsl.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const _maxDim = 1024; // colour stats don't need detail; keep it quick
const _rawExts = {'.raf', '.dng', '.nef', '.cr2', '.cr3', '.arw', '.rw2'};
const _refExts = {'.jpg', '.jpeg', '.png', '.tif', '.tiff'};

double _shortestAngle(double deg) {
  var d = deg % 360.0;
  if (d > 180.0) d -= 360.0;
  if (d < -180.0) d += 360.0;
  return d;
}

double _luma(double r, double g, double b) =>
    0.2126 * r + 0.7152 * g + 0.0722 * b;

double _lerpTable(List<double> t, double x) {
  final n = t.length;
  final f = x.clamp(0.0, 1.0) * (n - 1);
  final a = f.floor().clamp(0, n - 1);
  final b = math.min(a + 1, n - 1);
  return t[a] + (t[b] - t[a]) * (f - a);
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/build_color_profile.dart <pairs-dir> '
      '[out.json] [name]',
    );
    exit(1);
  }
  final dir = Directory(args[0]);
  if (!dir.existsSync()) {
    stderr.writeln('No such directory: ${args[0]}');
    exit(1);
  }
  final outPath = args.length > 1 ? args[1] : 'darkmoon_color_profile.json';
  final profileName = args.length > 2 ? args[2] : 'darkmoon Color';

  // Discover pairs.
  final pairs = <({String raw, String ref})>[];
  for (final entry in dir.listSync()) {
    if (entry is! File) continue;
    final ext = p.extension(entry.path).toLowerCase();
    if (!_rawExts.contains(ext)) continue;
    final stem = p.withoutExtension(entry.path);
    final ref = _refExts
        .map((e) => '$stem$e')
        .firstWhere((c) => File(c).existsSync(), orElse: () => '');
    if (ref.isEmpty) {
      stderr.writeln('  (no reference image for ${p.basename(entry.path)})');
      continue;
    }
    pairs.add((raw: entry.path, ref: ref));
  }
  if (pairs.isEmpty) {
    stderr.writeln('No <raw>+<image> pairs found in ${args[0]}');
    exit(1);
  }
  stdout.writeln('${pairs.length} pair(s) found.');

  // Tone curve: dm perceptual-luma -> mean lr perceptual-luma, over EVERY
  // lit pixel (grey included — the curve is the brightness/contrast match).
  const toneBins = 48;
  final toneLr = List<double>.filled(toneBins, 0);
  final toneN = List<double>.filled(toneBins, 0);

  // Per-hue-bin accumulators (saturated pixels only).
  final wSum = List<double>.filled(colorProfileBins, 0);
  final hueSum = List<double>.filled(colorProfileBins, 0);
  final satSum = List<double>.filled(colorProfileBins, 0);
  final binDmP = List<double>.filled(colorProfileBins, 0);
  final binLrP = List<double>.filled(colorProfileBins, 0);

  img.Image? firstDm;
  img.Image? firstRef;

  for (final pair in pairs) {
    stdout.write('  ${p.basename(pair.raw)} ... ');
    final sources = decodeEditSources(pair.raw, previewMaxDimension: _maxDim);
    if (sources == null) {
      stdout.writeln('decode failed, skipped');
      continue;
    }
    final src = sources.preview;
    // Neutral darkmoon render — colorProfile stays null here by design.
    final dm = renderRgb(
      src.width,
      src.height,
      src.rgbBytes,
      const RenderParams(),
    );

    var refRaw = img.decodeImage(File(pair.ref).readAsBytesSync());
    if (refRaw == null) {
      stdout.writeln('reference unreadable, skipped');
      continue;
    }
    // Lightroom's 16-bit TIFF/PNG exports come back as a 16-bit Image;
    // getBytes() would then hand back 2 bytes/channel and the `i += 3`
    // loop below reads pure garbage. Flatten to 8-bit sRGB-encoded here.
    if (refRaw.format != img.Format.uint8 || refRaw.numChannels != 3) {
      refRaw = refRaw.convert(format: img.Format.uint8, numChannels: 3);
    }
    final ref = img.copyResize(
      refRaw,
      width: src.width,
      height: src.height,
      interpolation: img.Interpolation.average,
    );
    final refBytes = ref.getBytes(order: img.ChannelOrder.rgb);

    var used = 0;
    for (var i = 0; i + 2 < dm.length && i + 2 < refBytes.length; i += 3) {
      final dr = srgbToLinear(dm[i] / 255.0);
      final dg = srgbToLinear(dm[i + 1] / 255.0);
      final db = srgbToLinear(dm[i + 2] / 255.0);
      final lr = srgbToLinear(refBytes[i] / 255.0);
      final lg = srgbToLinear(refBytes[i + 1] / 255.0);
      final lb = srgbToLinear(refBytes[i + 2] / 255.0);

      final dP = perceptualEncode(math.max(_luma(dr, dg, db), 1e-6));
      final lP = perceptualEncode(math.max(_luma(lr, lg, lb), 1e-6));
      if (dP < 0.02 || dP > 0.99 || lP > 0.995) continue; // black / clipped

      // Tone curve — every lit pixel.
      final tb = (dP * (toneBins - 1)).round().clamp(0, toneBins - 1);
      toneLr[tb] += lP;
      toneN[tb] += 1;

      final dHsv = rgbToHsv(dr, dg, db);
      final lHsv = rgbToHsv(lr, lg, lb);
      final dSat = dHsv[1];
      final lSat = lHsv[1];
      if (dSat < 0.07 || lSat < 0.05) continue; // hue is noise on greys

      final bin =
          (dHsv[0] / (360.0 / colorProfileBins)).round() % colorProfileBins;
      final weight = dSat; // more saturated -> more trustworthy

      wSum[bin] += weight;
      hueSum[bin] +=
          _shortestAngle(lHsv[0] - dHsv[0]).clamp(-60.0, 60.0) * weight;
      satSum[bin] += (lSat / math.max(dSat, 1e-3)).clamp(0.3, 3.0) * weight;
      binDmP[bin] += dP * weight;
      binLrP[bin] += lP * weight;
      used++;
    }
    stdout.writeln('$used samples');
    firstDm ??= img.Image.fromBytes(
      width: src.width,
      height: src.height,
      bytes: dm.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );
    firstRef ??= ref;
  }

  const damp = 0.9;

  // ---- Tone curve ----
  // Per tone-bin mean lr perceptual-luma; empty bins fall back to identity.
  final toneRaw = <double>[
    for (var t = 0; t < toneBins; t++)
      toneN[t] > 50 ? toneLr[t] / toneN[t] : t / (toneBins - 1),
  ];
  // Smooth, then force monotonic (a tone curve must never invert).
  var toneS = List<double>.from(toneRaw);
  for (var pass = 0; pass < 3; pass++) {
    final next = List<double>.from(toneS);
    for (var t = 1; t < toneBins - 1; t++) {
      next[t] = (toneS[t - 1] + 2 * toneS[t] + toneS[t + 1]) / 4.0;
    }
    toneS = next;
  }
  for (var t = 1; t < toneBins; t++) {
    if (toneS[t] < toneS[t - 1]) toneS[t] = toneS[t - 1];
  }
  // Resample to the profile's point count, damped toward identity.
  final tone = <double>[
    for (var k = 0; k < colorProfileTonePoints; k++)
      () {
        final x = k / (colorProfileTonePoints - 1);
        final f = (x * (toneBins - 1)).clamp(0.0, (toneBins - 1).toDouble());
        final a = f.floor();
        final bIdx = math.min(a + 1, toneBins - 1);
        final v = toneS[a] + (toneS[bIdx] - toneS[a]) * (f - a);
        return (x + (v - x) * damp).clamp(0.0, 1.0);
      }(),
  ];

  // ---- Per-hue table ----
  final minWeight = 200.0;
  final rawHue = List<double>.filled(colorProfileBins, 0);
  final rawSat = List<double>.filled(colorProfileBins, 1);
  final rawLum = List<double>.filled(colorProfileBins, 1);
  for (var b = 0; b < colorProfileBins; b++) {
    if (wSum[b] < minWeight) continue;
    rawHue[b] = hueSum[b] / wSum[b];
    rawSat[b] = satSum[b] / wSum[b];
    // lumMul is the residual AFTER the tone curve: what the curve predicts
    // for this bin's typical dm luma vs what Lightroom actually has.
    final dmPmean = binDmP[b] / wSum[b];
    final lrPmean = binLrP[b] / wSum[b];
    final predicted = _lerpTable(tone, dmPmean);
    rawLum[b] =
        perceptualDecode(lrPmean) / math.max(perceptualDecode(predicted), 1e-4);
  }

  List<double> smoothHue(List<double> a, double identity) {
    var cur = List<double>.from(a);
    for (var pass = 0; pass < 2; pass++) {
      final next = List<double>.filled(colorProfileBins, identity);
      for (var b = 0; b < colorProfileBins; b++) {
        final lft = cur[(b - 1 + colorProfileBins) % colorProfileBins];
        final rgt = cur[(b + 1) % colorProfileBins];
        next[b] = (lft + 2 * cur[b] + rgt) / 4.0;
      }
      cur = next;
    }
    return cur;
  }

  double dead(double v, double identity, double band) =>
      (v - identity).abs() < band ? identity : v;

  final hueShift = [
    for (final v in smoothHue(rawHue, 0)) dead(v * damp, 0, 1.5),
  ];
  final satMul = [
    for (final v in smoothHue(rawSat, 1)) dead(1.0 + (v - 1.0) * damp, 1, 0.04),
  ];
  final lumMul = [
    for (final v in smoothHue(rawLum, 1)) dead(1.0 + (v - 1.0) * damp, 1, 0.03),
  ];

  final profile = ColorProfile(
    tone: tone,
    hueShift: hueShift,
    satMul: satMul,
    lumMul: lumMul,
    name: profileName,
  );
  File(outPath).writeAsStringSync(profile.encode());

  stdout.writeln('\ntone curve (in / out, perceptual-luma):');
  for (var k = 0; k < colorProfileTonePoints; k += 4) {
    stdout.writeln(
      '  ${(k / (colorProfileTonePoints - 1)).toStringAsFixed(2)} -> '
      '${tone[k].toStringAsFixed(3)}',
    );
  }
  stdout.writeln('\nbin  hue°   satMul  lumMul   (bin i centres on i*15°)');
  for (var b = 0; b < colorProfileBins; b++) {
    stdout.writeln(
      '${b.toString().padLeft(2)}  '
      '${hueShift[b].toStringAsFixed(1).padLeft(5)}  '
      '${satMul[b].toStringAsFixed(3)}  '
      '${lumMul[b].toStringAsFixed(3)}',
    );
  }
  stdout.writeln('\nwrote $outPath');

  // Eyeball aids for the first pair — written to the CWD (not next to the
  // profile, which may live in assets/ where they'd get bundled).
  if (firstDm != null && firstRef != null) {
    final base = p.basenameWithoutExtension(outPath);
    img.encodeJpgFile('${base}_before.jpg', firstDm);

    final dmBytes = firstDm.getBytes(order: img.ChannelOrder.rgb);
    final buf = Float32List(dmBytes.length);
    for (var i = 0; i < dmBytes.length; i++) {
      buf[i] = dmBytes[i].toDouble();
    }
    applyColorProfile(buf, profile, 1.0);
    final after = Uint8List(dmBytes.length);
    for (var i = 0; i < after.length; i++) {
      after[i] = buf[i].clamp(0.0, 255.0).round();
    }
    img.encodeJpgFile(
      '${base}_after.jpg',
      img.Image.fromBytes(
        width: firstDm.width,
        height: firstDm.height,
        bytes: after.buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      ),
    );
    img.encodeJpgFile('${base}_reference.jpg', firstRef);
    stdout.writeln('wrote ${base}_before/after/reference.jpg');
  }
}
