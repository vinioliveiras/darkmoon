import 'package:darkmoon/export/frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _photo(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(200, 30, 30));
  return im;
}

void main() {
  test('original aspect adds the padding on every side', () {
    final size = frameSizeFor(600, 400, const FrameOptions(paddingPercent: 10));
    expect(size.padding, 60);
    expect(size.width, 720);
    expect(size.height, 520);
  });

  test('a fixed aspect grows the short side and never shrinks', () {
    final square = frameSizeFor(
      600,
      400,
      const FrameOptions(paddingPercent: 10, aspect: FrameAspect.square),
    );
    expect(square.width, 720);
    expect(square.height, 720);
    final tall = frameSizeFor(
      600,
      400,
      const FrameOptions(
        paddingPercent: 0,
        aspect: FrameAspect.ratio5x4,
        portrait: true,
      ),
    );
    expect(tall.width, 600);
    expect(tall.height, 750);
    final wide = frameSizeFor(
      400,
      600,
      const FrameOptions(paddingPercent: 0, aspect: FrameAspect.ratio16x9),
    );
    expect(wide.height, 600);
    expect(wide.width, closeTo(600 * 16 / 9, 1));
  });

  test('the photo sits centred on the background colour', () {
    final out = applyFrame(
      _photo(60, 40),
      const FrameOptions(paddingPercent: 10, background: 0xFF102030),
    );
    expect(out.width, 72);
    expect(out.height, 52);
    final corner = out.getPixel(0, 0);
    expect([corner.r, corner.g, corner.b], [0x10, 0x20, 0x30]);
    final centre = out.getPixel(36, 26);
    expect([centre.r, centre.g, centre.b], [200, 30, 30]);
    final edge = out.getPixel(6, 6); // first photo pixel
    expect([edge.r, edge.g, edge.b], [200, 30, 30]);
    final gap = out.getPixel(5, 26);
    expect([gap.r, gap.g, gap.b], [0x10, 0x20, 0x30]);
  });

  test('rounded corners blend to the background, edges stay sharp', () {
    final out = applyFrame(
      _photo(100, 100),
      const FrameOptions(
        paddingPercent: 0,
        radiusPercent: 20,
        background: 0xFFFFFFFF,
      ),
    );
    // The very corner is outside the arc: pure background.
    final corner = out.getPixel(0, 0);
    expect([corner.r, corner.g, corner.b], [255, 255, 255]);
    // Middle of an edge is inside the straight run: pure photo.
    final edge = out.getPixel(50, 0);
    expect([edge.r, edge.g, edge.b], [200, 30, 30]);
    // The arc is anti-aliased: somewhere in the corner square a pixel
    // sits between the photo and the background.
    var blended = 0;
    for (var y = 0; y < 20; y++) {
      for (var x = 0; x < 20; x++) {
        final p = out.getPixel(x, y);
        if (p.r > 200 && p.r < 255) blended++;
      }
    }
    expect(blended, greaterThan(5));
  });
}
