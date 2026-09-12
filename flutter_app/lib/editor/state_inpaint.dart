// Object removal (2026-09-12): the brush painted over what should go,
// the removals a photo carries, and running the model over them.
//
// A `part` of editor_screen.dart holding methods of _EditorScreenState,
// as an extension: same library, same private scope, fields stay on the
// State and `setState` goes through `_rebuild`.
part of '../editor_screen.dart';

extension _EditorInpaint on _EditorScreenState {
  /// The removals applied to [path], oldest first.
  List<BrushGeometry> _removalsFor(String path) =>
      _store.inpaints[path] ?? const [];

  /// Whether the selected photo is showing removals — its source is the
  /// model's result, not the plain decode.
  bool get _removalsActive {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    return selected != null &&
        (_paramValues[_inpaintKey] ?? 0.0) > 0 &&
        _removalsFor(selected.path).isNotEmpty;
  }

  /// Whether one of the other source pipelines (AI Enhance, Cloud AI,
  /// Colorize) is on. They decode from the file, so they cannot see a
  /// removal, and a removal cannot see them: one or the other, for now.
  bool get _otherSourcePipelineActive =>
      (_paramValues[_neuralDenoiseKey] ?? 0.0) > 0 ||
      (_paramValues[_neuralUpscaleKey] ?? 0.0) > 0 ||
      (_paramValues[_neuralRawDenoiseKey] ?? 0.0) > 0 ||
      (_paramValues[_restoreDetailKey] ?? 0.0) > 0 ||
      (_paramValues[_cloudDenoiseProviderKey] ?? 0.0) > 0 ||
      (_paramValues[_colorizeKey] ?? 0.0) > 0;

  /// The strokes being painted, as the brush layer the canvas edits.
  MaskLayer get _removeLayer => MaskLayer(
    id: _removeLayerId,
    name: 'removal',
    type: MaskType.brush,
    brush: _removeStrokes,
  );

  void _toggleRemoveMode() {
    if (!_removeModeActive && _otherSourcePipelineActive) {
      _notify(detail: AppLocalizations.of(context)!.removeUnavailableMessage);
      return;
    }
    unawaited(_flushCurrentEdits());
    _rebuild(() {
      _removeModeActive = !_removeModeActive;
      _removeStrokes = const BrushGeometry();
    });
  }

  void _onRemoveStrokesChanged(MaskLayer layer) {
    _rebuild(() => _removeStrokes = layer.brush);
  }

  void _undoRemoveStroke() {
    final strokes = _removeStrokes.strokes;
    if (strokes.isEmpty) {
      return;
    }
    _rebuild(
      () => _removeStrokes = _removeStrokes.copyWith(
        strokes: strokes.sublist(0, strokes.length - 1),
      ),
    );
  }

  void _clearRemoveStrokes() {
    _rebuild(() => _removeStrokes = const BrushGeometry());
  }

  /// Commits the painted strokes as one more removal of the selected
  /// photo and runs the model. On failure the removal is taken back.
  Future<void> _runRemoval() async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null ||
        _removeStrokes.strokes.isEmpty ||
        _isRunningInpaint) {
      return;
    }
    final path = selected.path;
    final previous = _removalsFor(path);
    final removals = [...previous, _removeStrokes];
    await _setRemovals(path, previous, removals);
  }

  /// Drops the selected photo's last removal and recomputes the rest.
  Future<void> _undoLastRemoval() async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null || _isRunningInpaint) {
      return;
    }
    final path = selected.path;
    final previous = _removalsFor(path);
    if (previous.isEmpty) {
      return;
    }
    await _setRemovals(
      path,
      previous,
      previous.sublist(0, previous.length - 1),
    );
  }

  Future<void> _setRemovals(
    String path,
    List<BrushGeometry> previous,
    List<BrushGeometry> removals,
  ) async {
    _storeRemovals(path, removals);
    _rebuild(() => _removeStrokes = const BrushGeometry());
    final ok = await _applyRemovals(path, removals);
    if (!mounted) {
      return;
    }
    if (!ok) {
      _storeRemovals(path, previous);
      return;
    }
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// Records [removals] as [path]'s, in the store and as the marker in
  /// the slider values that says the source carries them.
  void _storeRemovals(String path, List<BrushGeometry> removals) {
    if (removals.isEmpty) {
      _store.inpaints.remove(path);
    } else {
      _store.inpaints[path] = removals;
    }
    _rebuild(() {
      _paramValues = {..._paramValues, _inpaintKey: removals.length.toDouble()};
    });
  }

  /// Swaps [path]'s edit source for its removals' result — or for the
  /// plain decode when [removals] is empty. False when the run failed or
  /// was cancelled (a message is shown for a failure).
  Future<bool> _applyRemovals(String path, List<BrushGeometry> removals) async {
    if (removals.isEmpty) {
      await _revertToNormalEditSource(path);
      return mounted;
    }
    _rebuild(() {
      _isRunningInpaint = true;
      _inpaintProgress = null;
    });
    final cancellation = InpaintCancellationToken();
    _inpaintCancellation = cancellation;
    final cacheDir = await resolveInpaintCacheDir();
    if (!mounted) {
      return false;
    }
    final sources = await decodeEditSourcesWithInpaint(
      path,
      cacheDir,
      (stage) {
        if (!mounted) {
          return;
        }
        if (stage is InpaintModelInfo) {
          DevLog.log(
            'Inpaint model: '
            '${stage.usingGpu ? "GPU (${stage.providerLabel})" : "CPU"}'
            '${stage.gpuError == null ? "" : " — GPU unavailable: ${stage.gpuError}"}',
            tag: 'inpaint',
          );
        } else if (stage is InpaintProgress) {
          _rebuild(() => _inpaintProgress = stage);
        }
      },
      removals: removals,
      previewMaxDimension: _settings.previewResolution,
      editEmbeddedJpeg: _settings.editEmbeddedJpeg,
      cancellationToken: cancellation,
    );
    _inpaintCancellation = null;
    if (!mounted) {
      return false;
    }
    if (sources == null) {
      _rebuild(() {
        _isRunningInpaint = false;
        _inpaintProgress = null;
      });
      if (!cancellation.isCancelled) {
        final l10n = AppLocalizations.of(context)!;
        _notify(
          detail: l10n.removeFailedMessage,
          status: l10n.removeFailedStatus,
        );
      }
      return false;
    }
    final measured = await _withMeasuredCameraMatch(path, sources);
    if (!mounted) {
      return false;
    }
    _rebuild(() {
      _editSources[path] = measured;
      _isRunningInpaint = false;
      _inpaintProgress = null;
    });
    return true;
  }

  /// Export's source for a photo with removals: the cached full-resolution
  /// result, computed again first when the cache has been cleared.
  Future<EditSource?> _loadInpaintedNativeSource(String path) async {
    final removals = _removalsFor(path);
    if (removals.isEmpty) {
      return null;
    }
    final cacheDir = await resolveInpaintCacheDir();
    if (!mounted) {
      return null;
    }
    final key = inpaintRemovalsKey(removals);
    var png = await lookupInpaintCache(cacheDir, path, removalsKey: key);
    if (png == null) {
      final ok = await _applyRemovals(path, removals);
      if (!mounted || !ok) {
        return null;
      }
      png = await lookupInpaintCache(cacheDir, path, removalsKey: key);
    }
    if (png == null || !mounted) {
      return null;
    }
    return compute(decodeInpaintCacheEntry, png);
  }
}
