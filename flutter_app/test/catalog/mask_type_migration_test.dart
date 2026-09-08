import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/catalog/mask_store.dart';
import 'package:darkmoon/render/mask.dart';

/// One saved mask of [type], in the shape `savePhotoMasks` writes.
Map<String, dynamic> savedMask(String type) => {
  'id': 'mask_1',
  'name': 'Mask',
  'type': type,
  'enabled': true,
  'inverted': false,
  'opacity': 100.0,
  'values': <String, dynamic>{'exposure': 0.5},
};

List<MaskLayer> decode(List<Map<String, dynamic>> masks) =>
    decodePhotoMasksJson({'C:/photo.raf': masks})['C:/photo.raf'] ?? const [];

void main() {
  test('a saved Subject mask loads as a Foreground mask', () {
    // Subject was removed 2026-09-08 and Foreground took over the job, so
    // a photo edited while it existed keeps its mask rather than losing it.
    final masks = decode([savedMask('subject')]);
    expect(masks, hasLength(1));
    expect(masks.single.type, MaskType.foreground);
    expect(masks.single.values['exposure'], 0.5);
  });

  test('an unknown type does not take the photo\'s other masks with it', () {
    // `MaskType.values.byName` throws on a name it does not know, which
    // inside the decode loop would fail the whole file — so a mask written
    // by a newer build costs that one mask, not all of them.
    final masks = decode([
      savedMask('somethingFromTheFuture'),
      savedMask('radialGradient'),
    ]);
    expect(masks, hasLength(2));
    expect(masks[1].type, MaskType.radialGradient);
  });

  test('every current type still round-trips under its own name', () {
    final masks = decode([
      for (final type in MaskType.values) savedMask(type.name),
    ]);
    expect(
      masks.map((m) => m.type).toList(),
      MaskType.values,
      reason: 'a type whose name changed would silently become another type',
    );
  });
}
