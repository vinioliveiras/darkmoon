// End-to-end smoke test: real LibRaw FFI + real PMRID ONNX model on a real
// RAW file — proves the raw-domain denoise pipeline (pmrid_raw.dart's
// pack/unpack, libraw.dart's decodeRawImageWithPmridDenoise,
// pmrid_denoise.dart's tiling) actually works against real native code,
// not just unit-tested pure-Dart math.
//
// Usage: dart run tool/pmrid_raw_smoke_test.dart [rawFile]
import 'dart:io';

import 'package:darkmoon/native/libraw.dart';
import 'package:darkmoon/native/onnx_runtime.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (Platform.environment['DARKMOON_NATIVE_DIR'] == null) {
    stderr.writeln(
      'Set DARKMOON_NATIVE_DIR=windows\\native before running this '
      '(see onnx_runtime.dart\'s _nativeDirOverride doc) — otherwise this '
      'resolves onnxruntime.dll/PMRID.onnx relative to dart.exe\'s own '
      'directory, not this repo\'s build output.',
    );
    exit(2);
  }
  final rawPath = args.isNotEmpty
      ? args[0]
      : r'D:\Downloads\RAW_CANON_350D.CR2';

  final meta = extractRawMetadata(rawPath);
  if (meta == null) {
    stderr.writeln('Could not read metadata for $rawPath');
    exit(2);
  }
  // ignore: avoid_print
  print(
    '${meta.cameraMake} ${meta.cameraModel} — cfaFilters=${meta.cfaFilters} '
    'isBayerCfa=${meta.isBayerCfa}',
  );
  if (!meta.isBayerCfa) {
    stderr.writeln(
      'Not a Bayer RAW — PMRID raw denoise cannot run on this file.',
    );
    exit(2);
  }

  // ignore: avoid_print
  print('Decoding plain (before)...');
  final before = decodeRawImage(rawPath, fastPreview: false);
  if (before == null) {
    stderr.writeln('Plain decode failed');
    exit(2);
  }
  File('pmrid_raw_before.png').writeAsBytesSync(
    img.encodePng(
      img.Image.fromBytes(
        width: before.width,
        height: before.height,
        bytes: before.rgbBytes.buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      ),
    ),
  );
  // ignore: avoid_print
  print('OK -> pmrid_raw_before.png (${before.width}x${before.height})');

  final model = OnnxModel.forSpec(pmridDenoiseModelSpec);
  // ignore: avoid_print
  print('PMRID model ready — running on ${model.usingGpu ? "GPU" : "CPU"}');

  final sw = Stopwatch()..start();
  var lastPct = -1;
  final after = decodeRawImageWithPmridDenoise(
    rawPath,
    fastPreview: false,
    denoiseTile: model.runPackedTile,
    onDenoiseProgress: (i, total) {
      final pct = total == 0 ? 0 : (i * 100 ~/ total);
      if (pct != lastPct) {
        lastPct = pct;
        stdout.write('\r  tile $i/$total ($pct%)');
      }
    },
  );
  stdout.writeln();
  sw.stop();
  // ignore: avoid_print
  print('decodeRawImageWithPmridDenoise: ${sw.elapsedMilliseconds}ms total');

  if (after == null) {
    stderr.writeln('Raw-domain denoise decode failed');
    exit(2);
  }
  File('pmrid_raw_after.png').writeAsBytesSync(
    img.encodePng(
      img.Image.fromBytes(
        width: after.width,
        height: after.height,
        bytes: after.rgbBytes.buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      ),
    ),
  );
  // ignore: avoid_print
  print('OK -> pmrid_raw_after.png (${after.width}x${after.height})');
}
