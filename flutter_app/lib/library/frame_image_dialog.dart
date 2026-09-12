// The Albums "Frame image" dialog (2026-09-13), Solstice's collage modal
// for one picture: a live preview of the first photo inside the frame,
// the ratio presets with an orientation switch, spacing and corner
// radius, a background colour (swatches or a hex value), the output's
// long edge and format, and Save for every photo the menu was opened
// on. The preview is framed in an isolate by `frame_preview.dart`; the
// real file goes through the export pipeline with the photo's edits.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../export/export_format.dart';
import '../export/frame.dart';
import '../l10n/app_localizations.dart';
import '../motion.dart';
import '../raw_files.dart';
import '../theme.dart';
import '../widgets/dialog_chrome.dart';
import '../widgets/slider_row.dart';
import '../widgets/styled_dropdown.dart';
import 'frame_preview.dart';

/// Everything the dialog decided for the save.
class FrameImageChoice {
  const FrameImageChoice({
    required this.frame,
    required this.format,
    required this.longEdge,
  });

  final FrameOptions frame;
  final ExportFormat format;

  /// The output's long edge in pixels; null for the photo's own size.
  final int? longEdge;
}

/// What the dialog resolves with: the files written, in the order of
/// [FrameImageDialog.files], and the ones that failed. Null when
/// cancelled.
class FrameImageResult {
  const FrameImageResult(this.written, this.failed);
  final List<String> written;
  final List<String> failed;
}

class FrameImageDialog extends StatefulWidget {
  const FrameImageDialog({
    super.key,
    required this.files,
    required this.previewJpegFor,
    required this.save,
  });

  /// The photos to frame; the first one is previewed.
  final List<RawFile> files;

  /// A JPEG of [files.first] at any size — the preview or thumbnail cache.
  final Future<Uint8List?> Function(RawFile file) previewJpegFor;

  /// Saves one framed file, returning its path (throws on failure).
  final Future<String> Function(RawFile file, FrameImageChoice choice) save;

  @override
  State<FrameImageDialog> createState() => _FrameImageDialogState();
}

class _FrameImageDialogState extends State<FrameImageDialog> {
  static const _previewMaxDim = 700;

  /// Solstice's collage defaults: 15% spacing, square corners, white.
  static const _defaultFrame = FrameOptions(paddingPercent: 15);

  /// Paper white, black, a dark grey and a warm off-white. ARGB.
  static const _swatches = [0xFFFFFFFF, 0xFF000000, 0xFF2A2A2A, 0xFFF4F1EA];

  /// The long-edge choices; 0 is the photo's own size.
  static const _longEdges = [0, 4096, 3000, 2048, 1080];

  FrameOptions _frame = _defaultFrame;
  ExportFormat _format = ExportFormat.jpeg;
  int _longEdge = 0;
  late final TextEditingController _hex = TextEditingController(
    text: _hexOf(_frame.background),
  );

  FramePreviewBase? _base;
  ui.Image? _preview;
  bool _previewMissing = false;
  Timer? _debounce;
  int _renderSerial = 0;

