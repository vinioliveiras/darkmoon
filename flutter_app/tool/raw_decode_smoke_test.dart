// Standalone smoke test for the full RAW decode path (libraw_unpack +
// libraw_dcraw_process + libraw_dcraw_make_mem_image), separate from the
// thumbnail-only path in thumbnail_smoke_test.dart. Writes the decoded
// image out as a PNG (via package:image, just for this test's own
// visualization — the app itself doesn't need to go through PNG for this).
//
// Usage: dart run tool/raw_decode_smoke_test.dart <raw-file> [out.png]
import 'dart:io';

import 'package:darkmoon/native/libraw.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/raw_decode_smoke_test.dart <raw-file> [out.png]');
    exit(1);
  }
  final path = args[0];
  final outPath = args.length > 1 ? args[1] : 'raw_decode_smoke_test_out.png';

  final stopwatch = Stopwatch()..start();
  final decoded = decodeRawImage(path, fastPreview: true);
  stopwatch.stop();

  if (decoded == null) {
    stderr.writeln('decodeRawImage returned null for $path');
    exit(2);
  }
  // ignore: avoid_print
  print(
    'decodeRawImage: ${decoded.width}x${decoded.height}, '
    '${decoded.rgbBytes.length} raw RGB bytes, ${stopwatch.elapsedMilliseconds}ms',
  );

  final expectedBytes = decoded.width * decoded.height * 3;
  if (decoded.rgbBytes.length != expectedBytes) {
    stderr.writeln(
      'WARNING: byte count mismatch — expected $expectedBytes for '
      '${decoded.width}x${decoded.height}x3, got ${decoded.rgbBytes.length}',
    );
  }

  final image = img.Image.fromBytes(
    width: decoded.width,
    height: decoded.height,
    bytes: decoded.rgbBytes.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  File(outPath).writeAsBytesSync(img.encodePng(image));
  // ignore: avoid_print
  print('OK -> $outPath');
}
