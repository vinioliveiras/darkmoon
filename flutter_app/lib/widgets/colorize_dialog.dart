import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../native/onnx_gpu_probe.dart' show probeColorizeGpuSupport;
import '../theme.dart';
import 'dialog_chrome.dart';

/// Default value for [ColorizeChoice.intensityPercent] — 100%, the
/// model's raw prediction. Unlike the "new toggle, balanced 50% default"
/// convention (see `ai_denoise_dialog.dart`'s
/// `defaultRestoreDetailAmount` doc), this mirrors the Denoise Amount
/// default instead: the point of opening this dialog at all is wanting
/// color, so start at full strength and let the user dial back only if
/// the result looks oversaturated (a real, documented tendency — see
/// `onnx_runtime.dart`'s `ddcolorModelSpec` doc), same reasoning
/// `defaultNeuralDenoiseAmount` already used.
const defaultColorizeIntensity = 100;

/// What [ColorizeDialog] resolves with. `active` false means "turn
/// colorize back off" (re-picked the toggle after it was already on) —
/// checked the same way `NeuralEnhanceChoice.active` is.
class ColorizeChoice {
  const ColorizeChoice({
    required this.active,
    this.intensityPercent = defaultColorizeIntensity,
  });

  final bool active;
  final int intensityPercent;
}

/// Colorize (item 37, DDColor) confirm dialog — deliberately not folded
/// into `AiDenoiseDialog` as a 4th tab: colorize replaces the photo's base
/// image the same way Enhance does, but it's a conceptually different
/// operation (recoloring, not noise/detail restoration) and the user
/// asked for it as its own dedicated toolbar button (2026-09-01). Much
/// simpler than `AiDenoiseDialog` since there's only one real choice
/// (how much color, not which of several independent passes to combine).
class ColorizeDialog extends StatefulWidget {
  const ColorizeDialog({
    super.key,
    required this.active,
    this.intensityPercent = defaultColorizeIntensity,
  });

  /// Whether colorize is already applied to the current photo — same
  /// preselection reasoning as `AiDenoiseDialog.neuralDenoise`.
  final bool active;
  final int intensityPercent;

  @override
  State<ColorizeDialog> createState() => _ColorizeDialogState();
}

class _ColorizeDialogState extends State<ColorizeDialog> {
  late int _intensity = widget.intensityPercent;

  /// null while the probe hasn't resolved yet — same convention as
  /// `AiDenoiseDialog`'s own `_gpuAvailable`. Probed here in `initState`,
  /// not by the caller before `showDialog` (2026-09-01, fixed a real bug
  /// — see `probeColorizeGpuSupport`'s own doc for why awaiting a probe
  /// *before* opening the dialog is the wrong shape): the dialog opens
  /// immediately and this warning fills in once the probe resolves,
  /// exactly like `AiDenoiseDialog._gpuAvailable` already does.
  bool? _gpuAvailable;

  @override
  void initState() {
    super.initState();
    unawaited(_probeGpu());
  }

  Future<void> _probeGpu() async {
    final available = await probeColorizeGpuSupport();
    if (mounted) {
      setState(() => _gpuAvailable = available);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: DarkmoonColors.dialogBackground,
      shape: dialogShape,
      title: DialogTitleRow(
        title: l10n.colorizeDialogTitle,
        closeTooltip: l10n.closeButton,
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.colorizeDialogMessage,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_gpuAvailable == false) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8A33D).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFE8A33D).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      CupertinoIcons.exclamationmark_triangle_fill,
                      size: 14,
                      color: Color(0xFFE8A33D),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.aiDenoiseEnhanceGpuIncompatibleWarning,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: DarkmoonColors.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.colorizeIntensityLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DarkmoonColors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  '$_intensity%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: DarkmoonColors.textMuted,
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
                max: 100,
                divisions: 100,
                value: _intensity.toDouble(),
                onChanged: (v) => setState(() => _intensity = v.round()),
              ),
            ),
            if (widget.active) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(const ColorizeChoice(active: false)),
                child: Text(l10n.colorizeRemoveButton),
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
          ).pop(ColorizeChoice(active: true, intensityPercent: _intensity)),
          child: Text(l10n.aiDenoiseApplyButton),
        ),
      ],
    );
  }
}
