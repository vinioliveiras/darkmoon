// Masks and curves: the active layer, its geometry, its own values and
// curves, the brush, and the range samplers.
//
// A `part` of editor_screen.dart holding methods of _EditorScreenState,
// as an extension: same library, same private scope, fields stay on the
// State. `setState` is protected and an extension is not a subclass, so
// these go through the State's `_rebuild`. Split 2026-09-10 for navigation.
part of '../editor_screen.dart';

extension _EditorMasks on _EditorScreenState {
  void _onToneCurveChanged(List<CurvePoint> points) {
    _rebuild(() => _currentCurves = _currentCurves.copyWith(tone: points));
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onToneCurveChangeEnd(List<CurvePoint> points) {
    _rebuild(() => _currentCurves = _currentCurves.copyWith(tone: points));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  PhotoCurves _withChannelCurve(String channel, List<CurvePoint> points) {
    switch (channel) {
      case 'red':
        return _currentCurves.copyWith(red: points);
      case 'green':
        return _currentCurves.copyWith(green: points);
      case 'blue':
        return _currentCurves.copyWith(blue: points);
    }
    throw ArgumentError.value(channel, 'channel');
  }

  void _onColorCurveChanged(String channel, List<CurvePoint> points) {
    _rebuild(() => _currentCurves = _withChannelCurve(channel, points));
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onColorCurveChangeEnd(String channel, List<CurvePoint> points) {
    _rebuild(() => _currentCurves = _withChannelCurve(channel, points));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// The slider values the panel should currently show/edit — the global
  /// ones, or (when a mask is being edited) just that mask's own.
  Map<String, double> get _activeValues {
    if (_activeMaskId == imageMaskId) {
      return _paramValues;
    }
    return _activeMask?.values ?? const {};
  }

  /// The Tone Curve/Color Curve the panel should currently show/edit —
  /// mirrors [_activeValues]'s "global, or the active mask's own" split.
  PhotoCurves get _activeCurves {
    if (_activeMaskId == imageMaskId) {
      return _currentCurves;
    }
    return _activeMask?.curves ?? identityPhotoCurves;
  }

  MaskLayer? get _activeMask => _maskStack.active;

  void _onActiveToneCurveChanged(List<CurvePoint> points) {
    if (_activeMaskId == imageMaskId) {
      _onToneCurveChanged(points);
      return;
    }
    _updateActiveMask(
      (mask) => mask.copyWith(curves: mask.curves.copyWith(tone: points)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onActiveToneCurveChangeEnd(List<CurvePoint> points) {
    if (_activeMaskId == imageMaskId) {
      _onToneCurveChangeEnd(points);
      return;
    }
    _updateActiveMask(
      (mask) => mask.copyWith(curves: mask.curves.copyWith(tone: points)),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  PhotoCurves _withActiveChannelCurve(
    PhotoCurves curves,
    String channel,
    List<CurvePoint> points,
  ) {
    switch (channel) {
      case 'red':
        return curves.copyWith(red: points);
      case 'green':
        return curves.copyWith(green: points);
      case 'blue':
        return curves.copyWith(blue: points);
    }
    throw ArgumentError.value(channel, 'channel');
  }

  void _onActiveColorCurveChanged(String channel, List<CurvePoint> points) {
    if (_activeMaskId == imageMaskId) {
      _onColorCurveChanged(channel, points);
      return;
    }
    _updateActiveMask(
      (mask) => mask.copyWith(
        curves: _withActiveChannelCurve(mask.curves, channel, points),
      ),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onActiveColorCurveChangeEnd(String channel, List<CurvePoint> points) {
    if (_activeMaskId == imageMaskId) {
      _onColorCurveChangeEnd(channel, points);
      return;
    }
    _updateActiveMask(
      (mask) => mask.copyWith(
        curves: _withActiveChannelCurve(mask.curves, channel, points),
      ),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onActiveChanged(String name, double value) {
    if (_activeMaskId == imageMaskId) {
      _onParamChanged(name, value);
      return;
    }
    if (!_isAdjustingMaskValue) {
      _rebuild(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask(
      (mask) => mask.copyWith(values: {...mask.values, name: value}),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onActiveChangeEnd(String name, double value) {
    if (_activeMaskId == imageMaskId) {
      _onParamChangeEnd(name, value);
      return;
    }
    _rebuild(() => _isAdjustingMaskValue = false);
    _updateActiveMask(
      (mask) => mask.copyWith(values: {...mask.values, name: value}),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// Resets the whole photo back to its untouched state: global
  /// adjustments, curves, AND every mask — regardless of which layer is
  /// currently being edited. A partial reset (leaving masks behind) would
  /// be surprising for a button labeled "Reset", and there's no separate
  /// per-mask reset affordance, so this is the only way back to a blank
  /// slate.
  Future<void> _resetActive() async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    final wasAnyPipelineActive =
        selected != null &&
        ((_paramValues[_neuralDenoiseKey] ?? 0.0) > 0 ||
            (_paramValues[_neuralUpscaleKey] ?? 0.0) > 0 ||
            (_paramValues[_neuralRawDenoiseKey] ?? 0.0) > 0 ||
            (_paramValues[_restoreDetailKey] ?? 0.0) > 0 ||
            (_paramValues[_cloudDenoiseProviderKey] ?? 0.0) > 0 ||
            (_paramValues[_colorizeKey] ?? 0.0) > 0 ||
            (_paramValues[_inpaintKey] ?? 0.0) > 0);
    if (selected != null) {
      // Removals are an edit too: Reset takes them with the rest.
      _store.inpaints.remove(selected.path);
    }
    _rebuild(() {
      _paramValues = _freshParamValues();
      _currentCurves = identityPhotoCurves;
      _currentMasks = [];
      _activeMaskId = imageMaskId;
      // Reset clears the edit — no preset is "applied" any more.
      _appliedPresetId = null;
    });
    if (wasAnyPipelineActive) {
      // `_editSources[path]` currently holds the AI-pipeline buffer
      // (Enhance/Cloud/Colorize) — resetting `_paramValues` alone left it
      // in place, so the photo kept looking enhanced/colorized after Reset
      // (2026-09-01, real bug report). Revert it the same way turning a
      // pipeline off elsewhere already does (see `wasAnyPipelineActive` in
      // `_openAiDenoiseDialog`).
      await _revertToNormalEditSource(selected.path);
      if (!mounted) return;
    }
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _updateActiveMask(MaskLayer Function(MaskLayer mask) update) {
    _rebuild(() => _maskStack.updateActive(update));
  }

  void _selectMask(String id) {
    _rebuild(() => _maskStack.select(id));
  }

  void _toggleMaskOverlayVisible() {
    _rebuild(() => _maskOverlayVisible = !_maskOverlayVisible);
  }

  void _addMask(MaskType type) {
    final l10n = AppLocalizations.of(context)!;
    final baseName = switch (type) {
      MaskType.linearGradient => l10n.maskLinearGradient,
      MaskType.radialGradient => l10n.maskRadialGradient,
      MaskType.brush => l10n.maskBrush,
      MaskType.colorRange => l10n.maskColorRange,
      MaskType.wholeImage => l10n.maskWholeImage,
      MaskType.luminance => l10n.maskLuminance,
      MaskType.flow => l10n.maskFlow,
      MaskType.subject => l10n.maskSubject,
      MaskType.sky => l10n.maskSky,
      MaskType.foreground => l10n.maskForeground,
      MaskType.depth => l10n.maskDepth,
    };
    _rebuild(() => _maskStack.add(type, baseName));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _toggleActiveMaskEnabled() {
    _updateActiveMask((mask) => mask.copyWith(enabled: !mask.enabled));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _toggleActiveMaskInverted() {
    _updateActiveMask((mask) => mask.copyWith(inverted: !mask.inverted));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onActiveMaskOpacityChanged(double value) {
    if (!_isAdjustingMaskValue) {
      _rebuild(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask((mask) => mask.copyWith(opacity: value));
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onActiveMaskOpacityChangeEnd(double value) {
    _rebuild(() => _isAdjustingMaskValue = false);
    _updateActiveMask((mask) => mask.copyWith(opacity: value));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// Duplicates the active mask into a new sibling layer — same geometry,
  /// slider values and curves, a fresh id, and a "copy" suffix on the
  /// name so it's distinguishable in the switch menu. The clone becomes
  /// the active layer, matching [_addMask]'s "select what you just
  /// created" feel. Which fields a clone carries is [MaskStack.clone]'s
  /// business, and tested there.
  void _cloneActiveMask() {
    final l10n = AppLocalizations.of(context)!;
    if (_maskStack.active == null) {
      return;
    }
    _rebuild(() => _maskStack.clone(l10n.maskCloneSuffix));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _deleteActiveMask() {
    _rebuild(_maskStack.deleteActive);
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onMaskGeometryChanged(MaskLayer updated) {
    _rebuild(() => _maskStack.replace(updated));
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onMaskGeometryChangeEnd(MaskLayer updated) {
    _rebuild(() => _maskStack.replace(updated));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _setBrushRadius(double value) {
    _rebuild(() => _brushRadius = value);
  }

  void _setBrushHardness(double value) {
    _rebuild(() => _brushHardness = value);
  }

  void _toggleBrushErase() {
    _rebuild(() => _brushErase = !_brushErase);
  }

  void _setBrushFlow(double value) {
    _rebuild(() => _brushFlow = value);
  }

  /// Drops the active brush mask's last stroke — the brush equivalent of
  /// undo, since strokes are kept as vector data rather than baked into a
  /// fixed bitmap.
  void _undoLastStroke() {
    final mask = _activeMask;
    if (mask == null || mask.brush.strokes.isEmpty) {
      return;
    }
    _rebuild(_maskStack.undoLastStroke);
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onColorRangeToleranceChanged(double value) {
    if (!_isAdjustingMaskValue) {
      _rebuild(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(tolerance: value)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onColorRangeToleranceChangeEnd(double value) {
    _rebuild(() => _isAdjustingMaskValue = false);
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(tolerance: value)),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onColorRangeFeatherChanged(double value) {
    if (!_isAdjustingMaskValue) {
      _rebuild(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(feather: value)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onColorRangeFeatherChangeEnd(double value) {
    _rebuild(() => _isAdjustingMaskValue = false);
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(feather: value)),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onLuminanceToleranceChanged(double value) {
    if (!_isAdjustingMaskValue) {
      _rebuild(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask(
      (m) => m.copyWith(luminance: m.luminance.copyWith(tolerance: value)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onLuminanceToleranceChangeEnd(double value) {
    _rebuild(() => _isAdjustingMaskValue = false);
    _updateActiveMask(
      (m) => m.copyWith(luminance: m.luminance.copyWith(tolerance: value)),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onLuminanceFeatherChanged(double value) {
    if (!_isAdjustingMaskValue) {
      _rebuild(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask(
      (m) => m.copyWith(luminance: m.luminance.copyWith(feather: value)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onLuminanceFeatherChangeEnd(double value) {
    _rebuild(() => _isAdjustingMaskValue = false);
    _updateActiveMask(
      (m) => m.copyWith(luminance: m.luminance.copyWith(feather: value)),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// The Depth band's three sliders share one pair of handlers rather
  /// than getting three each: they all rewrite the same
  /// [DepthGeometry], and none of them re-runs the model — the depth map
  /// is cached, so a drag here is a band-pass over data already in hand.
  void _onDepthGeometryChanged(DepthGeometry geometry) {
    if (!_isAdjustingMaskValue) {
      _rebuild(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask((m) => m.copyWith(depth: geometry));
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onDepthGeometryChangeEnd(DepthGeometry geometry) {
    _rebuild(() => _isAdjustingMaskValue = false);
    _updateActiveMask((m) => m.copyWith(depth: geometry));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// Samples the currently-rendered preview at normalized ([nx], [ny]) and
  /// sets its luma as the active Luminance mask's target — mirrors
  /// [_onSampleMaskColor] but reduces the sampled pixel to brightness.
  Future<void> _onSampleMaskLuminance(double nx, double ny) async {
    final mask = _activeMask;
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (mask == null || mask.type != MaskType.luminance || selected == null) {
      return;
    }
    final pixel = await _samplePreviewPixel(selected.path, nx, ny);
    if (pixel == null || !mounted) {
      return;
    }
    final luma = luminanceRgb(pixel.r, pixel.g, pixel.b);
    _updateActiveMask(
      (m) => m.copyWith(luminance: m.luminance.copyWith(targetLuma: luma)),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// Samples the currently-rendered preview at normalized ([nx], [ny]) and
  /// sets it as the active Color Range mask's reference color — "what you
  /// see is what you pick", matching the eyedropper's own preview surface.
  Future<void> _onSampleMaskColor(double nx, double ny) async {
    final mask = _activeMask;
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (mask == null || mask.type != MaskType.colorRange || selected == null) {
      return;
    }
    final pixel = await _samplePreviewPixel(selected.path, nx, ny);
    if (pixel == null || !mounted) {
      return;
    }
    _updateActiveMask(
      (m) => m.copyWith(
        colorRange: m.colorRange.copyWith(r: pixel.r, g: pixel.g, b: pixel.b),
      ),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// One pixel (0-255 per channel) of [path]'s currently-displayed render,
  /// at normalized image coordinates ([nx], [ny]).
  ///
  /// Reads straight off the `ui.Image` the canvas is painting. Both mask
  /// eyedroppers used to decode the preview's JPEG with `package:image`
  /// for this; there is no preview JPEG any more (see `render_job.dart`'s
  /// `RenderResult.previewRgba`), and a readback is both cheaper than a
  /// full JPEG decode and exact — "what you see is what you pick" is
  /// literally true now, with no lossy generation in between.
  Future<({double r, double g, double b})?> _samplePreviewPixel(
    String path,
    double nx,
    double ny,
  ) async {
    final displayed = _displayPreview(path);
    if (displayed == null) {
      return null;
    }
    // Own a handle for the duration of the readback: a render landing
    // mid-await would otherwise dispose this image out from under it.
    final image = displayed.clone();
    final ByteData? byteData;
    try {
      byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
    if (byteData == null) {
      return null;
    }
    final rgba = byteData.buffer.asUint8List();
    final px = (nx * (image.width - 1)).round().clamp(0, image.width - 1);
    final py = (ny * (image.height - 1)).round().clamp(0, image.height - 1);
    final i = (py * image.width + px) * 4;
    return (
      r: rgba[i].toDouble(),
      g: rgba[i + 1].toDouble(),
      b: rgba[i + 2].toDouble(),
    );
  }

  /// The camera as-shot white balance for [path] (5500/0 for non-RAW or
  /// before its metadata resolves).
  ({double kelvin, double tint}) _asShotFor(String path) {
    final meta = _metadata[path];
    return (
      kelvin: meta?.asShotKelvin ?? wbDefaultKelvin,
      tint: meta?.asShotTint ?? wbDefaultTint,
    );
  }
}
