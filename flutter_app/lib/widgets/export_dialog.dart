import 'package:flutter/material.dart';

import '../export/export_format.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'dialog_chrome.dart';

class ExportOptions {
  const ExportOptions({
    required this.format,
    required this.quality,
    this.scalePercent,
  });

  final ExportFormat format;
  final int quality;

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
          ],
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
                  )
                : ExportOptions(format: _format, quality: _quality),
          ),
          child: Text(l10n.exportDialogConfirm),
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
