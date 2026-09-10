// ignore_for_file: avoid_print
// How far the RAW decode sits from the camera's own rendering, per file:
// mean luma, how much of the frame the decode has already clipped, and
// the exposure offset the camera match would ask for. Used to judge
// decode-time brightness decisions (LibRaw's auto-bright, 2026-09-10)
// on real files instead of on a flat patch.
//
//   dart run tool/decode_brightness_probe.dart <raw-file> [<raw-file> ...]
//
// Needs raw_r.dll beside the working directory (copied from the Release
// build, same as tool/wb_dump.dart).
import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/native/camera_match.dart';
import 'package:darkmoon/native/libraw.dart';
import 'package:darkmoon/render/color_space.dart';
import 'package:image/image.dart' as img;

({double meanLuma, double meanLinear, double clippedAny, double clippedAll})
_stats(Uint8List rgb) {
  final pixels = rgb.length ~/ 3;
  var luma = 0.0;
  var linear = 0.0;
  var any = 0;
  var all = 0;
  for (var p = 0; p < pixels; p++) {
    final i = p * 3;
    final r = rgb[i], g = rgb[i + 1], b = rgb[i + 2];
    luma += 0.2126 * r + 0.7152 * g + 0.0722 * b;
    linear +=
        0.2126 * srgbToLinear(r / 255.0) +
        0.7152 * srgbToLinear(g / 255.0) +
        0.0722 * srgbToLinear(b / 255.0);
    if (r >= 254 || g >= 254 || b >= 254) any++;
    if (r >= 254 && g >= 254 && b >= 254) all++;
  }
  return (
    meanLuma: luma / pixels,
    meanLinear: linear / pixels,
    clippedAny: any / pixels * 100,
    clippedAll: all / pixels * 100,
  );
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/decode_brightness_probe.dart <raw>...',
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
    '${'file'.padRight(16)} ${'decode mean'.padLeft(11)} ${'lin'.padLeft(6)} '
    '${'clip any%'.padLeft(9)} ${'clip all%'.padLeft(9)} | '
    '${'camera mean'.padLeft(11)} ${'lin'.padLeft(6)} ${'clip any%'.padLeft(9)} | '
    '${'offset'.padLeft(7)}',
  );
  for (final path in args) {
    final decoded = decodeRawImage(path, fastPreview: false);
    if (decoded == null) {
      print('${path.padRight(16)} decode failed');
      continue;
    }
    final d = _stats(decoded.rgbBytes);
    final embedded = extractRawThumbnailJpeg(path);
    String camera = '(no embedded JPEG)';
    String offset = '-';
    if (embedded != null) {
      final jpeg = img.decodeJpg(embedded);
      if (jpeg != null) {
        final c = _stats(jpeg.getBytes(order: img.ChannelOrder.rgb));
        camera =
            '${c.meanLuma.toStringAsFixed(1).padLeft(11)} '
            '${c.meanLinear.toStringAsFixed(3).padLeft(6)} '
            '${c.clippedAny.toStringAsFixed(2).padLeft(9)}';
      }
      final match = measureCameraMatch(
        decoded.rgbBytes,
        decoded.width,
        decoded.height,
        embedded,
      );
      offset = match.stops == null
          ? 'null'
          : '${match.stops! >= 0 ? '+' : ''}${match.stops!.toStringAsFixed(2)}';
    }
    final name = path.split(RegExp(r'[\\/]')).last;
    print(
      '${name.padRight(16)} ${d.meanLuma.toStringAsFixed(1).padLeft(11)} '
      '${d.meanLinear.toStringAsFixed(3).padLeft(6)} '
      '${d.clippedAny.toStringAsFixed(2).padLeft(9)} '
      '${d.clippedAll.toStringAsFixed(2).padLeft(9)} | $camera | '
      '${offset.padLeft(7)}',
    );
  }
}
