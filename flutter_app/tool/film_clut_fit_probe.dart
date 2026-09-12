// Measures how well a "darkmoon Color" profile (24 hue bins + 33-point
// tone curve, lib/render/color_profile.dart) can stand in for a film
// HaldCLUT, and how much a 3D LUT loses when subsampled to 33^3 / 17^3.
//
// For each CLUT given on the command line: apply it (trilinear) to a real
// photo, fit a ColorProfile to (input -> CLUT output) the way
// build_color_profile.dart does (tone curve on luma, per-hue hue/sat/lum
// from bin means, no damping), apply the fitted profile to the same photo
// and report the colour error against the CLUT output in CIE76 dE (Lab).
//
// Usage:
//   dart run tool/film_clut_fit_probe.dart <photo.jpg> <clut.png> [more...]
// Env: DARKMOON_PROBE_OUT=<dir> dumps <film>_{input,clut,profile}.jpg.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/render/color_profile.dart';
import 'package:darkmoon/render/color_space.dart';
import 'package:darkmoon/render/hsl.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const _maxDim = 900;

class Clut {
  Clut(this.size, this.data);
  final int size; // entries per axis
  final Float32List data; // size^3 * 3, index = (r + g*size + b*size^2)*3

  static Clut fromHald(img.Image im) {
    final total = im.width * im.height;
    final size = math.pow(total, 1 / 3).round();
    if (size * size * size != total) {
      throw StateError('not a Hald CLUT: ${im.width}x${im.height}');
    }
    final data = Float32List(total * 3);
    var k = 0;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final px = im.getPixel(x, y);
        data[k++] = px.rNormalized.toDouble();
        data[k++] = px.gNormalized.toDouble();
        data[k++] = px.bNormalized.toDouble();
      }
    }
    return Clut(size, data);
  }

  /// Trilinear lookup, inputs 0..1 sRGB.
  void lookup(double r, double g, double b, Float32List out, int o) {
    final n = size - 1;
    final fr = r.clamp(0.0, 1.0) * n;
    final fg = g.clamp(0.0, 1.0) * n;
    final fb = b.clamp(0.0, 1.0) * n;
    final r0 = fr.floor().clamp(0, n);
    final g0 = fg.floor().clamp(0, n);
    final b0 = fb.floor().clamp(0, n);
    final r1 = math.min(r0 + 1, n);
    final g1 = math.min(g0 + 1, n);
    final b1 = math.min(b0 + 1, n);
    final tr = fr - r0, tg = fg - g0, tb = fb - b0;
    for (var c = 0; c < 3; c++) {
      double at(int ri, int gi, int bi) =>
          data[(ri + gi * size + bi * size * size) * 3 + c];
      final c00 = at(r0, g0, b0) * (1 - tr) + at(r1, g0, b0) * tr;
      final c10 = at(r0, g1, b0) * (1 - tr) + at(r1, g1, b0) * tr;
      final c01 = at(r0, g0, b1) * (1 - tr) + at(r1, g0, b1) * tr;
      final c11 = at(r0, g1, b1) * (1 - tr) + at(r1, g1, b1) * tr;
      final c0 = c00 * (1 - tg) + c10 * tg;
      final c1 = c01 * (1 - tg) + c11 * tg;
      out[o + c] = c0 * (1 - tb) + c1 * tb;
    }
  }

  /// Resamples to [newSize] entries per axis (what a GPU texture would hold).
  Clut resample(int newSize) {
    final data = Float32List(newSize * newSize * newSize * 3);
    final tmp = Float32List(3);
    var k = 0;
    for (var bi = 0; bi < newSize; bi++) {
      for (var gi = 0; gi < newSize; gi++) {
        for (var ri = 0; ri < newSize; ri++) {
          lookup(
            ri / (newSize - 1),
            gi / (newSize - 1),
            bi / (newSize - 1),
            tmp,
            0,
          );
          data[k++] = tmp[0];
          data[k++] = tmp[1];
          data[k++] = tmp[2];
        }
      }
    }
    return Clut(newSize, data);
  }
}

// --- CIE Lab (D65) from sRGB 0..1 --------------------------------------
List<double> _lab(double r, double g, double b) {
  final rl = srgbToLinear(r), gl = srgbToLinear(g), bl = srgbToLinear(b);
  var x = (0.4124 * rl + 0.3576 * gl + 0.1805 * bl) / 0.95047;
  var y = (0.2126 * rl + 0.7152 * gl + 0.0722 * bl);
  var z = (0.0193 * rl + 0.1192 * gl + 0.9505 * bl) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  x = f(x);
  y = f(y);
  z = f(z);
  return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
}

