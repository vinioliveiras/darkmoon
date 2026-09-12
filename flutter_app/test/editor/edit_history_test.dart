import 'package:darkmoon/catalog/removal.dart';
import 'dart:typed_data';
import 'package:darkmoon/editor/edit_history.dart';
import 'package:darkmoon/render/tone_curve.dart';
import 'package:flutter_test/flutter_test.dart';

EditSnapshot _snap(double exposure) => EditSnapshot(
  paramValues: {'Exposure': exposure},
  curves: identityPhotoCurves,
  masks: const [],
);

void main() {
  test('a snapshot with other removals is a different snapshot', () {
    const base = EditSnapshot(
      paramValues: {},
      curves: identityPhotoCurves,
      masks: [],
    );
    final withRemoval = EditSnapshot(
      paramValues: base.paramValues,
      curves: base.curves,
      masks: base.masks,
      inpaints: [
        Removal(name: 'Removal 1', width: 1, height: 1, alphaPng: Uint8List(0)),
      ],
    );
    expect(base.sameAs(withRemoval), isFalse);
    final history = EditHistory()..reset(base);
    expect(history.push(withRemoval), isTrue);
    expect(history.canUndo, isTrue);
  });

  test('starts empty, reset gives an undo-proof baseline', () {
    final history = EditHistory();
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
    expect(history.undo(), isNull);
    history.reset(_snap(0));
    expect(history.length, 1);
    expect(history.index, 0);
    expect(history.canUndo, isFalse);
  });

  test('undo and redo walk the stack and stop at both ends', () {
    final history = EditHistory()..reset(_snap(0));
    final one = _snap(1);
    final two = _snap(2);
    expect(history.push(one), isTrue);
    expect(history.push(two), isTrue);
    expect(history.length, 3);
    expect(history.undo(), same(one));
    expect(history.canRedo, isTrue);
    expect(history.undo()!.paramValues['Exposure'], 0);
    expect(history.undo(), isNull);
    expect(history.redo(), same(one));
    expect(history.redo(), same(two));
    expect(history.redo(), isNull);
  });

  test('pushing the state already on top is a no-op', () {
    final history = EditHistory()..reset(_snap(0));
    final one = _snap(1);
    expect(history.push(one), isTrue);
    expect(history.push(one), isFalse);
    expect(history.length, 2);
    // A structurally equal but distinct snapshot is a new entry — the
    // check is by reference, on purpose.
    expect(history.push(_snap(1)), isTrue);
    expect(history.length, 3);
  });

  test('editing after an undo discards the redo branch', () {
    final history = EditHistory()..reset(_snap(0));
    history.push(_snap(1));
    history.push(_snap(2));
    history.undo();
    history.undo();
    expect(history.canRedo, isTrue);
    final branch = _snap(9);
    history.push(branch);
    expect(history.canRedo, isFalse);
    expect(history.length, 2);
    expect(history.undo()!.paramValues['Exposure'], 0);
    expect(history.redo(), same(branch));
  });

  test('reset after edits forgets them', () {
    final history = EditHistory()..reset(_snap(0));
    history.push(_snap(1));
    history.reset(_snap(5));
    expect(history.length, 1);
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
  });
}
