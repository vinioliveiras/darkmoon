import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/native/image_utils.dart';

void main() {
  group('fitToMaxDimension', () {
    test('returns image unchanged when already small enough', () {
      final image = img.Image(width: 10, height: 10);
      final result = fitToMaxDimension(image, 20);
      expect(result, same(image));
    });

    test('downscales preserving aspect ratio', () {
      final image = img.Image(width: 400, height: 200);
      final result = fitToMaxDimension(image, 100);
      expect(result.width, 100);
      expect(result.height, 50);
    });

    test('area-averages a pixel-level checkerboard instead of subsampling '
        'it', () {
      // A single-pixel-scale black/white checkerboard, downscaled 4x so
      // each output pixel's source region spans an even mix of black and
      // white input pixels. Nearest-neighbor subsampling would just pick
      // whichever single input pixel lands on the sample grid — landing on
      // a pure 0 or 255 for every output pixel, i.e. the checkerboard
      // survives at a coarser scale instead of being smoothed away. Area
      // averaging blends each region toward its true ~50/50 mean of
      // ~127.5, which is the Lightroom-like, noise-reducing behavior this
      // function exists to provide.
      const side = 16;
      final image = img.Image(width: side, height: side);
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final v = (x + y).isEven ? 255 : 0;
          image.setPixelRgb(x, y, v, v, v);
        }
      }

      const targetSide = 4;
      final result = fitToMaxDimension(image, targetSide);
      expect(result.width, targetSide);
      expect(result.height, targetSide);

      for (var y = 0; y < targetSide; y++) {
        for (var x = 0; x < targetSide; x++) {
          final pixel = result.getPixel(x, y);
          // Area-averaged output should land near the region's true mean —
          // never at a pure 0 or 255 extreme the way nearest-neighbor
          // subsampling of a checkerboard would.
          expect(pixel.r.toDouble(), greaterThan(40));
          expect(pixel.r.toDouble(), lessThan(215));
        }
      }
    });
  });

  group('scaleByPercent', () {
    test('returns image unchanged at 100%', () {
      final image = img.Image(width: 400, height: 200);
      final result = scaleByPercent(image, 100);
      expect(result, same(image));
    });

    test('returns image unchanged above 100%', () {
      final image = img.Image(width: 400, height: 200);
      final result = scaleByPercent(image, 150);
      expect(result, same(image));
    });

    test('scales down preserving aspect ratio', () {
      final image = img.Image(width: 400, height: 200);
      final result = scaleByPercent(image, 50);
      expect(result.width, 200);
      expect(result.height, 100);
    });

    test('default rapid-export percent trims only slightly', () {
      final image = img.Image(width: 4000, height: 3000);
      final result = scaleByPercent(image, 95);
      expect(result.width, 3800);
      expect(result.height, 2850);
    });
  });
}
