import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:darkmoon/editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Must go through tester.runAsync: testWidgets runs inside a fake-async
// zone, and decodeImageFromPixels' callback comes from the engine, so it
// never fires under fake time.
Future<ui.Image> _image(WidgetTester tester, int r) async =>
    (await tester.runAsync(() => _decode(r)))!;

Future<ui.Image> _decode(int r) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList([r, 0, 0, 255]),
    1,
    1,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Widget _host(PreviewFrame frame, int generation) => MaterialApp(
  home: SizedBox(
    width: 100,
    height: 100,
    child: FadingPreviewImage(
      frame: frame,
      fadeGeneration: generation,
      duration: const Duration(milliseconds: 220),
    ),
  ),
);

void main() {
  // Regression test for the grey rectangle that covered the whole canvas on
  // every settled edit (2026-09-03). The editor's preview map disposes a
  // frame synchronously when its replacement lands, before this widget
  // rebuilds — so the outgoing frame is already dead by the time
  // didUpdateWidget sees it as `old.frame`. Cloning it there threw
  // StateError, and Flutter renders a thrown build as an ErrorWidget: a
  // plain grey box in release builds.
  testWidgets('a settled edit cross-fades without touching the disposed '
      'image the editor just replaced', (tester) async {
    final first = await _image(tester, 10);
    await tester.pumpWidget(_host(PreviewFrame.rendered(first), 1));
    await tester.pump(const Duration(milliseconds: 300));

    // Exactly what _setPreviewImage does: the new render's image is stored
    // and the outgoing one is disposed, both before the rebuild.
    final second = await _image(tester, 20);
    first.dispose();
    await tester.pumpWidget(_host(PreviewFrame.rendered(second), 2));

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(RawImage), findsWidgets);

    // Mid-fade both layers paint; the outgoing one must still be alive.
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    second.dispose();
  });

  testWidgets('a live drag frame swaps in place without a fade', (
    tester,
  ) async {
    final first = await _image(tester, 10);
    await tester.pumpWidget(_host(PreviewFrame.rendered(first), 1));
    await tester.pump(const Duration(milliseconds: 300));

    // Same generation — a live drag tick. The old image is replaced and
    // disposed just the same.
    final second = await _image(tester, 20);
    first.dispose();
    await tester.pumpWidget(_host(PreviewFrame.rendered(second), 1));

    expect(tester.takeException(), isNull);
    expect(find.byType(RawImage), findsOneWidget);
    second.dispose();
  });
}
