// AI masks: when to ask the models again, and running them.
//
// A `part` of editor_screen.dart holding methods of _EditorScreenState,
// as an extension: same library, same private scope, fields stay on the
// State. `setState` is protected and an extension is not a subclass, so
// these go through the State's `_rebuild`. Split 2026-09-10 for navigation.
part of '../editor_screen.dart';

extension _EditorAiMasks on _EditorScreenState {
  /// Everything an AI mask's model output depends on, as one string:
  /// which model, what the user aimed it at, and the geometry of the frame
  /// the model will be shown.
  ///
  /// Deliberately coarse — it decides only *whether to ask*. The
  /// authoritative key is the hash of the actual frame pixels that
  /// `ai_mask_resolver.dart` takes, so a signature that changes without
  /// the pixels changing costs a cache hit, not a re-inference.
  String _aiMaskSignatureFor(MaskLayer mask) {
    final crop = _cropTransform
        .toValues()
        .entries
        .map((e) => '${e.key}=${e.value.toStringAsFixed(4)}')
        .join(',');
    final lens = _lensCorrection.enabled
        ? 'lens:${_lensCorrection.manualProfileKeyHash ?? "auto"}:'
              '${_lensCorrection.distortionAmount}'
        : 'lens:off';
    final prompt = mask.type == MaskType.subject
        ? AiMaskRequest(
            maskId: mask.id,
            type: mask.type,
            subject: mask.subject,
          ).promptKey
        : '';
    return '${mask.type.name}|$prompt|$crop|$lens';
  }

  /// Runs the models behind any AI mask whose answer is missing or stale,
  /// then re-renders with the results.
  ///
  /// Fire-and-forget, deliberately: inference takes seconds, and a render
  /// must not wait on it. Until a map lands, its mask contributes nothing
  /// and the photo renders as if it weren't there — so the first frame
  /// after adding a Sky mask is the unmasked photo, and the masked one
  /// follows.
  Future<void> _resolveAiMasks(String path) async {
    if (_aiMaskMapsPath != path) {
      _aiMaskMapsPath = path;
      _aiMaskMaps.clear();
      _aiMaskSignatures.clear();
      _aiMaskFailures.clear();
    }
    final wanted = <String, AiMaskRequest>{};
    final live = <String>{};
    for (final mask in _currentMasks) {
      if (!aiMaskTypes.contains(mask.type)) {
        continue;
      }
      live.add(mask.id);
      if (!mask.enabled) {
        continue;
      }
      if (_aiMaskSignatures[mask.id] == _aiMaskSignatureFor(mask)) {
        continue;
      }
      wanted[mask.id] = AiMaskRequest(
        maskId: mask.id,
        type: mask.type,
        subject: mask.subject,
      );
    }
    // Deleting a mask should not leave its map (or its error) behind.
    _aiMaskMaps.removeWhere((id, _) => !live.contains(id));
    _aiMaskSignatures.removeWhere((id, _) => !live.contains(id));
    _aiMaskFailures.removeWhere((id, _) => !live.contains(id));
    if (wanted.isEmpty) {
      return;
    }
    if (_aiMasksResolving.isNotEmpty) {
      // One run at a time — these are CPU-bound and hold a 100 MB model.
      // The flag makes the run in flight start another when it finishes,
      // so a box dragged during inference isn't dropped.
      _aiMaskResolvePending = true;
      return;
    }

    final sources = _editSources[path];
    if (sources == null) {
      return;
    }
    final cacheDir = _aiMaskCacheDir ??= await resolveAiMaskCacheDir();
    if (!mounted || _aiMaskMapsPath != path) {
      return;
    }

    // Snapshot what was asked, so a signature recorded on completion is
    // the one the answer actually belongs to.
    final askedSignatures = {
      for (final mask in _currentMasks)
        if (wanted.containsKey(mask.id)) mask.id: _aiMaskSignatureFor(mask),
    };
    final metadata = _metadata[path];
    _rebuild(() => _aiMasksResolving.addAll(wanted.keys));
    AiMaskResolveResult result;
    try {
      result = await compute(
        resolveAiMaskMaps,
        AiMaskResolveRequest(
          // The preview source rather than the live or full-quality one,
          // always: it keeps the map's quality — and the cache key behind
          // it — from depending on which render happened to trigger this.
          source: sources.preview,
          requests: wanted.values.toList(),
          cacheDir: cacheDir,
          cropTransform: _cropTransform,
          lensCorrection: _lensCorrection,
          lensProfile: _resolvedLensProfileFor(path),
          focalLengthMm: metadata?.focalLengthMm ?? 0,
          apertureFNumber: metadata?.apertureFNumber ?? 0,
        ),
      );
    } catch (e) {
      result = AiMaskResolveResult(
        maps: const {},
        failures: {for (final id in wanted.keys) id: '$e'},
      );
    }
    if (!mounted) {
      return;
    }
    _rebuild(() {
      _aiMasksResolving.removeAll(wanted.keys);
      if (_aiMaskMapsPath == path) {
        for (final entry in result.maps.entries) {
          _aiMaskMaps[entry.key] = entry.value;
          _aiMaskSignatures[entry.key] = askedSignatures[entry.key]!;
          _aiMaskFailures.remove(entry.key);
        }
        _aiMaskFailures.addAll(result.failures);
      }
    });
    for (final entry in result.failures.entries) {
      debugPrint('AI mask ${entry.key} failed: ${entry.value}');
    }
    if (_aiMaskResolvePending) {
      _aiMaskResolvePending = false;
      unawaited(_resolveAiMasks(path));
      return;
    }
    if (result.maps.isNotEmpty && _aiMaskMapsPath == path) {
      _scheduleRender(live: false);
    }
  }
}
