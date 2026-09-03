import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:darkmoon/editor_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _image() {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList([255, 0, 0, 255]),
    1,
    1,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  // The constraint behind PreviewFrame.cloneHandle's "must be called while
  // the owner still holds the image" rule, and behind
  // FadingPreviewImage taking its handle on receipt rather than in
  // didUpdateWidget. Ignoring it put a grey ErrorWidget over the whole
  // canvas on every settled edit — see fading_preview_image_test.dart.
  test('cloning a frame the owner already disposed throws', () async {
    final image = await _image();
    final frame = PreviewFrame.rendered(image);
    // Exactly what _setPreviewImage does when a new render lands: it
    // disposes the outgoing image synchronously, inside setState, before
    // the widget tree rebuilds.
    image.dispose();
    expect(frame.cloneHandle, throwsA(isA<StateError>()));
  });

  test('a handle taken while the image was alive outlives the owner', () async {
    final image = await _image();
    final kept = PreviewFrame.rendered(image).cloneHandle();
    image.dispose();
    expect(kept.image!.width, 1);
    kept.disposeHandle();
  });
}
