import 'package:darkmoon/catalog/sidecar_xmp.dart';
import 'package:darkmoon/editor/photo_edit_store.dart';
import 'package:darkmoon/render/mask.dart';
import 'package:darkmoon/render/tone_curve.dart';
import 'package:flutter_test/flutter_test.dart';

/// The in-memory half of [PhotoEditStore]; load/save/clear go through the
/// JSON stores in Documents and are covered by their own tests.
void main() {
  const mask = MaskLayer(id: 'm', name: 'Sky', type: MaskType.radialGradient);

  test('paths and contains span the maps, a preset marker alone does '
      'not count as an edit', () {
    final store = PhotoEditStore()
      ..values['a'] = {'Exposure': 1}
      ..curves['b'] = const PhotoCurves(tone: [CurvePoint(0, 0.1)])
      ..masks['c'] = [mask]
      ..presets['d'] = 'preset_1';
    expect(store.paths, {'a', 'b', 'c', 'd'});
    expect(store.contains('a'), isTrue);
    expect(store.contains('b'), isTrue);
    expect(store.contains('c'), isTrue);
    expect(store.contains('d'), isFalse);
    expect(store.contains('e'), isFalse);
  });

  test('removeWhere drops a path from every map', () {
    final store = PhotoEditStore()
      ..values['gone'] = {'Exposure': 1}
      ..curves['gone'] = identityPhotoCurves
      ..masks['gone'] = [mask]
      ..presets['gone'] = 'p'
      ..values['kept'] = {'Contrast': 5};
    store.removeWhere((path) => path == 'gone');
    expect(store.paths, {'kept'});
  });

  test('sidecarFor packs the four maps and adopt unpacks them', () {
    final store = PhotoEditStore()
      ..values['a'] = {'Exposure': 0.5}
      ..masks['a'] = [mask]
      ..presets['a'] = 'p1';
    final sidecar = store.sidecarFor('a');
    expect(sidecar.values, {'Exposure': 0.5});
    expect(sidecar.curves.isIdentity, isTrue);
    expect(sidecar.masks.single.id, 'm');
    expect(sidecar.presetId, 'p1');

    final other = PhotoEditStore()..presets['b'] = 'kept';
    other.adopt('b', sidecar);
    expect(other.values['b'], {'Exposure': 0.5});
    expect(other.masks['b']!.single.id, 'm');
    // The sidecar's own preset wins where it has one...
    expect(other.presets['b'], 'p1');
    // ...and an existing marker survives a sidecar that has none.
    other.adopt('b', const PhotoSidecar(values: {'Contrast': 1}));
    expect(other.presets['b'], 'p1');
    expect(other.values['b'], {'Contrast': 1});
  });

  test('a fresh store has nothing and no sidecar worth writing', () {
    final store = PhotoEditStore();
    expect(store.paths, isEmpty);
    expect(store.sidecarFor('x').hasEdits, isFalse);
  });
}
