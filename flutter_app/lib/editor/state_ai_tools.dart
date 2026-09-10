// The one-shot AI tools behind the toolbar dialogs: AI Denoise, Cloud
// AI, Colorize, and the edit-source swaps they perform.
//
// A `part` of editor_screen.dart holding methods of _EditorScreenState,
// as an extension: same library, same private scope, fields stay on the
// State. `setState` is protected and an extension is not a subclass, so
// these go through the State's `_rebuild`. Split 2026-09-10 for navigation.
part of '../editor_screen.dart';

extension _EditorAiTools on _EditorScreenState {
  /// Opens the AI Denoise dialog (Classic level picker / Enhance neural
  /// toggle / Cloud AI — see `AiDenoiseDialog`) and, if the user confirms a
  /// choice, applies it — a deliberate one-shot action (with its own
  /// loading message) rather than a slider the user drags, matching the
  /// Meridian/Photomator "pick a strength, apply" pattern.
  Future<void> _openAiDenoiseDialog() async {
    if (_openingToolbarDialog) return;
    _openingToolbarDialog = true;
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      _openingToolbarDialog = false;
      return;
    }
    final currentLevel = AiDenoiseParams.fromValues(_paramValues).level;
    final neuralDenoise = (_paramValues[_neuralDenoiseKey] ?? 0.0) > 0;
    final neuralUpscale = (_paramValues[_neuralUpscaleKey] ?? 0.0) > 0;
    final neuralRawDenoise = (_paramValues[_neuralRawDenoiseKey] ?? 0.0) > 0;
    final neuralDenoiseAmount =
        (_paramValues[_neuralDenoiseAmountKey] ?? defaultNeuralDenoiseAmount)
            .round();
    final upscaleSharpnessAmount =
        (_paramValues[_upscaleSharpnessAmountKey] ?? 0.0).round();
    final neuralRestoreDetail = (_paramValues[_restoreDetailKey] ?? 0.0) > 0;
    final restoreDetailAmount =
        (_paramValues[_restoreDetailAmountKey] ?? defaultRestoreDetailAmount)
            .round();
    final cloudProvider = _cloudProviderFromIndex(
      (_paramValues[_cloudDenoiseProviderKey] ?? 0.0).round(),
    );
    final wasNeuralActive =
        neuralDenoise ||
        neuralUpscale ||
        neuralRawDenoise ||
        neuralRestoreDetail;
    final wasAnyPipelineActive =
        wasNeuralActive ||
        cloudProvider != null ||
        (_paramValues[_colorizeKey] ?? 0.0) > 0;
    final rawDenoiseAvailable =
        isRawFile(selected.path) &&
        (_metadata[selected.path]?.isBayerCfa ?? false);
    final choice = await showAnimatedDialog<AiDenoiseChoice>(
      context: context,
      builder: (_) => AiDenoiseDialog(
        initialLevel: currentLevel,
        neuralDenoise: neuralDenoise,
        neuralUpscale: neuralUpscale,
        neuralDenoiseAmount: neuralDenoiseAmount,
        neuralRawDenoise: neuralRawDenoise,
        rawDenoiseAvailable: rawDenoiseAvailable,
        cloudProvider: cloudProvider,
        upscaleSharpnessAmount: upscaleSharpnessAmount,
        neuralRestoreDetail: neuralRestoreDetail,
        restoreDetailAmount: restoreDetailAmount,
      ),
    );
    _openingToolbarDialog = false;
    if (choice == null || !mounted) {
      return;
    }

