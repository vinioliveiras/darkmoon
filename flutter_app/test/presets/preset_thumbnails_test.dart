import 'dart:typed_data';

import 'package:darkmoon/native/edit_source.dart';
import 'package:darkmoon/presets/preset.dart';
import 'package:darkmoon/presets/preset_thumbnails.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:flutter_test/flutter_test.dart';

/// The store's job is not really "render a thumbnail" — that is one call
/// to the renderer. It is knowing when a thumbnail it already has is
/// still good, because with a library of eighty presets the difference
/// between keeping and re-rendering them is the difference between the
/// feature being usable and being unusable.
void main() {
  EditSource source({int width = 200, int height = 150, int tone = 120}) {
    final rgb = Uint8List(width * height * 3);
    for (var i = 0; i < rgb.length; i++) {
      rgb[i] = (tone + i) % 256;
    }
    return EditSource(width: width, height: height, rgbBytes: rgb);
  }

  Preset preset(String id) =>
      Preset(id: id, name: id, values: const {'Exposure': 0.5});

  RenderParams params(Preset _) => const RenderParams();

  /// Asks for [id]'s thumbnail and waits for it.
  ///
  /// The whole chain runs inside `runAsync`, not just the waiting. The
  /// render is handed to another isolate, and a future created inside the
  /// test's fake-async zone is driven by a clock that `runAsync` does not
  /// advance — start the request in that zone and it never completes, no
  /// matter how long the waiting side waits.
  Future<void> renderOne(
    WidgetTester tester,
    PresetThumbnailStore store,
    String id,
  ) async {
    await tester.runAsync(() async {
      store.request(preset(id));
      for (var i = 0; i < 400; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (store.thumbnailFor(id) != null) {
          return;
        }
      }
    });
  }

  testWidgets('renders what is asked for and keeps it', (tester) async {
    final store = PresetThumbnailStore();
    addTearDown(store.dispose);

    store.setSource(
      signature: 'photo-1',
      source: source(),
      paramsFor: params,
    );
    expect(store.hasSource, isTrue);
    expect(store.thumbnailFor('a'), isNull, reason: 'nothing asked for yet');

    await renderOne(tester, store, 'a');

    final image = store.thumbnailFor('a');
    expect(image, isNotNull);
    expect(
      image!.width,
      lessThanOrEqualTo(kPresetThumbnailEdge),
      reason: 'the whole point is that it is tiny',
    );
  });

  testWidgets('the same photo keeps its thumbnails', (tester) async {
    // This is the requirement, stated as a test. Applying a preset
    // rebuilds the editor and re-runs the sync, and if that dropped the
    // cache then every click would re-render the whole library.
    final store = PresetThumbnailStore();
    addTearDown(store.dispose);

    store.setSource(signature: 'photo-1', source: source(), paramsFor: params);
    await renderOne(tester, store, 'a');
    final first = store.thumbnailFor('a');
    expect(first, isNotNull);

    store.setSource(signature: 'photo-1', source: source(), paramsFor: params);
    expect(
      store.thumbnailFor('a'),
      same(first),
      reason:
          'nothing a thumbnail depends on changed, so it must be the very '
          'same image and not a re-render',
    );
  });

  testWidgets('a different photo drops them', (tester) async {
    final store = PresetThumbnailStore();
    addTearDown(store.dispose);

    store.setSource(signature: 'photo-1', source: source(), paramsFor: params);
    await renderOne(tester, store, 'a');
    expect(store.thumbnailFor('a'), isNotNull);

    store.setSource(
      signature: 'photo-2',
      source: source(tone: 40),
      paramsFor: params,
    );
    expect(
      store.thumbnailFor('a'),
      isNull,
      reason: 'that image is of the previous photo',
    );
  });

  testWidgets('asking twice does not render twice', (tester) async {
    final store = PresetThumbnailStore();
    addTearDown(store.dispose);

    store.setSource(signature: 'photo-1', source: source(), paramsFor: params);
    // A row calls this on every build, so it has to be free after the
    // first time.
    await tester.runAsync(() async {
      for (var i = 0; i < 5; i++) {
        store.request(preset('a'));
      }
    });
    await renderOne(tester, store, 'a');
    final first = store.thumbnailFor('a');
    expect(first, isNotNull);

    await renderOne(tester, store, 'a');
    expect(store.thumbnailFor('a'), same(first));
  });

  test('with no photo there is nothing to render', () {
    final store = PresetThumbnailStore();
    addTearDown(store.dispose);

    store.setSource(signature: 'none', source: null, paramsFor: params);
    expect(store.hasSource, isFalse);
    store.request(preset('a'));
    expect(store.thumbnailFor('a'), isNull);
  });
}