  /// null while idle; (done, total) while saving.
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
    _hex.dispose();
    super.dispose();
  }

  static String _hexOf(int argb) =>
      (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  Future<void> _loadBase() async {
    final jpeg = await widget.previewJpegFor(widget.files.first);
    if (!mounted) return;
    if (jpeg == null) {
      setState(() => _previewMissing = true);
      return;
    }
    final base = await compute(decodeFramePreviewBase, (
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
    final framed = await compute(renderFramePreviewRgba, (
      base: base,
      options: _frame,
    ));
    if (!mounted || serial != _renderSerial) return;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      framed.rgba,
      framed.width,
      framed.height,
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

  void _update(FrameOptions next) {
    setState(() => _frame = next);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 40), () {
      unawaited(_render());
    });
  }

  void _setBackground(int argb) {
    _hex.text = _hexOf(argb);
    _update(_frame.copyWith(background: argb));
  }

  void _hexChanged(String text) {
    final clean = text.replaceAll('#', '').trim();
    if (clean.length != 6) return;
    final value = int.tryParse(clean, radix: 16);
    if (value == null) return;
    _update(_frame.copyWith(background: 0xFF000000 | value));
  }

  Future<void> _saveAll() async {
    final files = widget.files;
    final choice = FrameImageChoice(
      frame: _frame,
      format: _format,
      longEdge: _longEdge == 0 ? null : _longEdge,
    );
    setState(() => _progress = (done: 0, total: files.length));
    final written = <String>[];
    final failed = <String>[];
    for (var i = 0; i < files.length; i++) {
      try {
        written.add(await widget.save(files[i], choice));
      } catch (_) {
        failed.add(files[i].path);
      }
      if (!mounted) return;
      setState(() => _progress = (done: i + 1, total: files.length));
    }
    if (!mounted) return;
    Navigator.of(context).pop(FrameImageResult(written, failed));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: DarkmoonColors.textMuted);
    final progress = _progress;
    final busy = progress != null;
    final orientable =
        _frame.aspect != FrameAspect.original &&
        _frame.aspect != FrameAspect.square;
    return AlertDialog(
      backgroundColor: DarkmoonColors.dialogBackground,
      shape: dialogShape,
      title: Text(
        l10n.frameDialogTitle,
        style: const TextStyle(color: DarkmoonColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview.
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: DarkmoonColors.canvas,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(12),
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
                            ? Text(l10n.framePreviewUnavailable, style: muted)
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
                    Text(l10n.framePreviewHint, style: muted),
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
                    Text(l10n.frameAspectLabel, style: muted),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final aspect in FrameAspect.values)
                          _Chip(
                            label: aspect == FrameAspect.original
                                ? l10n.frameAspectOriginal
                                : aspect.label,
                            selected: _frame.aspect == aspect,
                            onTap: busy
                                ? null
                                : () =>
                                      _update(_frame.copyWith(aspect: aspect)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _Chip(
                            label: l10n.frameOrientationLandscape,
                            selected: orientable && !_frame.portrait,
                            onTap: busy || !orientable
                                ? null
                                : () =>
                                      _update(_frame.copyWith(portrait: false)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _Chip(
                            label: l10n.frameOrientationPortrait,
                            selected: orientable && _frame.portrait,
                            onTap: busy || !orientable
                                ? null
                                : () =>
                                      _update(_frame.copyWith(portrait: true)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SliderRow(
                      name: l10n.frameSpacingLabel,
                      min: 0,
                      max: 50,
                      value: _frame.paddingPercent.toDouble(),
                      decimals: 0,
                      valueSuffix: '%',
                      defaultValue: _defaultFrame.paddingPercent.toDouble(),
                      onChanged: (v) =>
                          _update(_frame.copyWith(paddingPercent: v.round())),
                    ),
                    SliderRow(
                      name: l10n.frameRadiusLabel,
                      min: 0,
                      max: 50,
                      value: _frame.radiusPercent.toDouble(),
                      decimals: 0,
                      valueSuffix: '%',
                      defaultValue: 0,
                      onChanged: (v) =>
                          _update(_frame.copyWith(radiusPercent: v.round())),
                    ),
                    const SizedBox(height: 10),
                    Text(l10n.frameBackgroundLabel, style: muted),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final argb in _swatches) ...[
                          GestureDetector(
                            onTap: busy ? null : () => _setBackground(argb),
                            child: Container(
                              key: Key('frame-bg-${_hexOf(argb)}'),
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: Color(argb),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _frame.background == argb
                                      ? DarkmoonColors.accent
                                      : DarkmoonColors.border,
                                  width: _frame.background == argb ? 2 : 1,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: TextField(
                            key: const Key('frame-hex'),
                            controller: _hex,
                            enabled: !busy,
                            maxLength: 7,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              isDense: true,
                              counterText: '',
                              prefixText: '#',
                              hintText: l10n.frameBackgroundHexHint,
                            ),
                            onChanged: _hexChanged,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(l10n.frameSizeLabel, style: muted),
                    const SizedBox(height: 6),
                    StyledDropdown<int>(
                      value: _longEdge,
                      items: [
                        for (final edge in _longEdges)
                          StyledDropdownItem(
                            value: edge,
                            label: edge == 0
                                ? l10n.frameSizeOriginal
                                : l10n.frameSizePixels(edge),
                          ),
                      ],
                      onChanged: busy
                          ? (_) {}
                          : (edge) => setState(() => _longEdge = edge),
                    ),
                    const SizedBox(height: 12),
                    Text(l10n.frameFormatLabel, style: muted),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final format in ExportFormat.values) ...[
                          if (format != ExportFormat.values.first)
                            const SizedBox(width: 6),
                          Expanded(
                            child: _Chip(
                              label: format.label,
                              selected: _format == format,
                              onTap: busy
                                  ? null
                                  : () => setState(() => _format = format),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: progress.total == 0
                            ? null
                            : progress.done / progress.total,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.frameSavingProgress(progress.done, progress.total),
                        style: muted,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: busy ? null : () => unawaited(_saveAll()),
          child: Text(
            widget.files.length > 1
                ? l10n.frameSaveAllButton(widget.files.length)
                : l10n.frameSaveButton,
          ),
        ),
      ],
    );
  }
}

/// One choice of a row: the ratio presets, the orientation, the format.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !selected ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? DarkmoonColors.accent : DarkmoonColors.canvas,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? DarkmoonColors.accent : DarkmoonColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? DarkmoonColors.background
                  : DarkmoonColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
