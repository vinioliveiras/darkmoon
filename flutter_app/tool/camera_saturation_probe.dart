// ignore_for_file: avoid_print
// How much colour the RAW decode and darkmoon's own default rendering
// carry next to the camera's embedded JPEG of the same shot: mean HSV
// saturation of each, and the ratio the camera match would spend as a
// base saturation (2026-09-12, user's report that a RAW opens less
// saturated than the camera's JPEG).
//
//   dart run tool/camera_saturation_probe.dart <raw-file> [<raw-file> ...]
//
// Needs raw_r.dll beside the working directory (copied from the Release
// build, same as tool/decode_brightness_probe.dart).
import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/native/camera_match.dart';
import 'package:darkmoon/native/libraw.dart';
import 'package:darkmoon/render/color_profile.dart';
import 'package:darkmoon/render/hsl.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:image/image.dart' as img;

/// Mean HSV saturation over the pixels bright enough to carry colour, and
/// the mean chroma (max - min) in 0..1, sampled on a stride.
({double sat, double chroma, int counted}) _colour(Uint8List rgb) {
  final pixels = rgb.length ~/ 3;
  final stride = pixels <= 400000 ? 1 : (pixels / 400000).ceil();
  var sat = 0.0, chroma = 0.0;
  var counted = 0;
  for (var p = 0; p < pixels; p += stride) {
    final i = p * 3;
    final r = rgb[i] / 255.0, g = rgb[i + 1] / 255.0, b = rgb[i + 2] / 255.0;
    final (_, s, v) = rgbToHsv(r, g, b);
    if (v < 0.05) continue;
    sat += s;
    chroma += s * v;
    counted++;
  }
  if (counted == 0) return (sat: 0, chroma: 0, counted: 0);
  return (sat: sat / counted, chroma: chroma / counted, counted: counted);
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/camera_saturation_probe.dart <raw>...',
    );
    exit(1);
  }
  const releaseDir = 'build/windows/x64/runner/Release';
  for (final dll in ['raw_r.dll', 'vcomp140.dll']) {
    if (!File(dll).existsSync() && File('$releaseDir/$dll').existsSync()) {
      File('$releaseDir/$dll').copySync(dll);
    }
  }
  print(
    '${'file'.padRight(18)} ${'decode S'.padLeft(9)} ${'render S'.padLeft(9)} '
    '${'camera S'.padLeft(9)} ${'cam/render'.padLeft(10)} | '
    '${'decode C'.padLeft(9)} ${'render C'.padLeft(9)} ${'camera C'.padLeft(9)} '
    '${'cam/render'.padLeft(10)} | stops  tone',
  );
  for (final path in args) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final decoded = decodeRawImage(path, fastPreview: true);
    if (decoded == null) {
      print('${name.padRight(18)} decode failed');
      continue;
    }
    final embedded = extractRawThumbnailJpeg(path);
    final jpeg = embedded == null ? null : img.decodeJpg(embedded);
    if (jpeg == null) {
      print('${name.padRight(18)} no embedded JPEG');
      continue;
    }
    final match = measureCameraMatch(
      decoded.rgbBytes,
      decoded.width,
      decoded.height,
      embedded,
    );
    final meta = extractRawMetadata(path);
    // darkmoon's default look: the camera's tone curve in the profile's
    // tone slot, no per-hue correction, no S-curve — what _colorProfileFor
    // and _baseContrastFor produce in the default colour mode.
    final profile = match.tone == null
        ? null
        : ColorProfile(
            tone: match.tone!,
            hueShift: identityColorProfile.hueShift,
            satMul: identityColorProfile.satMul,
            lumMul: identityColorProfile.lumMul,
            name: 'camera',
          );
    final params = RenderParams.fromValues(
      const {},
      asShotKelvin: meta?.asShotKelvin ?? 5500,
      asShotTint: meta?.asShotTint ?? 0,
      baseExposureStops: match.tone != null ? 0 : (match.stops ?? 0),
      baseContrast: 0,
      colorProfile: profile,
    );
    final rendered = renderRgb(
      decoded.width,
      decoded.height,
      decoded.rgbBytes,
      params,
    );
    final d = _colour(decoded.rgbBytes);
    final r = _colour(rendered);
    final cameraRgb = jpeg.getBytes(order: img.ChannelOrder.rgb);
    final c = _colour(cameraRgb);
    // With the colour fit riding the profile's hue/sat/lum slots: what the
    // photo opens as since 2026-09-12.
    final fit = match.color;
    final fitted = fit == null
        ? rendered
        : renderRgb(
            decoded.width,
            decoded.height,
            decoded.rgbBytes,
            RenderParams.fromValues(
              const {},
              asShotKelvin: meta?.asShotKelvin ?? 5500,
              asShotTint: meta?.asShotTint ?? 0,
              baseContrast: 0,
              colorProfile: ColorProfile(
                tone: match.tone ?? identityColorProfile.tone,
                hueShift: fit.hueShift,
                satMul: fit.satMul,
                lumMul: fit.lumMul,
                name: 'camera',
              ),
            ),
          );
    final fb = _byHue(fitted);
    final fc = _colour(fitted);
    // Per hue bin (12 of 30 degrees) and by percentile: a matched mean can
    // hide a camera that pushes the strong colours and spares the rest.
    final rb = _byHue(rendered);
    final cb = _byHue(cameraRgb);
    final hueLine = StringBuffer('    per hue (cam S / render S, weight%): ');
    for (var i = 0; i < 12; i++) {
      final ratioB = rb.sat[i] <= 0 ? double.nan : cb.sat[i] / rb.sat[i];
      hueLine.write(
        '${(i * 30).toString().padLeft(3)}°=${ratioB.toStringAsFixed(2)}'
        '(${(100 * rb.count[i] / rb.total).toStringAsFixed(0)}%) ',
      );
    }
    final rp = _percentiles(rendered);
    final cp = _percentiles(cameraRgb);
    final pLine =
        '    S percentiles render p50/p75/p90/p97: '
        '${rp.map((v) => v.toStringAsFixed(2)).join('/')}  camera: '
        '${cp.map((v) => v.toStringAsFixed(2)).join('/')}';
    String f(double v) => v.toStringAsFixed(3).padLeft(9);
    String ratio(double a, double b) =>
        (b <= 0 ? double.nan : a / b).toStringAsFixed(3).padLeft(10);
    print(
      '${name.padRight(18)} ${f(d.sat)} ${f(r.sat)} ${f(c.sat)} '
      '${ratio(c.sat, r.sat)} | ${f(d.chroma)} ${f(r.chroma)} ${f(c.chroma)} '
      '${ratio(c.chroma, r.chroma)} | '
      '${match.stops == null ? '  -  ' : match.stops!.toStringAsFixed(2).padLeft(5)}  '
      '${match.tone == null ? 'none' : 'yes'}',
    );
    print(hueLine);
    print(pLine);
    if (fit == null) {
      print('    colour fit: refused');
    } else {
      final after = StringBuffer(
        '    after fit (cam S / fitted S): mean ${(c.sat / fc.sat).toStringAsFixed(3)}  ',
      );
      for (var i = 0; i < 12; i++) {
        final ratioB = fb.sat[i] <= 0 ? double.nan : cb.sat[i] / fb.sat[i];
        after.write(
          '${(i * 30).toString().padLeft(3)}°=${ratioB.toStringAsFixed(2)} ',
        );
      }
      print(after);
      final satLine = StringBuffer('    fit satMul per 15°: ');
      for (final v in fit.satMul) {
        satLine.write('${v.toStringAsFixed(2)} ');
      }
      print(satLine);
      final hueShiftLine = StringBuffer('    fit hueShift per 15°: ');
      for (final v in fit.hueShift) {
        hueShiftLine.write('${v.toStringAsFixed(0)} ');
      }
      print(hueShiftLine);
      final lumLine = StringBuffer('    fit lumMul per 15°: ');
      for (final v in fit.lumMul) {
        lumLine.write('${v.toStringAsFixed(2)} ');
      }
      print(lumLine);
      final out = Platform.environment['DARKMOON_PROBE_OUT'];
      if (out != null) {
        _writePpm(
          '$out/${name}_render.ppm',
          rendered,
          decoded.width,
          decoded.height,
        );
        _writePpm(
          '$out/${name}_fitted.ppm',
          fitted,
          decoded.width,
          decoded.height,
        );
        _writePpm(
          '$out/${name}_camera.ppm',
          cameraRgb,
          jpeg.width,
          jpeg.height,
        );
      }
    }
  }
}

