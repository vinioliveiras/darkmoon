// Fits a "darkmoon Color" profile (lib/render/color_profile.dart) from
// pairs of the same RAW rendered neutrally in darkmoon and in Lightroom
// with the Adobe Color profile.
//
// For each pair the tool renders the RAW through darkmoon's neutral
// pipeline (all sliders 0, WB As Shot, base contrast on — exactly the
// state `applyColorProfile` sees), lines it up with the Lightroom export,
// and per hue bin measures how far the hue/saturation/luminance drifted.
// The averaged drift becomes the correction table.
//
// Prep in Lightroom: select varied shots (skin, sky, foliage, vivid
// colour, shadow, high contrast), set Profile = Adobe Color, reset every
// slider, WB = As Shot, linear tone curve, then export sRGB JPEG named the
// same as the RAW.
//
// Usage:
//   dart run tool/build_color_profile.dart <pairs-dir> [out.json] [name]
//
// <pairs-dir> holds <stem>.RAF (or .raf/.dng/...) next to <stem>.jpg
// (or .jpeg/.png/.tif). Writes the profile JSON and, for the first pair,
// `<out>_before.jpg` / `<out>_after.jpg` next to a copy of the reference
// so the fit can be eyeballed.

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

  // Per-bin accumulators.
  final wSum = List<double>.filled(colorProfileBins, 0);
  final hueSum = List<double>.filled(colorProfileBins, 0);
  final satSum = List<double>.filled(colorProfileBins, 0);
  final lumSum = List<double>.filled(colorProfileBins, 0);

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

    final refRaw = img.decodeImage(File(pair.ref).readAsBytesSync());
    if (refRaw == null) {
      stdout.writeln('reference unreadable, skipped');
      continue;
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

      final dHsv = rgbToHsv(dr, dg, db);
      final lHsv = rgbToHsv(lr, lg, lb);
      final dSat = dHsv[1];
      final lSat = lHsv[1];
      // Unreliable hue on near-grey pixels, and clipped pixels lie.
      final dLumaV = _luma(dr, dg, db);
      if (dSat < 0.07 || lSat < 0.05) continue;
      if (dLumaV < 0.01 || dLumaV > 0.97) continue;

      final bin =
          (dHsv[0] / (360.0 / colorProfileBins)).round() % colorProfileBins;
      final weight = dSat; // more saturated -> more trustworthy

      final hueDiff = _shortestAngle(lHsv[0] - dHsv[0]).clamp(-60.0, 60.0);
      final satRatio = (lSat / math.max(dSat, 1e-3)).clamp(0.3, 3.0);
      final lLumaV = _luma(lr, lg, lb);
      final lumRatio = (lLumaV / math.max(dLumaV, 1e-3)).clamp(0.5, 2.0);

      wSum[bin] += weight;
      hueSum[bin] += hueDiff * weight;
      satSum[bin] += satRatio * weight;
      lumSum[bin] += lumRatio * weight;
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

  // Reduce to per-bin means; bins with little data stay identity.
  final minWeight = 200.0;
  final rawHue = List<double>.filled(colorProfileBins, 0);
  final rawSat = List<double>.filled(colorProfileBins, 1);
  final rawLum = List<double>.filled(colorProfileBins, 1);
  for (var b = 0; b < colorProfileBins; b++) {
    if (wSum[b] < minWeight) continue;
    rawHue[b] = hueSum[b] / wSum[b];
    rawSat[b] = satSum[b] / wSum[b];
    rawLum[b] = lumSum[b] / wSum[b];
  }

  // Circular 1-2-1 smooth, twice, then damp a touch so the profile guides
  // rather than fully forces (the fit is noisy and per-scene).
  List<double> smooth(List<double> a, double identity) {
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

  // Dead zone: corrections smaller than the fit's own noise floor (JPEG
  // artefacts, resample, gamut edges — a same-image pair still lands
  // ~±3°/±5%) snap back to identity so the profile only carries real drift.
  double dead(double v, double identity, double band) =>
      (v - identity).abs() < band ? identity : v;

  const damp = 0.9;
  final hueShift = [for (final v in smooth(rawHue, 0)) dead(v * damp, 0, 1.5)];
  final satMul = [
    for (final v in smooth(rawSat, 1)) dead(1.0 + (v - 1.0) * damp, 1, 0.04),
  ];
  final lumMul = [
    for (final v in smooth(rawLum, 1)) dead(1.0 + (v - 1.0) * damp, 1, 0.025),
  ];

  final profile = ColorProfile(
    hueShift: hueShift,
    satMul: satMul,
    lumMul: lumMul,
    name: profileName,
  );
  File(outPath).writeAsStringSync(profile.encode());

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

  // Eyeball aids for the first pair.
  if (firstDm != null && firstRef != null) {
    final base = p.withoutExtension(outPath);
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
