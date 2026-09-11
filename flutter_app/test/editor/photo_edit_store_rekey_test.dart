import 'package:darkmoon/catalog/photo_meta_store.dart';
import 'package:darkmoon/editor/photo_edit_store.dart';
import 'package:darkmoon/render/tone_curve.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('rekey moves every map entry to the new path', () {
    final store = PhotoEditStore()
      ..values['a'] = {'Exposure': 1}
      ..curves['a'] = identityPhotoCurves
      ..presets['a'] = 'p'
      ..meta['a'] = const PhotoMeta(rating: 3)
      ..values['b'] = {'Contrast': 2};
    store.rekey({'a': 'a2', 'zzz': 'ignored'});
    expect(store.values.keys, containsAll(['a2', 'b']));
    expect(store.values.containsKey('a'), isFalse);
    expect(store.values['a2'], {'Exposure': 1});
    expect(store.curves.containsKey('a2'), isTrue);
    expect(store.presets['a2'], 'p');
    expect(store.meta['a2']!.rating, 3);
    expect(store.paths, {'a2', 'b'});
  });

  test('rekeyFolder follows everything under a moved folder', () {
    final oldFolder = p.join('D:', 'photos', 'trip');
    final newFolder = p.join('E:', 'archive', 'trip');
    final inside = p.join(oldFolder, 'sub', 'x.raf');
    final direct = p.join(oldFolder, 'y.raf');
    final other = p.join('D:', 'photos', 'tripping', 'z.raf');
    final store = PhotoEditStore()
      ..values[inside] = {'Exposure': 1}
      ..meta[direct] = const PhotoMeta(label: 'Red')
      ..values[other] = {'Contrast': 1};
    store.rekeyFolder(oldFolder, newFolder);
    expect(store.values.containsKey(p.join(newFolder, 'sub', 'x.raf')), isTrue);
    expect(store.meta.containsKey(p.join(newFolder, 'y.raf')), isTrue);
    expect(store.values.containsKey(other), isTrue);
    expect(store.values.containsKey(inside), isFalse);
  });
}
