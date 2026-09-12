import 'package:flutter/material.dart';

import '../export/export_format.dart';
import '../export/frame.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'dialog_chrome.dart';

class ExportOptions {
  const ExportOptions({
    required this.format,
    required this.quality,
    this.scalePercent,
    this.frame,
  });

  final ExportFormat format;
  final int quality;

  /// The Frame section, when it is switched on — see `frame.dart`.
  final FrameOptions? frame;

  /// Set when "Rapid export" is on — passed straight through to
  /// `export_job.dart`'s `ExportRequest.scalePercent`.
  final int? scalePercent;
}

/// JPEG quality "Rapid export" forces — well below the 90 default, since
/// the point of that toggle is a small, fast file for sharing rather than
/// an archival-quality one.
const int rapidExportQuality = 80;

/// Default percent-of-original resolution "Rapid export"'s slider opens
/// at — barely a trim (a real photo's own edge/pixel-level detail is
/// already well past what any screen or print needs at 95% of native), so
/// the default itself is close to a no-op; the slider is there for
/// whoever wants to trade more of it away for a smaller/faster file.
const int defaultRapidExportScalePercent = 95;

/// Format + JPEG quality picker shown before the save-file dialog, mirroring
/// the Python app's `ExportOptionsDialog` but styled like the rest of this
/// app's panels (segmented format picker, section labels) instead of
/// default Material dialog chrome. Resolves with `null` if cancelled.
class ExportOptionsDialog extends StatefulWidget {
  const ExportOptionsDialog({super.key, this.nativeWidth, this.nativeHeight});

  /// The photo's actual output pixel dimensions (already flip/rotation-
  /// adjusted — see `RawMetadata.width`/`height`), used to show what the
  /// "Rapid export" resolution slider's percentage works out to in real
  /// pixels. Null (metadata not loaded yet, or a non-RAW source this app
  /// doesn't read dimensions from) just hides that preview rather than
  /// blocking the dialog on it.
  final int? nativeWidth;
  final int? nativeHeight;

