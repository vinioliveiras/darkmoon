import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:darkmoon/editor_screen.dart';

/// Which stand-in is on screen decides whether it is blurred.
///
/// The 200px filmstrip thumbnail has to be magnified several times to fill
/// the viewport and is going to look wrong regardless, so the blur is
/// honest about it being provisional. The camera's own embedded preview is
/// wider than the viewport and scaled *down* — showing it unaltered is the
/// entire reason it is there, and blurring it hides exactly the colour and
/// contrast it exists to show.
///
/// The blur was removed outright on 2026-09-09 when the embedded preview
/// became the usual stand-in, then brought back conditioned on this, which
/// is the distinction it should always have been drawn on.
void main() {
  Uint8List flatJpeg(int size) {
    final image = img.Image(width: size, height: (size * 2) ~/ 3);
    img.fill(image, color: img.ColorRgb8(120, 130, 140));
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  Future<int> blurLayers(WidgetTester tester, PreviewFrame frame) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: FadingPreviewImage(
              frame: frame,
              fadeGeneration: 0,
              duration: Duration.zero,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.widgetList(find.byType(ImageFiltered)).length;
  }

  testWidgets('the small filmstrip stand-in is blurred', (tester) async {
    expect(
      await blurLayers(
        tester,
        PreviewFrame.placeholder(flatJpeg(200), isSmallStandIn: true),
      ),
      greaterThan(0),
    );
  });

  testWidgets("the camera's own image is not", (tester) async {
    expect(
      await blurLayers(
        tester,
        PreviewFrame.placeholder(flatJpeg(1200)),
      ),
      0,
      reason:
          'softening it would hide the colour and contrast it is there to '
          'show',
    );
  });

  testWidgets('a real render is never blurred', (tester) async {
    late final ui.Image image;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 8, 8),
        Paint()..color = const Color(0xFF808080),
      );
      image = await recorder.endRecording().toImage(8, 8);
    });
    expect(await blurLayers(tester, PreviewFrame.rendered(image)), 0);
    image.dispose();
  });

  test('the default stand-in is the camera\'s own image', () {
    // isSmallStandIn is only meaningful for a placeholder, and the two
    // constructors initialise it separately — an easy pair to let drift.
    expect(
      PreviewFrame.placeholder(Uint8List(0)).isSmallStandIn,
      isFalse,
      reason: 'the embedded preview is the default stand-in',
    );
    expect(
      PreviewFrame.placeholder(Uint8List(0), isSmallStandIn: true).isPlaceholder,
      isTrue,
    );
  });
}
