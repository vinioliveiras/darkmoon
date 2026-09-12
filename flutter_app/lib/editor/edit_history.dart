import '../catalog/removal.dart';
import '../render/mask.dart';
import '../render/tone_curve.dart';

/// One photo's complete editable state at a moment: the slider values,
/// the curves and the mask stack. What [EditHistory] stores.
class EditSnapshot {
  const EditSnapshot({
    required this.paramValues,
    required this.curves,
    required this.masks,
    this.inpaints = const [],
  });

  final Map<String, double> paramValues;
  final PhotoCurves curves;
  final List<MaskLayer> masks;

  /// The object removals applied (2026-09-12): an edit like the others,
  /// so undoing steps back through them too.
  final List<Removal> inpaints;

  /// Reference equality on the three parts — enough, since every mutation
  /// site in the editor builds a new Map/List/object rather than mutating
  /// in place, and cheap enough to run on every push.
  bool sameAs(EditSnapshot other) =>
      identical(paramValues, other.paramValues) &&
      identical(curves, other.curves) &&
      identical(masks, other.masks) &&
      identical(inpaints, other.inpaints);
}

/// The undo/redo stack for the photo being edited — the editor screen's
/// second controller (2026-09-10), extracted from its State.
///
/// [index] points at the snapshot matching the live state right now.
/// [reset] starts over with a single undo-proof baseline whenever the
/// live state is replaced wholesale by loading a photo's saved state
/// (selection change, folder open) rather than by an edit the user made
/// — undo/redo is scoped per photo, not across the session. [push]
/// truncates any redo branch past [index] first: editing after an undo
/// abandons the undone-away future, every editor's convention.
class EditHistory {
  final List<EditSnapshot> _entries = [];
  int _index = -1;

  bool get canUndo => _index > 0;
  bool get canRedo => _index < _entries.length - 1;

  /// Number of snapshots held, the baseline included.
  int get length => _entries.length;

  /// The position of the live state in the stack (`-1` before [reset]).
  int get index => _index;

  void reset(EditSnapshot baseline) {
    _entries
      ..clear()
      ..add(baseline);
    _index = 0;
  }

  /// Records [snapshot] as a new entry — call after committing an edit
  /// (every `...ChangeEnd` / one-shot action), never from a live dragging
  /// callback, so a slider drag collapses into one undo step. A push of
  /// the very state at the top of the stack is skipped (redoing back to
  /// it and editing again would otherwise duplicate it); returns whether
  /// an entry was added.
  bool push(EditSnapshot snapshot) {
    if (_entries.isNotEmpty &&
        _index == _entries.length - 1 &&
        _entries.last.sameAs(snapshot)) {
      return false;
    }
    _entries.removeRange(_index + 1, _entries.length);
    _entries.add(snapshot);
    _index = _entries.length - 1;
    return true;
  }

  /// Steps back and returns the snapshot to restore, or null at the
  /// baseline.
  EditSnapshot? undo() {
    if (!canUndo) {
      return null;
    }
    _index--;
    return _entries[_index];
  }

  /// Steps forward and returns the snapshot to restore, or null at the
  /// newest entry.
  EditSnapshot? redo() {
    if (!canRedo) {
      return null;
    }
    _index++;
    return _entries[_index];
  }
}