  @override
  State<ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<ExportOptionsDialog> {
  ExportFormat _format = ExportFormat.jpeg;
  // 100 looks identical to ~90 in a JPEG encoder (quality above ~92 mostly
  // just disables chroma subsampling and wastes bytes on differences no one
  // can see) while multiplying file size several times over — a 70MB JPEG
  // out of an 8MP photo, reported against this default, is exactly that
  // waste. 90 matches the quality this app's own on-screen preview JPEGs
  // already render at (render_job.dart), a "good, normal-sized file"
  // default the user can still raise for a specific need.
  int _quality = 90;

  /// Rapid export forces JPEG at [rapidExportQuality] regardless of
  /// [_format]/[_quality] above (still shown, just disabled, rather than
  /// hidden — so switching it off leaves the format/quality exactly as the
  /// user last set them instead of resetting). On by default — the common
  /// case is a shareable file, not an archival master.
  bool _rapid = true;

  int _rapidScalePercent = defaultRapidExportScalePercent;
  bool _frameOn = false;
  FrameOptions _frame = const FrameOptions();

  /// The background swatches offered for a frame: paper white, black,
  /// and two greys. ARGB.
  static const _frameBackgrounds = [
    0xFFFFFFFF,
    0xFF000000,
    0xFF2A2A2A,
    0xFFE6E2DA,
  ];

  ({int width, int height})? _framedSize() {
    final w = widget.nativeWidth, h = widget.nativeHeight;
    if (w == null || h == null) return null;
    final scale = _rapid ? _rapidScalePercent / 100 : 1.0;
    final size = frameSizeFor((w * scale).round(), (h * scale).round(), _frame);
    return (width: size.width, height: size.height);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: DarkmoonColors.dialogBackground,
      shape: dialogShape,
      title: Text(
        l10n.exportPhotoDialogTitle,
        style: const TextStyle(color: DarkmoonColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.exportRapidLabel),
                subtitle: Text(l10n.exportRapidHint),
                value: _rapid,
                onChanged: (v) => setState(() => _rapid = v),
              ),
              if (_rapid) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.exportRapidScaleLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '$_rapidScalePercent%',
                      style: const TextStyle(
                        color: DarkmoonColors.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(
                    context,
                  ).copyWith(trackShape: const RectangularSliderTrackShape()),
                  child: Slider(
                    min: 10,
                    max: 100,
                    divisions: 90,
                    value: _rapidScalePercent.toDouble(),
                    onChanged: (v) =>
                        setState(() => _rapidScalePercent = v.round()),
                  ),
                ),
                if (widget.nativeWidth != null && widget.nativeHeight != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                      child: Text(
                        l10n.exportRapidScaleResultLabel(
                          (widget.nativeWidth! * _rapidScalePercent / 100)
                              .round(),
                          (widget.nativeHeight! * _rapidScalePercent / 100)
                              .round(),
                        ),
                        style: const TextStyle(
                          color: DarkmoonColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 4),
              const Divider(),
              const SizedBox(height: 12),
              Opacity(
                opacity: _rapid ? 0.4 : 1.0,
                child: IgnorePointer(
                  ignoring: _rapid,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.exportFormatLabel,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final format in ExportFormat.values) ...[
                            if (format != ExportFormat.values.first)
                              const SizedBox(width: 8),
                            Expanded(
                              child: _FormatChip(
                                label: format.label,
                                selected: _format == format,
                                onTap: () => setState(() => _format = format),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_format.supportsQuality) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.exportQualityLabel,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              '$_quality%',
                              style: const TextStyle(
                                color: DarkmoonColors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackShape: const RectangularSliderTrackShape(),
                          ),
                          child: Slider(
                            min: 1,
                            max: 100,
                            divisions: 99,
                            value: _quality.toDouble(),
                            onChanged: (v) =>
                                setState(() => _quality = v.round()),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Divider(),
              // Frame Image — Solstice's one-picture collage: a border, a
              // corner radius, a background and an outer aspect, composed
              // into the file at export.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.exportFrameLabel),
                subtitle: Text(l10n.exportFrameHint),
                value: _frameOn,
                onChanged: (v) => setState(() => _frameOn = v),
              ),
              if (_frameOn) ...[
                _FrameSlider(
                  label: l10n.exportFramePaddingLabel,
                  value: _frame.paddingPercent,
                  max: 50,
                  onChanged: (v) => setState(
                    () => _frame = _frame.copyWith(paddingPercent: v),
                  ),
                ),
                _FrameSlider(
                  label: l10n.exportFrameRadiusLabel,
                  value: _frame.radiusPercent,
                  max: 50,
                  onChanged: (v) => setState(
                    () => _frame = _frame.copyWith(radiusPercent: v),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.exportFrameAspectLabel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final aspect in FrameAspect.values)
                      _FormatChip(
                        label: switch (aspect) {
                          FrameAspect.original =>
                            l10n.exportFrameAspectOriginal,
                          FrameAspect.square => '1:1',
                          FrameAspect.portrait4x5 => '4:5',
                          FrameAspect.landscape3x2 => '3:2',
                          FrameAspect.widescreen16x9 => '16:9',
                        },
                        selected: _frame.aspect == aspect,
                        onTap: () => setState(
                          () => _frame = _frame.copyWith(aspect: aspect),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.exportFrameBackgroundLabel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final argb in _frameBackgrounds) ...[
                      GestureDetector(
                        onTap: () => setState(
                          () => _frame = _frame.copyWith(background: argb),
                        ),
                        child: Container(
                          key: Key('frame-bg-${argb.toRadixString(16)}'),
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
                  ],
                ),
                if (_framedSize() case final size?)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.exportRapidScaleResultLabel(
                          size.width,
                          size.height,
                        ),
                        style: const TextStyle(
                          color: DarkmoonColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _rapid
                ? ExportOptions(
                    format: ExportFormat.jpeg,
                    quality: rapidExportQuality,
                    scalePercent: _rapidScalePercent,
                    frame: _frameOn ? _frame : null,
                  )
                : ExportOptions(
                    format: _format,
                    quality: _quality,
                    frame: _frameOn ? _frame : null,
                  ),
          ),
          child: Text(l10n.exportDialogConfirm),
        ),
      ],
    );
  }
}

/// One labelled 0..[max] percent slider of the Frame section.
class _FrameSlider extends StatelessWidget {
  const _FrameSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(
              '$value%',
              style: const TextStyle(
                color: DarkmoonColors.textMuted,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(
            context,
          ).copyWith(trackShape: const RectangularSliderTrackShape()),
          child: Slider(
            min: 0,
            max: max.toDouble(),
            divisions: max,
            value: value.toDouble(),
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
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
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
