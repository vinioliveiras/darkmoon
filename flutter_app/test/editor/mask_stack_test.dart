import 'package:darkmoon/editor/mask_stack.dart';
import 'package:darkmoon/render/mask.dart';
import 'package:darkmoon/render/tone_curve.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mask stack's own rules, checked without a widget tree: how new
/// masks are named, that a clone carries every field, where the panel
/// lands after a delete or an undo, and the brush's stroke undo.
void main() {
  var counter = 0;
  MaskStack stack() => MaskStack(newId: () => 'id${counter++}');

  setUp(() => counter = 0);

  test('adding names by type count and selects the new mask', () {
    final s = stack();
    final first = s.add(MaskType.brush, 'Brush');
    s.add(MaskType.linearGradient, 'Linear');
    final third = s.add(MaskType.brush, 'Brush');
    expect(first.name, 'Brush 1');
    expect(third.name, 'Brush 2');
    expect(s.activeId, third.id);
    expect(s.active, same(third));
    expect(s.layers.length, 3);
  });

  test('every operation hands back a new list', () {
    final s = stack();
    final before = s.layers;
    s.add(MaskType.brush, 'Brush');
    expect(identical(before, s.layers), isFalse);
    final added = s.layers;
    s.updateActive((m) => m.copyWith(opacity: 40));
    expect(identical(added, s.layers), isFalse);
    expect(s.active!.opacity, 40);
  });

  test('a clone carries every field and takes over as active', () {
    final s = stack();
    final source = s.add(MaskType.luminance, 'Luminance');
    s.replace(
      source.copyWith(
        luminance: const LuminanceGeometry(targetLuma: 0.8, tolerance: 0.3),
        inverted: true,
        opacity: 55,
        values: {'Exposure': 1.5},
        curves: identityPhotoCurves.copyWith(
          tone: const [CurvePoint(0, 0), CurvePoint(1, 0.9)],
        ),
      ),
    );
    final copy = s.clone('copy')!;
    expect(copy.id, isNot(source.id));
    expect(copy.name, 'Luminance 1 copy');
    expect(copy.type, MaskType.luminance);
    expect(copy.luminance.targetLuma, 0.8);
    expect(copy.luminance.tolerance, 0.3);
    expect(copy.inverted, isTrue);
    expect(copy.opacity, 55);
    expect(copy.values, {'Exposure': 1.5});
    expect(copy.curves.tone.last.y, 0.9);
    expect(s.activeId, copy.id);
    expect(s.layers.length, 2);
    // The copy's values are its own, not shared with the source.
    expect(identical(copy.values, s.layers.first.values), isFalse);
  });

  test('cloning on the image layer does nothing', () {
    final s = stack();
    expect(s.clone('copy'), isNull);
    expect(s.layers, isEmpty);
  });

  test('deleting returns the panel to the image layer', () {
    final s = stack();
    s.add(MaskType.brush, 'Brush');
    final kept = s.add(MaskType.sky, 'Sky');
    s.select(s.layers.first.id);
    s.deleteActive();
    expect(s.layers.map((m) => m.id), [kept.id]);
    expect(s.activeId, imageMaskId);
    expect(s.onImage, isTrue);
  });

  test('undoing a stroke drops the last one and reports when none', () {
    final s = stack();
    final mask = s.add(MaskType.brush, 'Brush');
    expect(s.undoLastStroke(), isFalse);
    s.replace(
      mask.copyWith(
        brush: const BrushGeometry(
          strokes: [
            BrushStroke(
              points: [BrushPoint(0.1, 0.1)],
              radius: 0.05,
              hardness: 0.5,
              erase: false,
            ),
            BrushStroke(
              points: [BrushPoint(0.5, 0.5)],
              radius: 0.05,
              hardness: 0.5,
              erase: false,
            ),
          ],
        ),
      ),
    );
    expect(s.undoLastStroke(), isTrue);
    expect(s.active!.brush.strokes.length, 1);
    expect(s.active!.brush.strokes.single.points.single.x, 0.1);
  });

  test(
    'loading keeps the active mask when present and falls back when not',
    () {
      final s = stack();
      final a = s.add(MaskType.brush, 'Brush');
      final b = s.add(MaskType.brush, 'Brush');
      s.select(a.id);
      s.load([a, b]);
      expect(s.activeId, a.id);
      s.load([b]);
      expect(s.activeId, imageMaskId);
      s.clear();
      expect(s.layers, isEmpty);
    },
  );
}