void _writePpm(String path, Uint8List rgb, int width, int height) {
  final header = 'P6 $width $height 255\n'.codeUnits;
  File(path).writeAsBytesSync([...header, ...rgb]);
}

({List<double> sat, List<int> count, int total}) _byHue(Uint8List rgb) {
  final sat = List<double>.filled(12, 0);
  final count = List<int>.filled(12, 0);
  final pixels = rgb.length ~/ 3;
  final stride = pixels <= 400000 ? 1 : (pixels / 400000).ceil();
  var total = 0;
  for (var p = 0; p < pixels; p += stride) {
    final i = p * 3;
    final (h, s, v) = rgbToHsv(
      rgb[i] / 255.0,
      rgb[i + 1] / 255.0,
      rgb[i + 2] / 255.0,
    );
    if (v < 0.05 || s < 0.04) continue;
    final bin = ((h % 360) / 30).floor().clamp(0, 11);
    sat[bin] += s;
    count[bin]++;
    total++;
  }
  return (
    sat: [for (var i = 0; i < 12; i++) count[i] == 0 ? 0.0 : sat[i] / count[i]],
    count: count,
    total: total == 0 ? 1 : total,
  );
}

List<double> _percentiles(Uint8List rgb) {
  final pixels = rgb.length ~/ 3;
  final stride = pixels <= 400000 ? 1 : (pixels / 400000).ceil();
  final values = <double>[];
  for (var p = 0; p < pixels; p += stride) {
    final i = p * 3;
    final (_, s, v) = rgbToHsv(
      rgb[i] / 255.0,
      rgb[i + 1] / 255.0,
      rgb[i + 2] / 255.0,
    );
    if (v < 0.05) continue;
    values.add(s);
  }
  values.sort();
  if (values.isEmpty) return [0, 0, 0, 0];
  double at(double q) => values[((values.length - 1) * q).round()];
  return [at(0.5), at(0.75), at(0.9), at(0.97)];
}