    switch (choice) {
      case ClassicDenoiseChoice(level: final level):
        _rebuild(() {
          _paramValues = {
            ..._paramValues,
            'AiDenoiseLevel': level == null
                ? 0.0
                : (AiDenoiseLevel.values.indexOf(level) + 1).toDouble(),
            _neuralDenoiseKey: 0.0,
            _neuralUpscaleKey: 0.0,
            _neuralRawDenoiseKey: 0.0,
            _restoreDetailKey: 0.0,
            _cloudDenoiseProviderKey: 0.0,
            _colorizeKey: 0.0,
          };
        });
        // Switching away from a previously-enhanced source: _editSources
        // currently holds the neural-pipeline/cloud buffer, which the
        // classical per-render stage was never meant to run against.
        if (wasAnyPipelineActive) {
          await _revertToNormalEditSource(selected.path);
          if (!mounted) return;
        }
        await _applyAiDenoiseChoiceAndRender(
          selected.path,
          disabling: level == null,
        );
      case NeuralEnhanceChoice(
            denoise: final wantDenoise,
            upscale: final wantUpscale,
            denoiseAmount: final wantDenoiseAmount,
            rawDenoise: final wantRawDenoise,
            upscaleSharpnessAmount: final wantUpscaleSharpnessAmount,
            restoreDetail: final wantRestoreDetail,
            restoreDetailAmount: final wantRestoreDetailAmount,
          )
          when wantDenoise ||
              wantUpscale ||
              wantRawDenoise ||
              wantRestoreDetail:
        _rebuild(() {
          _paramValues = {
            ..._paramValues,
            _neuralDenoiseKey: wantDenoise ? 1.0 : 0.0,
            _neuralUpscaleKey: wantUpscale ? 1.0 : 0.0,
            _neuralDenoiseAmountKey: wantDenoiseAmount.toDouble(),
            _neuralRawDenoiseKey: wantRawDenoise ? 1.0 : 0.0,
            _upscaleSharpnessAmountKey: wantUpscaleSharpnessAmount.toDouble(),
            _restoreDetailKey: wantRestoreDetail ? 1.0 : 0.0,
            _restoreDetailAmountKey: wantRestoreDetailAmount.toDouble(),
            _cloudDenoiseProviderKey: 0.0,
            // _colorizeKey deliberately left alone: Colorize now runs as a
            // pass inside this same pipeline (between denoise and upscale),
            // so applying Enhance no longer has to throw it away. Cloud AI
            // is still exclusive with both — it hands the photo to a remote
            // provider, so there is no local buffer to chain onto.
            'AiDenoiseLevel': 0.0,
          };
        });
        final keepColorize = (_paramValues[_colorizeKey] ?? 0.0) > 0;
        final ok = await _runNeuralEnhance(
          selected.path,
          denoise: wantDenoise,
          upscale: wantUpscale,
          denoiseAmount: wantDenoiseAmount,
          rawDenoise: wantRawDenoise,
          upscaleSharpnessAmount: wantUpscaleSharpnessAmount,
          restoreDetail: wantRestoreDetail,
          restoreDetailAmount: wantRestoreDetailAmount,
          colorize: keepColorize,
          colorizeIntensity:
              (_paramValues[_colorizeIntensityKey] ?? defaultColorizeIntensity)
                  .round(),
        );
        if (!mounted || !ok) {
          return;
        }
        await _applyAiDenoiseChoiceAndRender(selected.path);
      case NeuralEnhanceChoice():
        // All toggles off — equivalent to turning Enhance back off.
        _rebuild(() {
          _paramValues = {
            ..._paramValues,
            _neuralDenoiseKey: 0.0,
            _neuralUpscaleKey: 0.0,
            _neuralRawDenoiseKey: 0.0,
            _restoreDetailKey: 0.0,
          };
        });
        // Colorize may still be on. Reverting to the plain decode would
        // silently drop it while _paramValues still claims it is applied,
        // so re-run it on its own instead.
        if ((_paramValues[_colorizeKey] ?? 0.0) > 0) {
          await _runColorize(
            selected.path,
            intensityPercent:
                (_paramValues[_colorizeIntensityKey] ??
                        defaultColorizeIntensity)
                    .round(),
          );
        } else {
          await _revertToNormalEditSource(selected.path);
        }
        if (!mounted) return;
        await _applyAiDenoiseChoiceAndRender(selected.path, disabling: true);
      case CloudDenoiseChoice(
            provider: final wantProvider,
            apiKey: final wantApiKey,
          )
          when wantProvider != null && wantApiKey.isNotEmpty:
        await CloudDenoiseTokenStore.write(wantProvider, wantApiKey);
        if (!mounted) return;
        _rebuild(() {
          _paramValues = {
            ..._paramValues,
            _neuralDenoiseKey: 0.0,
            _neuralUpscaleKey: 0.0,
            _neuralRawDenoiseKey: 0.0,
            _cloudDenoiseProviderKey: _cloudProviderIndex(
              wantProvider,
            ).toDouble(),
            _colorizeKey: 0.0,
            'AiDenoiseLevel': 0.0,
          };
        });
        final ok = await _runCloudDenoise(
          selected.path,
          provider: wantProvider,
          apiKey: wantApiKey,
        );
        if (!mounted || !ok) {
          return;
        }
        await _applyAiDenoiseChoiceAndRender(selected.path);
      case CloudDenoiseChoice():
        // No provider picked (or an empty key) — equivalent to off.
        _rebuild(() {
          _paramValues = {..._paramValues, _cloudDenoiseProviderKey: 0.0};
        });
        if (wasAnyPipelineActive) {
          await _revertToNormalEditSource(selected.path);
          if (!mounted) return;
        }
        await _applyAiDenoiseChoiceAndRender(selected.path, disabling: true);
    }
  }

  /// Re-decodes [path] the normal way (no neural enhance) and swaps it
  /// into `_editSources` — used when the user turns Enhance back off, or
  /// switches to a Classic level while Enhance was active, since
  /// `_editSources[path]` holds the enhanced (upscaled) buffer until
  /// something replaces it.
  Future<void> _revertToNormalEditSource(String path) async {
    final normalSources = await decodeEditSourcesWithProgress(
      path,
      (_) {},
      previewMaxDimension: _settings.previewResolution,
      editEmbeddedJpeg: _settings.editEmbeddedJpeg,
    );
    if (mounted && normalSources != null) {
      _rebuild(() => _editSources[path] = normalSources);
    }
  }

  /// Opens item 37's Colorize dialog and, if confirmed, applies the
  /// choice — same one-shot-action shape as [_openAiDenoiseDialog], much
  /// simpler since there's only one real setting (intensity), not several
  /// independent toggles to combine.
  Future<void> _openColorizeDialog() async {
    if (_openingToolbarDialog) return;
    _openingToolbarDialog = true;
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      _openingToolbarDialog = false;
      return;
    }
    final active = (_paramValues[_colorizeKey] ?? 0.0) > 0;
    final intensity =
        (_paramValues[_colorizeIntensityKey] ?? defaultColorizeIntensity)
            .round();
    // GPU probed inside ColorizeDialog itself (its own initState), not
    // awaited here before opening — see `probeColorizeGpuSupport`'s doc
    // for the real bug this used to cause (the dialog took however long
    // DirectML session creation takes to even appear, and a rapid second
    // click in that window stacked a second dialog on top).
    final choice = await showAnimatedDialog<ColorizeChoice>(
      context: context,
      builder: (_) =>
          ColorizeDialog(active: active, intensityPercent: intensity),
    );
    _openingToolbarDialog = false;
    if (choice == null || !mounted) {
      return;
    }
    // Colorize and AI Enhance can be applied together (2026-09-03):
    // colorize is a pass *inside* the Enhance pipeline, between denoise
    // and upscale — see `edit_source_ai_enhance.dart`'s `_decodeAndEnhance`
    // for why that spot. Which pipeline actually runs depends on whether
    // any neural toggle is also on:
    //
    //   colorize alone  -> _runColorize, its own dedicated disk cache
    //   colorize + AI   -> _runNeuralEnhance with colorize: true, one
    //                      combined result under the Enhance cache
    //
    // Cloud AI stays exclusive with both: it hands the photo to a remote
    // provider, so there is no local buffer for another pass to chain onto.
    final neuralDenoiseOn = (_paramValues[_neuralDenoiseKey] ?? 0.0) > 0;
    final neuralUpscaleOn = (_paramValues[_neuralUpscaleKey] ?? 0.0) > 0;
    final neuralRawDenoiseOn = (_paramValues[_neuralRawDenoiseKey] ?? 0.0) > 0;
    final neuralRestoreOn = (_paramValues[_restoreDetailKey] ?? 0.0) > 0;
    final anyNeuralOn =
        neuralDenoiseOn ||
        neuralUpscaleOn ||
        neuralRawDenoiseOn ||
        neuralRestoreOn;

    if (choice.active) {
      _rebuild(() {
        _paramValues = {
          ..._paramValues,
          _colorizeKey: 1.0,
          _colorizeIntensityKey: choice.intensityPercent.toDouble(),
          _cloudDenoiseProviderKey: 0.0,
          'AiDenoiseLevel': 0.0,
        };
      });
      final ok = anyNeuralOn
          ? await _runNeuralEnhance(
              selected.path,
              denoise: neuralDenoiseOn,
              upscale: neuralUpscaleOn,
              denoiseAmount:
                  (_paramValues[_neuralDenoiseAmountKey] ??
                          defaultNeuralDenoiseAmount)
                      .round(),
              rawDenoise: neuralRawDenoiseOn,
              upscaleSharpnessAmount:
                  (_paramValues[_upscaleSharpnessAmountKey] ?? 0.0).round(),
              restoreDetail: neuralRestoreOn,
              restoreDetailAmount:
                  (_paramValues[_restoreDetailAmountKey] ??
                          defaultRestoreDetailAmount)
                      .round(),
              colorize: true,
              colorizeIntensity: choice.intensityPercent,
            )
          : await _runColorize(
              selected.path,
              intensityPercent: choice.intensityPercent,
            );
      if (!mounted || !ok) {
        return;
      }
      await _applyColorizeChoiceAndRender(selected.path);
    } else {
      _rebuild(() {
        _paramValues = {..._paramValues, _colorizeKey: 0.0};
      });
      // Enhance may still be on. Reverting to the plain decode would
      // silently drop it while _paramValues still claims it is applied, so
      // re-run it without the colorize pass instead.
      if (anyNeuralOn) {
        await _runNeuralEnhance(
          selected.path,
          denoise: neuralDenoiseOn,
          upscale: neuralUpscaleOn,
          denoiseAmount:
              (_paramValues[_neuralDenoiseAmountKey] ??
                      defaultNeuralDenoiseAmount)
                  .round(),
          rawDenoise: neuralRawDenoiseOn,
          upscaleSharpnessAmount:
              (_paramValues[_upscaleSharpnessAmountKey] ?? 0.0).round(),
          restoreDetail: neuralRestoreOn,
          restoreDetailAmount:
              (_paramValues[_restoreDetailAmountKey] ??
                      defaultRestoreDetailAmount)
                  .round(),
        );
      } else {
        await _revertToNormalEditSource(selected.path);
      }
      if (!mounted) return;
      await _applyColorizeChoiceAndRender(selected.path, disabling: true);
    }
  }

  /// Runs the colorize pipeline (`native/edit_source_colorize.dart`,
  /// disk-cached) for [path] and swaps the result into `_editSources`.
  /// Returns false (having already reverted the `_colorizeKey` marker and
  /// shown a message) on failure — same contract as `_runNeuralEnhance`.
  Future<bool> _runColorize(
    String path, {
    required int intensityPercent,
  }) async {
    _rebuild(() {
      _isRunningColorize = true;
    });
    final cancellation = ColorizeCancellationToken();
    _colorizeCancellation = cancellation;
    final cacheDir = await resolveColorizeCacheDir();
    if (!mounted) return false;
    var cpuWarningShown = false;
    final sources = await decodeEditSourcesWithColorize(
      path,
      cacheDir,
      (stage) {
        if (!mounted) return;
        if (stage is ColorizeModelInfo) {
          DevLog.log(
            'Colorize model: '
            '${stage.usingGpu ? "GPU (${stage.providerLabel})" : "CPU fallback"}'
            '${stage.gpuError == null ? "" : " — GPU unavailable: ${stage.gpuError}"}',
            tag: 'colorize',
          );
          if (!stage.usingGpu && !cpuWarningShown) {
            cpuWarningShown = true;
            _notify(detail: AppLocalizations.of(context)!.colorizeCpuWarning);
          }
        }
      },
      intensityPercent: intensityPercent,
      previewMaxDimension: _settings.previewResolution,
      editEmbeddedJpeg: _settings.editEmbeddedJpeg,
      cancellationToken: cancellation,
    );
    _colorizeCancellation = null;
    if (!mounted) {
      return false;
    }
    if (sources == null) {
      final wasCancelled = cancellation.isCancelled;
      _rebuild(() {
        _paramValues = {..._paramValues, _colorizeKey: 0.0};
        _isRunningColorize = false;
      });
      if (!wasCancelled) {
        _notify(
          detail: AppLocalizations.of(context)!.colorizeFailedMessage,
          status: AppLocalizations.of(context)!.colorizeFailedStatus,
        );
      }
      return false;
    }
    // The pipeline modules build their pair from their own processed
    // pixels and carry no offset, so a run drops it the same way a cache
    // hit does — see [_withMeasuredCameraMatch].
    final measured = await _withMeasuredCameraMatch(path, sources);
    if (!mounted) {
      return false;
    }
    _rebuild(() {
      _editSources[path] = measured;
      _isRunningColorize = false;
    });
    return true;
  }

  /// Renders/persists a colorize choice — same shape as
  /// `_applyAiDenoiseChoiceAndRender`, kept separate since it drives its
  /// own overlay state ([_isApplyingColorize]/[_colorizeDisabling]) rather
  /// than the AI Denoise trio.
  Future<void> _applyColorizeChoiceAndRender(
    String path, {
    bool disabling = false,
  }) async {
    _rebuild(() {
      _isApplyingColorize = true;
      _colorizeDisabling = disabling;
      _colorizeRenderStage = null;
    });
    await _renderPreview(
      path,
      onStage: (stage) {
        if (mounted) {
          _rebuild(() => _colorizeRenderStage = stage);
        }
      },
    );
    if (!mounted) {
      return;
    }
    _rebuild(() {
      _isApplyingColorize = false;
      _colorizeRenderStage = null;
    });
    _pushHistory();
    _scheduleCatalogSave();
  }

  /// Runs item 13's neural Enhance pipeline (AI denoise and/or
  /// DIS 2x [upscale], disk-cached — see
  /// `native/edit_source_ai_enhance.dart`) for [path] and swaps the
  /// result into `_editSources`, so every later render/mask/export builds
  /// on the enhanced buffer instead of the plain decode. Returns false
  /// (having already reverted the `_neuralDenoiseKey`/`_neuralUpscaleKey`
  /// markers and shown a message) on failure, so the caller can skip
  /// rendering/history for a change that didn't actually happen.
  ///
  /// Owns [_isRunningNeuralEnhance]/[_aiEnhanceProgress] end-to-end (set
  /// on entry, cleared on every exit path) — this is the operation that
  /// can take 30s-2min, so without a loading overlay covering exactly
  /// this call the dialog just closes and appears to do nothing for that
  /// whole stretch.
  Future<bool> _runNeuralEnhance(
    String path, {
    required bool denoise,
    required bool upscale,
    int denoiseAmount = 100,
    bool rawDenoise = false,
    int upscaleSharpnessAmount = 0,
    bool restoreDetail = false,
    int restoreDetailAmount = defaultRestoreDetailAmount,
    // Colorize runs inside this pipeline (between denoise and upscale)
    // rather than as its own pass, so the two can be applied together —
    // see `edit_source_ai_enhance.dart`'s `_decodeAndEnhance`. Colorize on
    // its own still goes through [_runColorize] and its own disk cache.
    bool colorize = false,
    int colorizeIntensity = defaultColorizeIntensity,
  }) async {
    _rebuild(() {
      _isRunningNeuralEnhance = true;
      _aiEnhanceProgress = null;
    });
    // The overlay's Cancel button (_cancelLoading) calls .cancel() on this
    // to actually stop waiting instead of just resetting the UI while the
    // isolate keeps running the ONNX inference underneath it.
    final cancellation = AiEnhanceCancellationToken();
    _aiEnhanceCancellation = cancellation;
    final cacheDir = await resolveAiEnhanceCacheDir();
    if (!mounted) return false;
    // Set the first time either model reports a CPU fallback, so the
    // "this will be slower" warning below only ever shows once per run
    // (there are two models, denoise then upscale) instead of twice.
    var cpuWarningShown = false;
    final sources = await decodeEditSourcesWithAiEnhance(
      path,
      cacheDir,
      (stage) {
        if (!mounted) return;
        if (stage is AiEnhanceProgress) {
          _rebuild(() => _aiEnhanceProgress = stage);
        } else if (stage is AiEnhanceModelInfo) {
          DevLog.log(
            'AI Enhance model ${stage.modelName}: '
            '${stage.usingGpu ? "GPU (${stage.providerLabel})" : "CPU fallback"}'
            '${stage.gpuError == null ? "" : " — GPU unavailable: ${stage.gpuError}"}',
            tag: 'ai-enhance',
          );
          if (!stage.usingGpu && !cpuWarningShown) {
            cpuWarningShown = true;
            // No non-dev status equivalent — the AI Denoise dialog itself
            // already warns about this before the user even applies (see
            // probeAiEnhanceGpuSupport), so this is purely a Dev Mode
            // detail at this point, not a first notice.
            _notify(
              detail: AppLocalizations.of(context)!.aiDenoiseEnhanceCpuWarning,
            );
          }
        } else if (stage is CustomDenoiseModelFallback) {
          DevLog.log(
            'Custom denoise model failed, fell back to default: ${stage.reason}',
            tag: 'ai-enhance',
          );
          _notify(
            detail: AppLocalizations.of(
              context,
            )!.aiDenoiseCustomModelFallbackMessage(stage.reason),
            status: AppLocalizations.of(
              context,
            )!.aiDenoiseCustomModelFallbackStatus,
          );
        }
      },
      enableDenoise: denoise,
      enableUpscale: upscale,
      enableRawDenoise: rawDenoise,
      denoiseStrengthPercent: denoiseAmount,
      customDenoiseModelPath: _settings.customDenoiseModelPath,
      previewMaxDimension: _settings.previewResolution,
      editEmbeddedJpeg: _settings.editEmbeddedJpeg,
      cancellationToken: cancellation,
      upscaleSharpnessAmount: upscaleSharpnessAmount,
      enableDetailRestore: restoreDetail,
      detailRestoreAmount: restoreDetailAmount,
      enableColorize: colorize,
      colorizeIntensityPercent: colorizeIntensity,
    );
    _aiEnhanceCancellation = null;
    if (!mounted) {
      return false;
    }
    if (sources == null) {
      final wasCancelled = cancellation.isCancelled;
      _rebuild(() {
        _paramValues = {
          ..._paramValues,
          _neuralDenoiseKey: 0.0,
          _neuralUpscaleKey: 0.0,
          _neuralRawDenoiseKey: 0.0,
          _restoreDetailKey: 0.0,
          // This run owned the colorize pass too when it was asked for, so
          // a failure has to clear that marker as well — leaving it set
          // would claim a colorized base that was never produced.
          if (colorize) _colorizeKey: 0.0,
        };
        _isRunningNeuralEnhance = false;
        _aiEnhanceProgress = null;
      });
      // A deliberate Cancel already reset the overlay in _cancelLoading —
      // showing "AI Enhance couldn't run" on top of that would misreport
      // the user's own action as a failure.
      if (!wasCancelled) {
        _notify(
          detail: AppLocalizations.of(context)!.aiDenoiseEnhanceFailedMessage,
          status: AppLocalizations.of(context)!.aiDenoiseEnhanceFailedStatus,
        );
      }
      return false;
    }
    // The pipeline modules build their pair from their own processed
    // pixels and carry no offset, so a run drops it the same way a cache
    // hit does — see [_withMeasuredCameraMatch].
    final measured = await _withMeasuredCameraMatch(path, sources);
    if (!mounted) {
      return false;
    }
    _rebuild(() {
      _editSources[path] = measured;
      _isRunningNeuralEnhance = false;
      _aiEnhanceProgress = null;
    });
    return true;
  }

  /// Runs the Cloud AI denoise pipeline (`native/edit_source_cloud_denoise
  /// .dart`, disk-cached — see `cloud_denoise_cache.dart` for why: this
  /// costs real money per call) for [path] and swaps the result into
  /// `_editSources`. Returns false (having already reverted
  /// `_cloudDenoiseProviderKey` and shown the real failure reason — a bad
  /// key, a provider error, a network failure — since unlike the local
  /// pipeline these are worth surfacing individually) on failure.
  ///
  /// Owns [_isRunningCloudDenoise]/[_cloudDenoiseStage] end-to-end, same
  /// role [_isRunningNeuralEnhance]/[_aiEnhanceProgress] play for the
  /// on-device pipeline.
  Future<bool> _runCloudDenoise(
    String path, {
    required CloudDenoiseProviderKind provider,
    required String apiKey,
  }) async {
    _rebuild(() {
      _isRunningCloudDenoise = true;
      _cloudDenoiseStage = null;
    });
    final cancellation = CloudDenoiseCancellationToken();
    _cloudDenoiseCancellation = cancellation;
    final cacheDir = await resolveCloudDenoiseCacheDir();
    if (!mounted) return false;

    final result = await decodeEditSourcesWithCloudDenoise(
      path,
      cacheDir,
      (stage) {
        if (mounted) _rebuild(() => _cloudDenoiseStage = stage);
      },
      provider: provider,
      apiKey: apiKey,
      previewMaxDimension: _settings.previewResolution,
      editEmbeddedJpeg: _settings.editEmbeddedJpeg,
      cancellationToken: cancellation,
    );
    _cloudDenoiseCancellation = null;
    if (!mounted) {
      return false;
    }

    switch (result) {
      case CloudDenoiseSuccess(sources: final sources):
        // The pipeline modules build their pair from their own processed
        // pixels and carry no offset, so a run drops it the same way a cache
        // hit does — see [_withMeasuredCameraMatch].
        final measured = await _withMeasuredCameraMatch(path, sources);
        if (!mounted) {
          return false;
        }
        _rebuild(() {
          _editSources[path] = measured;
          _isRunningCloudDenoise = false;
          _cloudDenoiseStage = null;
        });
        return true;
      case CloudDenoiseCancelled():
        // A deliberate Cancel already reset the overlay in _cancelLoading.
        _rebuild(() {
          _paramValues = {..._paramValues, _cloudDenoiseProviderKey: 0.0};
          _isRunningCloudDenoise = false;
          _cloudDenoiseStage = null;
        });
        return false;
      case CloudDenoiseFailed(message: final message):
        _rebuild(() {
          _paramValues = {..._paramValues, _cloudDenoiseProviderKey: 0.0};
          _isRunningCloudDenoise = false;
          _cloudDenoiseStage = null;
        });
        DevLog.log(message, tag: 'cloud-denoise');
        _notify(
          detail: AppLocalizations.of(
            context,
          )!.aiDenoiseCloudFailedMessage(message),
          status: AppLocalizations.of(context)!.aiDenoiseCloudFailedStatus,
        );
        return false;
    }
  }

  /// The loading-overlay/render/history/save sequence shared by every
  /// `_openAiDenoiseDialog` outcome, once `_paramValues`/`_editSources`
  /// already reflect the user's choice.
  Future<void> _applyAiDenoiseChoiceAndRender(
    String path, {
    bool disabling = false,
  }) async {
    _rebuild(() {
      _isApplyingAiDenoise = true;
      _aiDenoiseDisabling = disabling;
      _aiDenoiseRenderStage = null;
    });
    await _renderPreview(
      path,
      onStage: (stage) {
        if (mounted) {
          _rebuild(() => _aiDenoiseRenderStage = stage);
        }
      },
    );
    if (!mounted) {
      return;
    }
    _rebuild(() {
      _isApplyingAiDenoise = false;
      _aiDenoiseRenderStage = null;
    });
    _pushHistory();
    _scheduleCatalogSave();
  }
}