double _dE(Float32List a, Float32List b, int i) {
  final la = _lab(a[i], a[i + 1], a[i + 2]);
  final lb = _lab(b[i], b[i + 1], b[i + 2]);
  final d0 = la[0] - lb[0], d1 = la[1] - lb[1], d2 = la[2] - lb[2];
  return math.sqrt(d0 * d0 + d1 * d1 + d2 * d2);
}

class _Stats {
  _Stats(List<double> v) {
    v.sort();
    mean = v.fold(0.0, (a, b) => a + b) / v.length;
    p95 = v[(v.length * 0.95).floor().clamp(0, v.length - 1)];
    max = v.last;
  }
  late final double mean, p95, max;
  @override
  String toString() =>
      'mean ${mean.toStringAsFixed(2)}  p95 ${p95.toStringAsFixed(2)}  '
      'max ${max.toStringAsFixed(2)}';
}

double _linearLuma(double r, double g, double b) =>
    0.2126 * r + 0.7152 * g + 0.0722 * b;

double _lerp(List<double> tb, double x) {
  final f = x.clamp(0.0, 1.0) * (tb.length - 1);
  final a = f.floor().clamp(0, tb.length - 1);
  final c = (a + 1).clamp(0, tb.length - 1);
  return tb[a] + (tb[c] - tb[a]) * (f - a);
}

/// Fits a ColorProfile mapping [src] -> [dst] (both 0..1 sRGB).
ColorProfile _fit(Float32List src, Float32List dst) {
  const n = colorProfileTonePoints;
  final toneSum = List.filled(n, 0.0), toneW = List.filled(n, 0.0);
  final toneAllSum = List.filled(n, 0.0), toneAllW = List.filled(n, 0.0);
  final hueSum = List.filled(colorProfileBins, 0.0);
  final satSum = List.filled(colorProfileBins, 0.0);
  final lumSum = List.filled(colorProfileBins, 0.0);
  final binW = List.filled(colorProfileBins, 0.0);
  final count = src.length ~/ 3;
  for (var i = 0; i < count; i++) {
    final r = srgbToLinear(src[i * 3]), g = srgbToLinear(src[i * 3 + 1]);
    final b = srgbToLinear(src[i * 3 + 2]);
    final r2 = srgbToLinear(dst[i * 3]), g2 = srgbToLinear(dst[i * 3 + 1]);
    final b2 = srgbToLinear(dst[i * 3 + 2]);
    final pIn = perceptualEncode(math.max(_linearLuma(r, g, b), 1e-6));
    final pOut = perceptualEncode(math.max(_linearLuma(r2, g2, b2), 1e-6));
    // The tone curve is what neutral pixels get (the per-hue lumMul only
    // reaches saturated ones), so fit it on the near-neutral population
    // and let lumMul carry the colour-dependent part; fall back to every
    // pixel where a luma bin has no neutrals.
    final (_, s, _) = rgbToHsv(r, g, b);
    final neutral = 1.0 - ((s - 0.04) / 0.14).clamp(0.0, 1.0);
    final f = pIn * (n - 1);
    final i0 = f.floor().clamp(0, n - 1), i1 = (i0 + 1).clamp(0, n - 1);
    final t = f - i0;
    toneSum[i0] += pOut * (1 - t) * neutral;
    toneW[i0] += (1 - t) * neutral;
    toneSum[i1] += pOut * t * neutral;
    toneW[i1] += t * neutral;
    toneAllSum[i0] += pOut * (1 - t);
    toneAllW[i0] += 1 - t;
    toneAllSum[i1] += pOut * t;
    toneAllW[i1] += t;
  }
  final tone = [
    for (var k = 0; k < n; k++)
      toneW[k] > 30
          ? toneSum[k] / toneW[k]
          : (toneAllW[k] > 0 ? toneAllSum[k] / toneAllW[k] : k / (n - 1)),
  ];
  // Per-hue residuals after the tone curve, weighted by the same
  // saturation gate applyColorProfile uses.
  for (var i = 0; i < count; i++) {
    final r = srgbToLinear(src[i * 3]), g = srgbToLinear(src[i * 3 + 1]);
    final b = srgbToLinear(src[i * 3 + 2]);
    final r2 = srgbToLinear(dst[i * 3]), g2 = srgbToLinear(dst[i * 3 + 1]);
    final b2 = srgbToLinear(dst[i * 3 + 2]);
    final (h, s, _) = rgbToHsv(r, g, b);
    final (h2, s2, _) = rgbToHsv(r2, g2, b2);
    if (s < 0.04) continue;
    final w = ((s - 0.04) / 0.14).clamp(0.0, 1.0);
    var dh = h2 - h;
    if (dh > 180) dh -= 360;
    if (dh < -180) dh += 360;
    final lumIn = math.max(_linearLuma(r, g, b), 1e-6);
    final lumPred = perceptualDecode(_lerp(tone, perceptualEncode(lumIn)));
    final lumOut = math.max(_linearLuma(r2, g2, b2), 1e-6);
    final bin = (h / (360 / colorProfileBins)).floor() % colorProfileBins;
    hueSum[bin] += dh * w;
    satSum[bin] += (s2 / math.max(s, 1e-4)) * w;
    lumSum[bin] += (lumOut / lumPred) * w;
    binW[bin] += w;
  }
  final hueShift = List.filled(colorProfileBins, 0.0);
  final satMul = List.filled(colorProfileBins, 1.0);
  final lumMul = List.filled(colorProfileBins, 1.0);
  for (var b = 0; b < colorProfileBins; b++) {
    if (binW[b] < 20) continue;
    hueShift[b] = hueSum[b] / binW[b];
    satMul[b] = satSum[b] / binW[b];
    lumMul[b] = lumSum[b] / binW[b];
  }
  return ColorProfile(
    tone: tone,
    hueShift: hueShift,
    satMul: satMul,
    lumMul: lumMul,
  );
}

