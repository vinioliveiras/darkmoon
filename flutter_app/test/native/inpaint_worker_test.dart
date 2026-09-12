// One removal through the app's own worker on a real photo: the same
// decode (LibRaw for a RAW, the common decoder otherwise), coverage
// record, model and cache as the editor uses — everything but the
// widgets. Needs a built bundle and a photo:
//
//   DARKMOON_NATIVE_DIR=<bundle> DARKMOON_PROBE_PHOTO=<file> \
//     flutter test test/native/inpaint_worker_test.dart
//
// Skipped without them (CI has neither). Written for the 2026-09-12
// report that a removal on a RAW left the painted mask on screen.
import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/catalog/removal.dart';
import 'package:darkmoon/native/edit_source_inpaint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final photo = Platform.environment['DARKMOON_PROBE_PHOTO'];
  final native = Platform.environment['DARKMOON_NATIVE_DIR'];
  test(
    'the worker applies one removal to a real photo',
    () async {
      final cacheDir = Directory.systemTemp.createTempSync('darkmoon_inpaint_');
      addTearDown(() => cacheDir.deleteSync(recursive: true));
      const w = 640, h = 480;
      final alpha = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final dx = (x - w / 2) / 60.0, dy = (y - h / 2) / 80.0;
          final d = dx * dx + dy * dy;
          alpha[y * w + x] = d < 1 ? 1.0 : (d < 1.4 ? (1.4 - d) / 0.4 : 0.0);
        }
      }
      final removal = Removal(
        name: 'Removal 1',
        width: w,
        height: h,
        alphaPng: encodeAlphaPng(alpha, w, h),
      );
      final sw = Stopwatch()..start();
      final result = await decodeEditSourcesWithInpaint(
        photo!,
        cacheDir.path,
        // ignore: avoid_print
        (stage) => print('   ${sw.elapsedMilliseconds} ms  $stage'),
        removals: [removal],
      );
      // ignore: avoid_print
      print('   done in ${sw.elapsedMilliseconds} ms');
      expect(result, isNotNull, reason: 'the worker returned null');
      expect(result!.preview.width, greaterThan(0));
      final dump = Platform.environment['DARKMOON_PROBE_OUT'];
      if (dump != null) {
        final live = result.live;
        final header =
            'P6 ${live.width} ${live.height} 255${String.fromCharCode(10)}';
        File(
          '$dump/worker_live.ppm',
        ).writeAsBytesSync([...header.codeUnits, ...live.rgbBytes]);
      }
    },
    skip: photo == null || native == null
        ? 'set DARKMOON_PROBE_PHOTO and DARKMOON_NATIVE_DIR'
        : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
