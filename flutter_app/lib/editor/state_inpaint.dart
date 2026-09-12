// Object removal (2026-09-12): the brush painted over what should go, a
// mask turned into a removal, the removals a photo carries, and running
// the model over them. After Solstice's inpainting panel: every removal
// is a "patch" that can be hidden or deleted on its own, and it can come
// from any mask, not only the brush.
//
// A `part` of editor_screen.dart holding methods of _EditorScreenState,
// as an extension: same library, same private scope, fields stay on the
// State and `setState` goes through `_rebuild`.
part of '../editor_screen.dart';

extension _EditorInpaint on _EditorScreenState {
  /// The removals applied to [path], oldest first.
  List<Removal> _removalsFor(String path) => _store.inpaints[path] ?? const [];

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

  void _setRemoveGrow(double value) {
    _rebuild(() => _removeGrow = value);
  }

  /// [mask]'s coverage as a removal, rasterised at the preview's
  /// resolution (which is what a colour range or an AI mask needs to be
  /// judged against) and grown by the Expand setting. Null when the
  /// preview is not decoded yet or an AI mask's map is still computing.
  Removal? _rasterizeRemoval(String path, MaskLayer mask, String name) {
    final preview = _editSources[path]?.preview;
    if (preview == null) {
      return null;
    }
    final width = preview.width;
    final height = preview.height;
    final aiMap = _aiMaskMaps[mask.id];
    if (aiMaskTypes.contains(mask.type) && aiMap == null) {
      return null;
    }
    Float32List? buffer;
    if (mask.type == MaskType.colorRange || mask.type == MaskType.luminance) {
      final bytes = preview.rgbBytes;
      buffer = Float32List(bytes.length);
      for (var i = 0; i < bytes.length; i++) {
        buffer[i] = bytes[i].toDouble();
      }
    }
    var alpha = computeMaskAlpha(
      mask,
      width,
      height,
      sourceForColorRange: buffer,
      aiMap: aiMap,
    );
    final grow = (_removeGrow / 100 * width).round();
    if (grow > 0) {
      alpha = dilateAlpha(alpha, width, height, grow);
    }
    final longer = math.max(width, height);
    var storedWidth = width;
    var storedHeight = height;
    if (longer > removalMaxDimension) {
      final scale = removalMaxDimension / longer;
      storedWidth = math.max(1, (width * scale).round());
      storedHeight = math.max(1, (height * scale).round());
      alpha = resampleAlpha(alpha, width, height, storedWidth, storedHeight);
    }
    return Removal(
      name: name,
      width: storedWidth,
      height: storedHeight,
      alphaPng: encodeAlphaPng(alpha, storedWidth, storedHeight),
    );
  }

  /// Commits the painted strokes as one more removal of the selected
  /// photo and runs the model.
  Future<void> _runRemoval() async {
    if (_removeStrokes.strokes.isEmpty) {
      return;
    }
    await _addRemovalFrom(_removeLayer);
  }

  /// One more removal from a mask of the stack, by id.
  Future<void> _removeWithMask(String maskId) async {
    final mask = _currentMasks.where((m) => m.id == maskId).firstOrNull;
    if (mask == null) {
      return;
    }
    await _addRemovalFrom(mask);
  }

  Future<void> _addRemovalFrom(MaskLayer mask) async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null || _isRunningInpaint) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final path = selected.path;
    final previous = _removalsFor(path);
    final removal = _rasterizeRemoval(
      path,
      mask,
      l10n.removePatchName(previous.length + 1),
    );
    if (removal == null) {
      _notify(
        detail: l10n.removeMaskNotReadyMessage,
        status: l10n.removeMaskNotReadyMessage,
      );
      return;
    }
    await _setRemovals(path, previous, [...previous, removal]);
  }

  Future<void> _toggleRemovalVisible(int index) async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null || _isRunningInpaint) {
      return;
    }
    final previous = _removalsFor(selected.path);
    if (index < 0 || index >= previous.length) {
      return;
    }
    final next = [...previous];
    next[index] = previous[index].copyWith(visible: !previous[index].visible);
    await _setRemovals(selected.path, previous, next);
  }

  Future<void> _deleteRemoval(int index) async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null || _isRunningInpaint) {
      return;
    }
    final previous = _removalsFor(selected.path);
    if (index < 0 || index >= previous.length) {
      return;
    }
    final next = [...previous]..removeAt(index);
    await _setRemovals(selected.path, previous, next);
  }

  Future<void> _setRemovals(
    String path,
    List<Removal> previous,
    List<Removal> removals,
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
  void _storeRemovals(String path, List<Removal> removals) {
    if (removals.isEmpty) {
      _store.inpaints.remove(path);
    } else {
      _store.inpaints[path] = removals;
    }
    _rebuild(() {
      _paramValues = {..._paramValues, _inpaintKey: removals.length.toDouble()};
    });
  }

  /// The photo's plain preview — before any removal — for the worker to
  /// apply the removals to at the editor's resolution. The preview cache
  /// holds it (it is what a photo without a pipeline was cached as); the
  /// live source is it too while no removal has been applied yet. Null
  /// when neither is at hand, and the worker decodes the file instead.
  Future<InpaintPreviewSource?> _plainPreviewFor(String path) async {
    if (_removalsFor(path).isEmpty || (_paramValues[_inpaintKey] ?? 0) <= 0) {
      final preview = _editSources[path]?.preview;
      if (preview != null) {
        return InpaintPreviewSource(
          preview.width,
          preview.height,
          preview.rgbBytes,
        );
      }
    }
    final cachedJpeg = await _previewCache?.lookup(path);
    if (cachedJpeg == null || !mounted) {
      return null;
    }
    final pair = await compute(decodeEditSourcePairFromCachedJpeg, cachedJpeg);
    final preview = pair?.preview;
    if (preview == null) {
      return null;
    }
    return InpaintPreviewSource(
      preview.width,
      preview.height,
      preview.rgbBytes,
    );
  }

  /// Swaps [path]'s edit source for its removals' result — or for the
  /// plain decode when [removals] is empty. False when the run failed or
  /// was cancelled (a message is shown for a failure).
  ///
  /// Applied at the preview's resolution when the plain preview is at
  /// hand (see [_plainPreviewFor]); export computes the full-resolution
  /// result on its own.
  Future<bool> _applyRemovals(String path, List<Removal> removals) async {
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
    final plain = await _plainPreviewFor(path);
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
      preview: plain,
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
      // The full-resolution result, computed now: the editor only ever
      // applied the removals to the preview.
      _rebuild(() {
        _isRunningInpaint = true;
        _inpaintProgress = null;
      });
      final cancellation = InpaintCancellationToken();
      _inpaintCancellation = cancellation;
      final full = await decodeEditSourcesWithInpaint(
        path,
        cacheDir,
        (stage) {
          if (mounted && stage is InpaintProgress) {
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
        return null;
      }
      _rebuild(() {
        _isRunningInpaint = false;
        _inpaintProgress = null;
      });
      if (full == null) {
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
