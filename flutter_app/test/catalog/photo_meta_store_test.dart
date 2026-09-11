import 'package:darkmoon/catalog/photo_meta_store.dart';
import 'package:darkmoon/catalog/sidecar_xmp.dart';
import 'package:darkmoon/editor/photo_edit_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PhotoMeta round-trips through JSON and drops what is empty', () {
    const meta = PhotoMeta(rating: 4, label: 'Blue', tags: ['a', 'b']);
    final json = meta.toJson();
    expect(json, {
      'rating': 4,
      'label': 'Blue',
      'tags': ['a', 'b'],
    });
    final back = PhotoMeta.fromJson(json);
    expect(back.rating, 4);
    expect(back.label, 'Blue');
    expect(back.tags, ['a', 'b']);
    expect(const PhotoMeta().toJson(), isEmpty);
    expect(const PhotoMeta().isEmpty, isTrue);
    expect(PhotoMeta.fromJson({'rating': 9}).rating, 5);
    expect(
      PhotoMeta.fromJson({
        'tags': ['', 3, 'x'],
      }).tags,
      ['x'],
    );
  });

  test('the store keeps meta beside the edits and mirrors it to the '
      'sidecar', () {
    final store = PhotoEditStore()
      ..setMeta('a', const PhotoMeta(rating: 3, label: 'Red'));
    expect(store.paths, {'a'});
    // Meta alone is not an edit...
    expect(store.contains('a'), isFalse);
    // ...but it goes into the sidecar.
    final sidecar = store.sidecarFor('a');
    expect(sidecar.rating, 3);
    expect(sidecar.label, 'Red');
    expect(sidecar.hasEdits, isFalse);
    expect(sidecar.hasMetadata, isTrue);
    // Clearing removes the entry.
    store.setMeta('a', const PhotoMeta());
    expect(store.meta.containsKey('a'), isFalse);
  });

  test('adopting a sidecar takes its metadata, and only when it has some', () {
    final store = PhotoEditStore();
    expect(
      store.adoptMeta('a', const PhotoSidecar(values: {'Contrast': 1})),
      isFalse,
    );
    expect(store.meta, isEmpty);
    expect(
      store.adoptMeta('a', const PhotoSidecar(rating: 5, tags: ['t'])),
      isTrue,
    );
    expect(store.meta['a']!.rating, 5);
    expect(store.meta['a']!.tags, ['t']);
    store.adopt(
      'b',
      const PhotoSidecar(values: {'Exposure': 1}, label: 'Green'),
    );
    expect(store.meta['b']!.label, 'Green');
    expect(store.values['b'], {'Exposure': 1});
  });
}