Float32List _applyClut(Clut c, Float32List src) {
  final out = Float32List(src.length);
  for (var i = 0; i < src.length; i += 3) {
    c.lookup(src[i], src[i + 1], src[i + 2], out, i);
  }
  return out;
}

Float32List _applyProfile(ColorProfile prof, Float32List src) {
  final buf = Float32List(src.length);
  for (var i = 0; i < src.length; i++) {
    buf[i] = src[i] * 255.0;
  }
  applyColorProfile(buf, prof, 1.0);
  for (var i = 0; i < buf.length; i++) {
    buf[i] = (buf[i] / 255.0).clamp(0.0, 1.0);
  }
  return buf;
}

void _dump(String path, Float32List px, int w, int h) {
  final im = img.Image(width: w, height: h);
  var k = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(
        x,
        y,
        (px[k] * 255).round(),
        (px[k + 1] * 255).round(),
        (px[k + 2] * 255).round(),
      );
      k += 3;
    }
  }
  File(path).writeAsBytesSync(img.encodeJpg(im, quality: 92));
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: <photo> <clut.png> [more...]');
    exit(2);
  }
  var photo = img.decodeImage(File(args[0]).readAsBytesSync())!;
  if (math.max(photo.width, photo.height) > _maxDim) {
    photo = photo.width >= photo.height
        ? img.copyResize(photo, width: _maxDim)
        : img.copyResize(photo, height: _maxDim);
  }
  final w = photo.width, h = photo.height;
  final src = Float32List(w * h * 3);
  var k = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = photo.getPixel(x, y);
      src[k++] = px.rNormalized.toDouble();
      src[k++] = px.gNormalized.toDouble();
      src[k++] = px.bNormalized.toDouble();
    }
  }
  final outDir = Platform.environment['DARKMOON_PROBE_OUT'];
  stdout.writeln('photo ${p.basename(args[0])} ${w}x$h, ${w * h} px');
  stdout.writeln(
    'dE (CIE76): look = CLUT vs input; profile = fitted 24-bin profile vs '
    'CLUT; lut33/lut17 = resampled CLUT vs full CLUT',
  );
  // Fitter self-test: a target that IS a per-hue profile must be
  // recovered almost entirely, else the film numbers below mean nothing.
  {
    final vivid = ColorProfile.decode(
      File('assets/color_profiles/darkmoon_vivid.json').readAsStringSync(),
    );
    final target = _applyProfile(vivid, src);
    final refit = _applyProfile(_fit(src, target), src);
    final look = <double>[], res = <double>[];
    for (var i = 0; i < w * h; i += 2) {
      look.add(_dE(target, src, i * 3));
      res.add(_dE(target, refit, i * 3));
    }
    final sL = _Stats(look), sR = _Stats(res);
    stdout.writeln(
      'self-test (vivid profile as target): look $sL | refit residual $sR '
      '| recovers ${((1 - sR.mean / sL.mean) * 100).toStringAsFixed(0)}%',
    );
  }
  for (final clutPath in args.skip(1)) {
    final name = p.basenameWithoutExtension(clutPath);
    final clut = Clut.fromHald(
      img.decodePng(File(clutPath).readAsBytesSync())!,
    );
    final target = _applyClut(clut, src);
    final prof = _fit(src, target);
    final viaProfile = _applyProfile(prof, src);
    final via33 = _applyClut(clut.resample(33), src);
    final via17 = _applyClut(clut.resample(17), src);
    final count = w * h;
    final look = <double>[], eProf = <double>[], e33 = <double>[];
    final e17 = <double>[], moved = <double>[];
    for (var i = 0; i < count; i += 2) {
      moved.add(_dE(viaProfile, src, i * 3));
      look.add(_dE(target, src, i * 3));
      eProf.add(_dE(target, viaProfile, i * 3));
      e33.add(_dE(target, via33, i * 3));
      e17.add(_dE(target, via17, i * 3));
    }
    final sL = _Stats(look), sP = _Stats(eProf), s33 = _Stats(e33);
    final s17 = _Stats(e17);
    stdout.writeln('');
    stdout.writeln('== $name (${clut.size}^3)');
    stdout.writeln('  look     $sL');
    stdout.writeln(
      '  profile  $sP   recovers '
      '${((1 - sP.mean / sL.mean) * 100).toStringAsFixed(0)}% of the look',
    );
    stdout.writeln('  profile moved the input by ${_Stats(moved)}');
    stdout.writeln('  lut33    $s33');
    stdout.writeln('  lut17    $s17');
    if (Platform.environment['DARKMOON_PROBE_DUMP_PROFILE'] != null) {
      stdout.writeln(prof.encode());
      // Residual split: neutral vs saturated input pixels, and the grey
      // axis of the CLUT vs the fitted tone curve.
      final eN = <double>[], eS = <double>[];
      for (var i = 0; i < count; i += 2) {
        final o = i * 3;
        final (_, sat, _) = rgbToHsv(
          srgbToLinear(src[o]),
          srgbToLinear(src[o + 1]),
          srgbToLinear(src[o + 2]),
        );
        (sat < 0.1 ? eN : eS).add(_dE(target, viaProfile, o));
      }
      stdout.writeln('  residual neutral(${eN.length}) ${_Stats(eN)}');
      stdout.writeln('  residual saturated(${eS.length}) ${_Stats(eS)}');
      final tmp = Float32List(3);
      for (final gv in [0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 0.9]) {
        clut.lookup(gv, gv, gv, tmp, 0);
        final lIn = _lab(gv, gv, gv)[0];
        final lOut = _lab(tmp[0], tmp[1], tmp[2])[0];
        final pIn = perceptualEncode(srgbToLinear(gv));
        final pFit = _lerp(prof.tone, pIn);
        final lFit = _lab(
          linearToSrgb(perceptualDecode(pFit)),
          linearToSrgb(perceptualDecode(pFit)),
          linearToSrgb(perceptualDecode(pFit)),
        )[0];
        stdout.writeln(
          '  grey $gv: L ${lIn.toStringAsFixed(1)} -> clut '
          '${lOut.toStringAsFixed(1)} / fit ${lFit.toStringAsFixed(1)}',
        );
      }
    }
    // Neutral-axis cast: what the CLUT does to greys (a profile cannot).
    final tmp = Float32List(3);
    final casts = <String>[];
    for (final gv in [0.1, 0.3, 0.5, 0.7, 0.9]) {
      clut.lookup(gv, gv, gv, tmp, 0);
      final lab = _lab(tmp[0], tmp[1], tmp[2]);
      casts.add(
        '${gv.toStringAsFixed(1)}:a${lab[1].toStringAsFixed(1)}'
        '/b${lab[2].toStringAsFixed(1)}',
      );
    }
    stdout.writeln('  grey cast (Lab a/b at grey levels): ${casts.join('  ')}');
    if (outDir != null) {
      Directory(outDir).createSync(recursive: true);
      _dump(p.join(outDir, '${name}_input.jpg'), src, w, h);
      _dump(p.join(outDir, '${name}_clut.jpg'), target, w, h);
      _dump(p.join(outDir, '${name}_profile.jpg'), viaProfile, w, h);
    }
  }
}
