// The Albums "Convert negative" dialog (2026-09-12), Solstice's Negative
// Conversion modal: a live preview of the first photo, the colour timing
// (three channel weights) and print grade (exposure, contrast) sliders,
// hold-to-compare with the original, and Convert & Save for every photo
// the menu was opened on. The pixels come from
// `negative_converter.dart` through `compute`; the dialog only draws.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../motion.dart';
import '../raw_files.dart';
import '../render/negative.dart';
import '../theme.dart';
import '../widgets/dialog_chrome.dart';
import '../widgets/slider_row.dart';
import 'negative_converter.dart';

/// What the dialog resolves with: the positives written, in the order
/// of [NegativeConversionDialog.files]. Empty when cancelled.
class NegativeConversionResult {
  const NegativeConversionResult(this.written, this.failed);
  final List<String> written;
  final List<String> failed;
}

class NegativeConversionDialog extends StatefulWidget {
  const NegativeConversionDialog({
    super.key,
    required this.files,
    required this.previewJpegFor,
    required this.convert,
  });

  /// The photos to convert; the first one is previewed.
  final List<RawFile> files;

  /// A JPEG of [files.first] at any size — the preview or thumbnail cache.
  final Future<Uint8List?> Function(RawFile file) previewJpegFor;

  /// Converts one file, returning the positive's path (throws on failure).
  final Future<String> Function(RawFile file, NegativeParams params) convert;

  @override
  State<NegativeConversionDialog> createState() =>
      _NegativeConversionDialogState();
}

class _NegativeConversionDialogState extends State<NegativeConversionDialog> {
  static const _previewMaxDim = 900;

  NegativeParams _params = const NegativeParams(enabled: true);
  NegativePreviewBase? _base;
  ui.Image? _preview;
  bool _previewMissing = false;
  bool _comparing = false;
  Timer? _debounce;
  int _renderSerial = 0;

  /// null while idle; (done, total) while converting.
  ({int done, int total})? _progress;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBase());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _loadBase() async {
    final jpeg = await widget.previewJpegFor(widget.files.first);
    if (!mounted) return;
    if (jpeg == null) {
      setState(() => _previewMissing = true);
      return;
    }
    final base = await compute(decodeNegativePreviewBase, (
      jpeg: jpeg,
      maxDim: _previewMaxDim,
    ));
    if (!mounted) return;
    if (base == null) {
      setState(() => _previewMissing = true);
      return;
    }
    _base = base;
    await _render();
  }

  Future<void> _render() async {
    final base = _base;
    if (base == null) return;
    final serial = ++_renderSerial;
    final params = _comparing
        ? const NegativeParams(enabled: false)
        : _params;
    final rgba = await compute(renderNegativePreviewRgba, (
      base: base,
      params: params,
    ));
    if (!mounted || serial != _renderSerial) return;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      base.width,
      base.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    if (!mounted || serial != _renderSerial) {
      image.dispose();
      return;
    }
    setState(() {
      _preview?.dispose();
      _preview = image;
    });
  }

  void _update(NegativeParams next) {
    setState(() => _params = next);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 40), () {
      unawaited(_render());
    });
  }

  void _setComparing(bool value) {
    if (_comparing == value) return;
    setState(() => _comparing = value);
    unawaited(_render());
  }

  Future<void> _convertAll() async {
    final files = widget.files;
    setState(() => _progress = (done: 0, total: files.length));
    final written = <String>[];
    final failed = <String>[];
    for (var i = 0; i < files.length; i++) {
      try {
        written.add(await widget.convert(files[i], _params));
      } catch (_) {
        failed.add(files[i].path);
      }
      if (!mounted) return;
      setState(() => _progress = (done: i + 1, total: files.length));
    }
    if (!mounted) return;
    Navigator.of(context).pop(NegativeConversionResult(written, failed));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: DarkmoonColors.textMuted);
    final progress = _progress;
    final busy = progress != null;
    return AlertDialog(
      backgroundColor: DarkmoonColors.dialogBackground,
      shape: dialogShape,
      title: Text(
        l10n.negativeDialogTitle,
        style: const TextStyle(color: DarkmoonColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 720,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview: hold to see the negative as it is.
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTapDown: (_) => _setComparing(true),
                    onTapUp: (_) => _setComparing(false),
                    onTapCancel: () => _setComparing(false),
                    child: Container(
                      height: 360,
                      decoration: BoxDecoration(
                        color: DarkmoonColors.canvas,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: _preview != null
                          ? AnimatedSwitcher(
                              duration: DarkmoonMotion.of(
                                context,
                                DarkmoonMotion.fast,
                              ),
                              child: RawImage(
                                key: ValueKey(_preview),
                                image: _preview,
                                fit: BoxFit.contain,
                              ),
                            )
                          : _previewMissing
                          ? Text(l10n.negativePreviewUnavailable, style: muted)
                          : const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _comparing
                        ? l10n.negativeOriginalLabel
                        : l10n.negativeCompareHint,
                    style: muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            // Controls.
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.negativeColorTimingLabel, style: muted),
                  const SizedBox(height: 6),
                  SliderRow(
                    name: l10n.negativeRedLabel,
                    min: 0.5,
                    max: 2.0,
                    value: _params.redWeight,
                    defaultValue: 1.0,
                    onChanged: (v) =>
                        _update(_params.copyWith(redWeight: v)),
                  ),
                  SliderRow(
                    name: l10n.negativeGreenLabel,
                    min: 0.5,
                    max: 2.0,
                    value: _params.greenWeight,
                    defaultValue: 1.0,
                    onChanged: (v) =>
                        _update(_params.copyWith(greenWeight: v)),
                  ),
                  SliderRow(
                    name: l10n.negativeBlueLabel,
                    min: 0.5,
                    max: 2.0,
                    value: _params.blueWeight,
                    defaultValue: 1.0,
                    onChanged: (v) =>
                        _update(_params.copyWith(blueWeight: v)),
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.negativePrintGradeLabel, style: muted),
                  const SizedBox(height: 6),
                  SliderRow(
                    name: l10n.negativeExposureLabel,
                    min: -2.0,
                    max: 2.0,
                    value: _params.exposure,
                    defaultValue: 0.0,
                    onChanged: (v) =>
                        _update(_params.copyWith(exposure: v)),
                  ),
                  SliderRow(
                    name: l10n.negativeContrastLabel,
                    min: 0.5,
                    max: 2.5,
                    value: _params.contrast,
                    defaultValue: 1.0,
                    onChanged: (v) =>
                        _update(_params.copyWith(contrast: v)),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy
                          ? null
                          : () =>
                                _update(const NegativeParams(enabled: true)),
                      child: Text(l10n.resetTooltip),
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress.total == 0
                          ? null
                          : progress.done / progress.total,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.negativeConvertingProgress(
                        progress.done,
                        progress.total,
                      ),
                      style: muted,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: busy ? null : () => unawaited(_convertAll()),
          child: Text(
            widget.files.length > 1
                ? l10n.negativeConvertAllButton(widget.files.length)
                : l10n.negativeConvertButton,
          ),
        ),
      ],
    );
  }
}
