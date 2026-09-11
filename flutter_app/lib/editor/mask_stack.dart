import '../render/mask.dart';

/// The mask stack of the photo being edited: its layers, which one the
/// panel is editing, and the operations the mask picker and the canvas
/// perform on them. The editor screen's third controller (2026-09-12),
/// extracted from its State so that naming, cloning, deleting and the
/// brush's stroke undo can be tested without a widget tree.
///
/// Every operation replaces [layers] with a new list rather than mutating
/// it in place: the undo history compares snapshots by identity, and the
/// widgets rebuild on identity too. The controller knows nothing about
/// rendering, history or saving — the State wraps each call with those.
class MaskStack {
  MaskStack({
    List<MaskLayer> layers = const [],
    this.activeId = imageMaskId,
    String Function()? newId,
  }) : _layers = layers,
       _newId = newId ?? _timestampId;

  List<MaskLayer> _layers;
  final String Function() _newId;

  /// Which layer the controls panel is editing: [imageMaskId] for the
  /// whole photo, or one of [layers]' ids.
  String activeId;

  /// The layers, oldest first. Replaced, never mutated in place.
  List<MaskLayer> get layers => _layers;

  /// The active layer, or null on the image layer (or a stale id).
  MaskLayer? get active => activeId == imageMaskId
      ? null
      : _layers.where((m) => m.id == activeId).firstOrNull;

  bool get onImage => activeId == imageMaskId;

  static String _timestampId() =>
      'mask_${DateTime.now().microsecondsSinceEpoch}';

  void select(String id) => activeId = id;

  /// Adds a mask of [type] named "[baseName] N", N counting the masks of
  /// that type so far plus one, and selects it.
  MaskLayer add(MaskType type, String baseName) {
    final countOfType = _layers.where((m) => m.type == type).length + 1;
    final mask = MaskLayer(
      id: _newId(),
      name: '$baseName $countOfType',
      type: type,
    );
    _layers = [..._layers, mask];
    activeId = mask.id;
    return mask;
  }

  /// Duplicates the active mask into a new sibling — every geometry, the
  /// flags, the opacity, its own values and curves — with a fresh id and
  /// [suffix] after the name, and selects the copy. Null when nothing is
  /// active.
  MaskLayer? clone(String suffix) {
    final source = active;
    if (source == null) {
      return null;
    }
    final copy = MaskLayer(
      id: _newId(),
      name: '${source.name} $suffix',
      type: source.type,
      linear: source.linear,
      radial: source.radial,
      brush: source.brush,
      colorRange: source.colorRange,
      luminance: source.luminance,
      subject: source.subject,
      depth: source.depth,
      enabled: source.enabled,
      inverted: source.inverted,
      opacity: source.opacity,
      values: Map<String, double>.from(source.values),
      curves: source.curves,
    );
    _layers = [..._layers, copy];
    activeId = copy.id;
    return copy;
  }

  /// Removes the active mask and returns the panel to the image layer.
  void deleteActive() {
    _layers = [
      for (final mask in _layers)
        if (mask.id != activeId) mask,
    ];
    activeId = imageMaskId;
  }

  /// Rewrites the active mask through [update]; nothing on the image layer.
  void updateActive(MaskLayer Function(MaskLayer mask) update) {
    _layers = [
      for (final mask in _layers)
        if (mask.id == activeId) update(mask) else mask,
    ];
  }

  /// Puts [updated] in place of the layer with its id.
  void replace(MaskLayer updated) {
    _layers = [
      for (final mask in _layers)
        if (mask.id == updated.id) updated else mask,
    ];
  }

  /// Drops the active brush mask's last stroke. False when there was no
  /// stroke to drop, so the caller can skip the history entry.
  bool undoLastStroke() {
    final mask = active;
    if (mask == null || mask.brush.strokes.isEmpty) {
      return false;
    }
    updateActive(
      (m) => m.copyWith(
        brush: m.brush.copyWith(
          strokes: m.brush.strokes.sublist(0, m.brush.strokes.length - 1),
        ),
      ),
    );
    return true;
  }

  /// Replaces the stack wholesale (a photo's saved state, an undo step).
  /// The active layer is kept when it is still there, and the panel
  /// returns to the image layer when it is not: undoing past a mask's
  /// creation must not leave the panel pointing at a mask that is gone.
  void load(List<MaskLayer> layers) {
    _layers = layers;
    if (activeId != imageMaskId && !layers.any((m) => m.id == activeId)) {
      activeId = imageMaskId;
    }
  }

  /// No masks, the image layer active.
  void clear() {
    _layers = [];
    activeId = imageMaskId;
  }
}
