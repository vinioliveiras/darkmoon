// Export of the current photo.
//
// A `part` of editor_screen.dart holding methods of _EditorScreenState,
// as an extension: same library, same private scope, fields stay on the
// State. `setState` is protected and an extension is not a subclass, so
// these go through the State's `_rebuild`. Split 2026-09-10 for navigation.
part of '../editor_screen.dart';

extension _EditorExport on _EditorScreenState {
  Future<void> _exportCurrent() async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null || _exporting) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final metadata = _metadata[selected.path];
    final options = await showAnimatedDialog<ExportOptions>(
      context: context,
      builder: (_) => ExportOptionsDialog(
        nativeWidth: metadata?.width,
        nativeHeight: metadata?.height,
      ),
    );
    if (options == null) {
      return;
    }
    final baseName = p.basenameWithoutExtension(selected.path);
    final destPath = await FilePicker.saveFile(
      dialogTitle: l10n.exportPhotoDialogTitle,
      fileName: '${baseName}_edit.${options.format.extension}',
      type: FileType.custom,
      allowedExtensions: [options.format.extension],
    );
    if (destPath == null || !mounted) {
      return;
    }

    _rebuild(() {
      _exporting = true;
      _exportCancellation = ExportCancellationToken();
      _exportStage = ExportStage.decoding;
    });

    // Skip the RAW demosaic in the export isolate if we already have (or
    // can cheaply get) the photo's decoded native source — the editor's
    // full-quality source, the shared cache, or one fresh decode that then
    // warms the cache for next time. This is the dominant export cost,
    // especially for X-Trans.
    //
    // If AI Enhance is active for this photo, that "native source" must
    // be the enhanced buffer, not a plain RAW decode — see
    // _loadEnhancedNativeSource's doc for the bug this fixes.
    final wantDenoise = (_paramValues[_neuralDenoiseKey] ?? 0.0) > 0;
    final wantUpscale = (_paramValues[_neuralUpscaleKey] ?? 0.0) > 0;
    final wantRawDenoise = (_paramValues[_neuralRawDenoiseKey] ?? 0.0) > 0;
    final wantDenoiseAmount =
        (_paramValues[_neuralDenoiseAmountKey] ?? defaultNeuralDenoiseAmount)
            .round();
    final wantUpscaleSharpnessAmount =
        (_paramValues[_upscaleSharpnessAmountKey] ?? 0.0).round();
    final wantRestoreDetail = (_paramValues[_restoreDetailKey] ?? 0.0) > 0;
    final wantRestoreDetailAmount =
        (_paramValues[_restoreDetailAmountKey] ?? defaultRestoreDetailAmount)
            .round();
    final wantCloudProvider = _cloudProviderFromIndex(
      (_paramValues[_cloudDenoiseProviderKey] ?? 0.0).round(),
    );
    final wantColorize = (_paramValues[_colorizeKey] ?? 0.0) > 0;
    final wantColorizeIntensity =
        (_paramValues[_colorizeIntensityKey] ?? defaultColorizeIntensity)
            .round();
    final wantInpaint =
        (_paramValues[_inpaintKey] ?? 0.0) > 0 &&
        _removalsFor(selected.path).isNotEmpty;
    EditSource? nativeForExport;
    final srcSw = Stopwatch()..start();
    try {
      if (wantDenoise || wantUpscale || wantRawDenoise || wantRestoreDetail) {
        // Colorize rides along inside the Enhance pipeline when both are
        // on (it is a pass between denoise and upscale, not a separate
        // base) — the `else if (wantColorize)` branch below is only for
        // colorize on its own.
        nativeForExport = await _loadEnhancedNativeSource(
          selected.path,
          denoise: wantDenoise,
          upscale: wantUpscale,
          denoiseAmount: wantDenoiseAmount,
          rawDenoise: wantRawDenoise,
          upscaleSharpnessAmount: wantUpscaleSharpnessAmount,
          restoreDetail: wantRestoreDetail,
          restoreDetailAmount: wantRestoreDetailAmount,
          colorize: wantColorize,
          colorizeIntensity: wantColorizeIntensity,
        );
      } else if (wantCloudProvider != null) {
        nativeForExport = await _loadCloudDenoisedNativeSource(
          selected.path,
          wantCloudProvider,
        );
      } else if (wantColorize) {
        nativeForExport = await _loadColorizedNativeSource(
          selected.path,
          intensityPercent: wantColorizeIntensity,
        );
      } else if (wantInpaint) {
        nativeForExport = await _loadInpaintedNativeSource(selected.path);
      }
      nativeForExport ??= await _loadNativeSource(
        selected.path,
        lowPriority: false,
      );
    } catch (e, st) {
      // Falls back to decoding inside the export isolate — correct, just
      // slower, and for an AI pipeline source it means re-running the
      // whole thing. Worth knowing why when an export takes minutes
      // longer than the same photo did last time.
      DevLog.logError(
        'export source preload failed, decoding in the export isolate',
        e,
        st,
      );
      nativeForExport = null;
    }
    final srcMs = srcSw.elapsedMilliseconds;
    final srcTiming = nativeForExport == null
        ? null
        : 'source (decode+cache) ${srcMs}ms';
    if (!mounted || _exportCancellation?.isCancelled == true) {
      _rebuild(() {
        _exporting = false;
        _exportStage = null;
      });
      return;
    }

    final result = await exportPhotoWithProgress(
      ExportRequest(
        sourcePath: selected.path,
        editEmbeddedJpeg: _settings.editEmbeddedJpeg,
        destPath: destPath,
        params: RenderParams.fromValues(
          _effectiveParamValues(),
          curves: _effectiveCurves,
          asShotKelvin: metadata?.asShotKelvin ?? wbDefaultKelvin,
          asShotTint: metadata?.asShotTint ?? wbDefaultTint,
          baseExposureStops: _baseExposureFor(selected.path),
          baseContrast: _baseContrastFor(selected.path),
          colorProfile: _colorProfileFor(selected.path),
          colorProfileStrength: _effectiveColorProfileStrength,
        ),
        masks: _effectiveMasks,
        // The same maps the preview was rendered with, so an AI mask
        // exports as what the user was looking at when they hit Export.
        aiMaskMaps: _aiMaskMaps,
        format: options.format,
        quality: options.quality,
        cropTransform: _cropTransform,
        scalePercent: options.scalePercent,
        preDecodedRgb: nativeForExport?.rgbBytes,
        preDecodedWidth: nativeForExport?.width,
        preDecodedHeight: nativeForExport?.height,
        captureInfo: metadata == null
            ? null
            : ExportCaptureInfo.fromRawMetadata(metadata),
      ),
      (stage) {
        if (mounted) {
          _rebuild(() => _exportStage = stage);
        }
      },
      cancellationToken: _exportCancellation,
    );
    final wasCancelled = result.error == 'Export cancelled';
    _exportCancellation = null;
    if (!mounted) {
      return;
    }
    _rebuild(() {
      _exporting = false;
      _exportStage = null;
    });
    if (!wasCancelled) {
      final timingLine = _showExportTimings
          ? [
              if (srcTiming != null) srcTiming,
              if (result.timings != null) result.timings!,
            ].join('\n')
          : '';
      final detail = result.success
          ? '${l10n.exportSuccessMessage(result.destPath!)}'
                '${timingLine.isEmpty ? '' : '\n$timingLine'}'
          : l10n.exportFailureMessage(result.error!);
      _notify(
        detail: detail,
        status: result.success
            ? l10n.exportDoneStatus
            : l10n.exportFailedStatus,
      );
    }
  }
}
