// Fits a "darkmoon Color" profile (lib/render/color_profile.dart) from
// pairs of the same RAW rendered neutrally in darkmoon and exported from
// Meridian with the Adobe Color profile.
//
// For each pair the tool renders the RAW through darkmoon's neutral
// pipeline (all sliders 0, WB As Shot, no colour profile), lines it up
// with the Meridian export, and measures the per-hue hue/sat/lum drift.
//
// 2026-09-01: per-hue ONLY — the tone curve is forced to identity and no
// longer fit at all (see project_darkmoon_color_profile.md's full incident
// history: every real bug this profile ever caused traced back to that
// curve's brightness lift amplifying something else downstream). This
// version is also fit against whatever `libraw.dart`'s CURRENT
// `no_auto_bright` setting decodes with (today: auto-bright ON, matching
// darkmoon's normal/Default render) instead of requiring a separate global
// decode-time flag flip — so this profile only ever changes render-time
// per-hue color, never a photo's baseline exposure/decode, and applying it
// (gated to ColorProfileMode.vivid, never Default) can't regress anything
// outside that scope.
//
// Prep in Meridian: varied shots (skin, sky, foliage, vivid colour,
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

  // Per-hue-bin cross-pair accumulators (saturated pixels only). Each pair
  // contributes at most ONE vote per bin (its own weighted mean), not one
  // vote per pixel — same "equal weight per pair" fix already applied to
  // the old tone-curve fit (project_darkmoon_color_profile.md, 2026-08-31,
  // "5th round": a single very saturated/dominant photo was otherwise
  // free to outvote all 13 other pairs combined in whichever bin its own
  // colours happened to land in).
  final pairCount = List<double>.filled(colorProfileBins, 0);
  final hueSum = List<double>.filled(colorProfileBins, 0);
  final satSum = List<double>.filled(colorProfileBins, 0);
  final binDmP = List<double>.filled(colorProfileBins, 0);
  final binLrP = List<double>.filled(colorProfileBins, 0);
  const minPairWeightPerBin = 20.0;

  img.Image? firstDm;
  img.Image? firstRef;

  // Kept for the validation pass below (avoids re-decoding every RAW a
  // second time just to measure the fit).
  final pairsData = <({String name, Uint8List dm, Uint8List ref})>[];

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
    // Meridian's 16-bit TIFF/PNG exports come back as a 16-bit Image;
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
    final pairW = List<double>.filled(colorProfileBins, 0);
    final pairHue = List<double>.filled(colorProfileBins, 0);
    final pairSat = List<double>.filled(colorProfileBins, 0);
    final pairDmP = List<double>.filled(colorProfileBins, 0);
    final pairLrP = List<double>.filled(colorProfileBins, 0);
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

      final (dHue, dSat, _) = rgbToHsv(dr, dg, db);
      final (lHue, lSat, _) = rgbToHsv(lr, lg, lb);
      if (dSat < 0.07 || lSat < 0.05) continue; // hue is noise on greys

      final bin =
          (dHue / (360.0 / colorProfileBins)).round() % colorProfileBins;
      final weight = dSat; // more saturated -> more trustworthy

      pairW[bin] += weight;
      pairHue[bin] += _shortestAngle(lHue - dHue).clamp(-60.0, 60.0) * weight;
      pairSat[bin] += (lSat / math.max(dSat, 1e-3)).clamp(0.3, 3.0) * weight;
      pairDmP[bin] += dP * weight;
      pairLrP[bin] += lP * weight;
      used++;
    }
    // Fold this pair's own per-bin weighted mean into the cross-pair
    // accumulator — one vote per pair per bin, regardless of how many of
    // this pair's own pixels landed there (see pairCount's doc comment).
    for (var b = 0; b < colorProfileBins; b++) {
      if (pairW[b] < minPairWeightPerBin) continue;
      hueSum[b] += pairHue[b] / pairW[b];
      satSum[b] += pairSat[b] / pairW[b];
      binDmP[b] += pairDmP[b] / pairW[b];
      binLrP[b] += pairLrP[b] / pairW[b];
      pairCount[b] += 1;
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
    pairsData.add((name: p.basename(pair.raw), dm: dm, ref: refBytes));
  }

  // 2026-09-01: dropped from 0.9 (light damping) to 0.5 — the first
  // undamped-tone-curve fit blew out highlights on one pair (_DSF1202,
  // 330 newly-clipped pixels) and regressed several others; explicit
  // user request for a more aggressive reduction given that.
  const damp = 0.5;

  // ---- Tone curve ----
  // Forced identity (2026-09-01) — no longer fit at all. See this file's
  // header comment for why: every real bug this profile ever caused
  // traced back to the tone curve's brightness lift amplifying something
  // downstream. `lumMul` below still corrects per-hue brightness, just
  // without a global curve doing a first, much bigger pass first.
  final tone = identityColorProfile.tone;

  // ---- Per-hue table ----
  // A bin needs support from at least this many *pairs* (not pixels) —
  // one or two saturated photos alone can't define a bin's correction.
  const minPairsPerBin = 3.0;
  final rawHue = List<double>.filled(colorProfileBins, 0);
  final rawSat = List<double>.filled(colorProfileBins, 1);
  final rawLum = List<double>.filled(colorProfileBins, 1);
  for (var b = 0; b < colorProfileBins; b++) {
    if (pairCount[b] < minPairsPerBin) continue;
    rawHue[b] = hueSum[b] / pairCount[b];
    rawSat[b] = satSum[b] / pairCount[b];
    // lumMul is the residual: what this bin's typical dm luma predicts
    // (identity — the tone curve is gone) vs what Meridian actually has.
    final dmPmean = binDmP[b] / pairCount[b];
    final lrPmean = binLrP[b] / pairCount[b];
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
  // Same kind of hard safety ceiling as the tone curve: the per-bin
  // residual is measured from BIN MEANS (a coarser, noisier estimate than
  // the tone curve's own per-pixel fit), so it can swing further from
  // noise alone — cap it so a residual can never multiply brightness past
  // a sane range regardless of how it got there.
  final lumMul = [
    for (final v in smoothHue(rawLum, 1))
      dead(1.0 + (v - 1.0) * damp, 1, 0.03).clamp(0.85, 1.15),
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

  // ---- Validation against every pair, not just the first ----
  // Catches exactly last time's failure mode: a pair that gets WORSE after
  // correction (regression), or a jump in "went-to-white" pixels
  // (blowout) even if the mean error looks fine.
  stdout.writeln(
    '\nvalidation (mean abs error 0-255, all 3 channels; '
    '"went white" = pixels that crossed 250 that weren\'t there before):',
  );
  stdout.writeln(
    '  ${'pair'.padRight(20)} ${'before'.padLeft(7)} ${'after'.padLeft(7)}  '
    '${'Δ'.padLeft(6)}  went-white',
  );
  var worstRegression = 0.0;
  String? worstRegressionName;
  for (final d in pairsData) {
    final buf = Float32List(d.dm.length);
    for (var i = 0; i < d.dm.length; i++) {
      buf[i] = d.dm[i].toDouble();
    }
    applyColorProfile(buf, profile, 1.0);

    double beforeErr = 0, afterErr = 0;
    var wentWhite = 0;
    final n = math.min(d.dm.length, d.ref.length);
    for (var i = 0; i < n; i++) {
      final before = d.dm[i].toDouble();
      final after = buf[i].clamp(0.0, 255.0);
      final ref = d.ref[i].toDouble();
      beforeErr += (before - ref).abs();
      afterErr += (after - ref).abs();
      if (after >= 250 && before < 250 && ref < 250) wentWhite++;
    }
    beforeErr /= n;
    afterErr /= n;
    final delta = afterErr - beforeErr;
    if (delta > worstRegression) {
      worstRegression = delta;
      worstRegressionName = d.name;
    }
    stdout.writeln(
      '  ${d.name.padRight(20)} ${beforeErr.toStringAsFixed(1).padLeft(7)} '
      '${afterErr.toStringAsFixed(1).padLeft(7)}  '
      '${(delta >= 0 ? '+' : '')}${delta.toStringAsFixed(1).padLeft(5)}  '
      '$wentWhite px',
    );
  }
  if (worstRegressionName != null && worstRegression > 2.0) {
    stdout.writeln(
      '\n⚠ WORST REGRESSION: $worstRegressionName got '
      '${worstRegression.toStringAsFixed(1)}/255 WORSE after correction — '
      'do not ship this profile as-is.',
    );
  } else {
    stdout.writeln('\nNo pair regressed by more than 2/255 — looks safe.');
  }

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
