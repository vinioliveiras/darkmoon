// Zoom and pan of the preview.
//
// A `part` of editor_screen.dart holding methods of _EditorScreenState,
// as an extension: same library, same private scope, fields stay on the
// State. `setState` is protected and an extension is not a subclass, so
// these go through the State's `_rebuild`. Split 2026-09-10 for navigation.
part of '../editor_screen.dart';

extension _EditorZoom on _EditorScreenState {
  /// Instant — used for "the view just needs to be Fit again" resets
  /// (switching photos, opening the Crop overlay) that aren't really a
  /// user-initiated zoom gesture, so animating them would just be a
  /// distracting flourish on top of an unrelated action.
  void _resetZoom() {
    _viewController.value = Matrix4.identity();
    _rebuild(() => _zoomScale = 1.0);
  }

  /// The animated counterpart, for the toolbar's Fit button specifically.
  void _resetZoomAnimated() {
    _animateViewMatrixTo(Matrix4.identity());
    _rebuild(() => _zoomScale = 1.0);
  }

  /// The matrix/scale a zoom by [factor] (centered on [anchor], or the
  /// viewport's own center) would land on, or null if [factor] wouldn't
  /// move [_zoomScale] at all (already at the min/max clamp).
  ({Matrix4 matrix, double scale})? _computeZoomTarget(
    double factor, {
    Offset? anchor,
  }) {
    final newScale = (_zoomScale * factor).clamp(_minZoom, _maxZoom);
    final effectiveFactor = newScale / _zoomScale;
    if (effectiveFactor == 1.0) {
      return null;
    }
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    final center =
        anchor ?? (box != null ? box.size.center(Offset.zero) : Offset.zero);
    final matrix = Matrix4.copy(_viewController.value)
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(effectiveFactor, effectiveFactor, effectiveFactor, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    return (matrix: matrix, scale: newScale);
  }

  /// Instant zoom — used for continuous gestures (Ctrl+scroll-wheel,
  /// double-click) that already have their own immediate feel; animating
  /// every tiny wheel tick would fight the gesture instead of following
  /// it.
  void _zoomBy(double factor, {Offset? anchor}) {
    final target = _computeZoomTarget(factor, anchor: anchor);
    if (target == null) {
      return;
    }
    _viewController.value = target.matrix;
    _rebuild(() => _zoomScale = target.scale);
    // Zoom no longer triggers any render — the preview is rendered once,
    // at [AppSettings.previewResolution], and only scaled on screen.
  }

  /// The animated counterpart, for the toolbar's +/- buttons — a single
  /// discrete click benefits from an eased hop between zoom levels.
  void _zoomByAnimated(double factor) {
    final target = _computeZoomTarget(factor);
    if (target == null) {
      return;
    }
    _animateViewMatrixTo(target.matrix);
    _rebuild(() => _zoomScale = target.scale);
  }

  void _zoomIn() => _zoomByAnimated(_zoomStep);

  void _zoomOut() => _zoomByAnimated(1 / _zoomStep);

  /// Fit-relative zoom level a double-click jumps to (item 25) — matches
  /// `_zoomScale`'s own "1.0 = Fit" convention (see `_ViewerToolbar`'s
  /// `zoomLabel`), not a literal 100%/200%-of-native-pixels figure, since
  /// darkmoon's zoom is defined relative to Fit rather than native
  /// resolution. 2.0 sits comfortably under `_maxZoom` (4.0) so a second
  /// double-click-in is still possible after the initial jump if wanted,
  /// while leaving Ctrl+scroll to reach the rest of the range.
  static const double _doubleTapZoomLevel = 2.0;

  /// Double-click on the image (item 25): zoom in centered on the click
  /// point if currently at Fit or below, or back out to Fit if already
  /// zoomed in — the same toggle Meridian/Photoshop use, adapted to
  /// darkmoon's fit-relative zoom scale.
  void _onDoubleTapZoom(Offset localPosition) {
    if (_zoomScale > 1.0) {
      _resetZoom();
    } else {
      _zoomBy(_doubleTapZoomLevel / _zoomScale, anchor: localPosition);
    }
  }

  /// Ctrl+scroll (Cmd+scroll on macOS) zooms, anchored at the cursor;
  /// plain scroll does nothing, matching the Python app's wheelEvent
  /// behavior.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_commandModifierHeld) {
      return;
    }
    final factor = event.scrollDelta.dy < 0 ? _zoomStep : 1 / _zoomStep;
    _zoomBy(factor, anchor: event.localPosition);
  }
}
