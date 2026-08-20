import 'package:flutter/material.dart';

import '../export/export_format.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';

class ExportOptions {
  const ExportOptions({required this.format, required this.quality});

  final ExportFormat format;
  final int quality;
}

/// Format + JPEG quality picker shown before the save-file dialog, mirroring
/// the Python app's `ExportOptionsDialog` but styled like the rest of this
/// app's panels (segmented format picker, section labels) instead of
/// default Material dialog chrome. Resolves with `null` if cancelled.
class ExportOptionsDialog extends StatefulWidget {
  const ExportOptionsDialog({super.key});

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: DarkmoonColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: DarkmoonColors.border),
      ),
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
                data: SliderTheme.of(
                  context,
                ).copyWith(trackShape: const RectangularSliderTrackShape()),
                child: Slider(
                  min: 1,
                  max: 100,
                  divisions: 99,
                  value: _quality.toDouble(),
                  onChanged: (v) => setState(() => _quality = v.round()),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(ExportOptions(format: _format, quality: _quality)),
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
