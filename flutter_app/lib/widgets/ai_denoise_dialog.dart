import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../native/onnx_gpu_probe.dart';
import '../render/ai_denoise.dart';
import '../theme.dart';

/// Sparingly used, not part of the app's usual monochrome palette — a
/// genuine caution color reads faster than another gray box for the one
/// thing in this dialog that's actually worth interrupting for (a GPU
/// that won't be used, when the whole point of the model choice was
/// speed).
const _warningColor = Color(0xFFE8A33D);

String _levelLabel(AppLocalizations l10n, AiDenoiseLevel? level) =>
    switch (level) {
      null => l10n.aiDenoiseLevelOff,
      AiDenoiseLevel.light => l10n.aiDenoiseLevelLight,
      AiDenoiseLevel.medium => l10n.aiDenoiseLevelMedium,
      AiDenoiseLevel.strong => l10n.aiDenoiseLevelStrong,
    };

/// Every choice offered by the Classic tab — `null` means "Off" (turn a
/// previously-applied level back off), listed first so switching it off is
/// never more than one tap away.
const _classicChoices = <AiDenoiseLevel?>[
  null,
  AiDenoiseLevel.light,
  AiDenoiseLevel.medium,
  AiDenoiseLevel.strong,
];

/// What [AiDenoiseDialog] resolves with — the two tabs are mutually
/// exclusive (a photo has either a classical level applied, or the neural
/// enhance pipeline applied, never both), so the result is one or the
/// other rather than a flat level like before item 13's neural pipeline
/// existed.
sealed class AiDenoiseChoice {
  const AiDenoiseChoice();
}

/// Off ([level] null) or one of the classical blur-based levels
/// (`lib/render/ai_denoise.dart`'s `applyAiDenoise` — a per-render
/// pipeline stage).
class ClassicDenoiseChoice extends AiDenoiseChoice {
  const ClassicDenoiseChoice(this.level);

  final AiDenoiseLevel? level;
}

/// The item-13 neural pipeline — a one-shot pre-process that replaces the
/// photo's edit source, not a per-render stage. [denoise] (NAFNet-SIDD)
/// and [upscale] (Real-ESRGAN 2x) are independent toggles rather than one
/// combined on/off switch, since either is a useful result on its own
/// (denoise a noisy JPEG without changing its resolution; upscale an
/// already-clean photo without paying for denoise it doesn't need).
/// [active] (both false) means "turn it back off" — checked by callers
/// instead of a stray null case.
class NeuralEnhanceChoice extends AiDenoiseChoice {
  const NeuralEnhanceChoice({
    required this.denoise,
    required this.upscale,
    this.denoiseAmount = 100,
    this.rawDenoise = false,
  });

  final bool denoise;
  final bool upscale;

  /// PMRID raw-domain denoise (`pmrid_denoise.dart`) — runs on the
  /// sensor's own Bayer data before demosaic, unlike [denoise]
  /// (NAFNet-SIDD, which runs after). Only ever true for a standard
  /// Bayer-CFA RAW file (see `libraw.dart`'s `RawMetadata.isBayerCfa`);
  /// mutually exclusive with [denoise] in the dialog UI (running both
  /// would just re-smooth pixels PMRID already cleaned) — enforced there,
  /// not here, so this class stays a plain data holder.
  final bool rawDenoise;

  /// 0-100 blend between the original and NAFNet-SIDD's full-strength
  /// output (see `ai_enhance.dart`'s `enhanceImage` doc — the model has
  /// no strength control of its own, so this is a linear blend applied
  /// afterward). Only meaningful when [denoise] is true; ignored
  /// otherwise, and left at its default rather than made nullable so
  /// callers don't need a null-check for a value that never actually
  /// matters when unused.
  final int denoiseAmount;

  bool get active => denoise || upscale || rawDenoise;
}

/// AI Denoise level/mode picker, opened from the toolbar's AI Denoise
/// button — two tabs: **Classic** (the original single-choice strength
/// picker: each level already tuned to a good noise/detail trade-off, so
/// there's nothing else to set) and **Enhance** (item 13's neural
/// pipeline, a fundamentally different kind of operation — it can change
/// the photo's resolution and has independent Denoise/Upscale toggles
/// instead of strength levels, hence its own tab rather than folded into
/// Classic's four chips). Resolves with an [AiDenoiseChoice], or with a
/// plain `null` if the dialog was dismissed without a choice.
class AiDenoiseDialog extends StatefulWidget {
  const AiDenoiseDialog({
    super.key,
    required this.initialLevel,
    required this.neuralDenoise,
    required this.neuralUpscale,
    this.neuralDenoiseAmount = 100,
    this.neuralRawDenoise = false,
    this.rawDenoiseAvailable = false,
  });

  /// The classical level already applied to the current photo, if any —
  /// preselected so reopening the dialog shows what's active rather than
  /// resetting to a default.
  final AiDenoiseLevel? initialLevel;

  /// Whether the neural pipeline's denoise/upscale passes are already
  /// applied to the current photo — same preselection reasoning as
  /// [initialLevel].
  final bool neuralDenoise;
  final bool neuralUpscale;

  /// See [NeuralEnhanceChoice.denoiseAmount].
  final int neuralDenoiseAmount;

  /// See [NeuralEnhanceChoice.rawDenoise].
  final bool neuralRawDenoise;

  /// Whether the current photo is a standard Bayer-CFA RAW file — the raw
  /// denoise toggle is shown disabled (with an explanatory caption) when
  /// this is false, since PMRID can't process X-Trans/Foveon sensors or a
  /// non-RAW format at all (see `libraw.dart`'s `RawMetadata.isBayerCfa`).
  final bool rawDenoiseAvailable;

  @override
  State<AiDenoiseDialog> createState() => _AiDenoiseDialogState();
}

class _AiDenoiseDialogState extends State<AiDenoiseDialog>
    with SingleTickerProviderStateMixin {
  late AiDenoiseLevel? _level = widget.initialLevel;
  late bool _neuralDenoise = widget.neuralDenoise;
  late bool _neuralUpscale = widget.neuralUpscale;
  late bool _neuralRawDenoise = widget.neuralRawDenoise;
  late int _denoiseAmount = widget.neuralDenoiseAmount;
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
    initialIndex:
        (widget.neuralDenoise || widget.neuralUpscale || widget.neuralRawDenoise)
        ? 1
        : 0,
  );

  /// null while the probe hasn't resolved yet — the Enhance tab shows
  /// nothing extra until then rather than guessing. `false` is exactly
  /// the case the warning below exists for.
  bool? _gpuAvailable;

  @override
  void initState() {
    super.initState();
    // Drives the IndexedStack below off the controller's current tab —
    // there's no TabBarView/PageView here (see the `content` comment), so
    // nothing else rebuilds this widget when a tab is tapped.
    _tabController.addListener(() => setState(() {}));
    unawaited(_probeGpu());
  }

  /// Cached after the first probe (see `probeAiEnhanceGpuSupport`'s own
  /// doc) — creating a real ONNX session costs ~1-2s either way, so this
  /// dialog only pays that once per app run, not once per open.
  Future<void> _probeGpu() async {
    final available = await probeAiEnhanceGpuSupport();
    if (mounted) {
      setState(() => _gpuAvailable = available);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// The two tabs are mutually exclusive — picking a Classic level turns
  /// both Enhance toggles back off, and turning either Enhance toggle on
  /// resets the Classic level to Off, so whichever tab the user isn't
  /// looking at always agrees with what's about to actually be applied
  /// (and the classic per-render denoise never stacks with the neural
  /// pipeline on the same photo).
  void _pickClassic(AiDenoiseLevel? level) {
    setState(() {
      _level = level;
      _neuralDenoise = false;
      _neuralUpscale = false;
      _neuralRawDenoise = false;
    });
  }

  void _setNeuralDenoise(bool value) {
    setState(() {
      _neuralDenoise = value;
      if (value) {
        _level = null;
        // Mutually exclusive with raw denoise — running both would just
        // re-smooth pixels PMRID already cleaned.
        _neuralRawDenoise = false;
      }
    });
  }

  void _setNeuralUpscale(bool value) {
    setState(() {
      _neuralUpscale = value;
      if (value) {
        _level = null;
      }
    });
  }

  void _setNeuralRawDenoise(bool value) {
    setState(() {
      _neuralRawDenoise = value;
      if (value) {
        _level = null;
        _neuralDenoise = false;
      }
    });
  }

  AiDenoiseChoice get _currentChoice =>
      (_neuralDenoise || _neuralUpscale || _neuralRawDenoise)
      ? NeuralEnhanceChoice(
          denoise: _neuralDenoise,
          upscale: _neuralUpscale,
          denoiseAmount: _denoiseAmount,
          rawDenoise: _neuralRawDenoise,
        )
      : ClassicDenoiseChoice(_level);

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
        l10n.aiDenoiseDialogTitle,
        style: const TextStyle(color: DarkmoonColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 360,
        // No fixed height: Classic's and Enhance's messages are very
        // different lengths, and a hard-coded height either overflows the
        // shorter tab into a scroll it doesn't need or clips the taller one.
        // An IndexedStack (not TabBarView — that needs a bounded height
        // for its PageView, which is exactly what we're avoiding) sizes
        // itself to its biggest child, so the dialog naturally grows to fit
        // whichever tab is tallest and both tabs render at that same size.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              controller: _tabController,
              labelColor: DarkmoonColors.textPrimary,
              unselectedLabelColor: DarkmoonColors.textMuted,
              indicatorColor: DarkmoonColors.accent,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: DarkmoonColors.divider,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              labelStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 12.5),
              tabs: [
                Tab(text: l10n.aiDenoiseTabClassic),
                Tab(text: l10n.aiDenoiseTabEnhance),
              ],
            ),
            const SizedBox(height: 14),
            IndexedStack(
              index: _tabController.index,
              alignment: Alignment.topLeft,
              children: [_buildClassicTab(l10n), _buildEnhanceTab(l10n)],
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
          onPressed: () => Navigator.of(context).pop(_currentChoice),
          child: Text(l10n.aiDenoiseApplyButton),
        ),
      ],
    );
  }

  Widget _buildClassicTab(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aiDenoiseDialogMessage,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final choice in _classicChoices) ...[
              if (choice != _classicChoices.first) const SizedBox(width: 8),
              Expanded(
                child: _LevelChip(
                  label: _levelLabel(l10n, choice),
                  selected:
                      !_neuralDenoise &&
                      !_neuralUpscale &&
                      !_neuralRawDenoise &&
                      _level == choice,
                  onTap: () => _pickClassic(choice),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildEnhanceTab(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aiDenoiseEnhanceMessage,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        // Told up front, before the user commits to running it — the
        // same fact `editor_screen.dart`'s CPU-fallback SnackBar reports,
        // just moved earlier so it can actually change the user's mind
        // instead of only explaining a slow wait after it's started.
        // Silent while `_gpuAvailable` is still null (mid-probe) or true
        // (nothing worth interrupting for).
        if (_gpuAvailable == false) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _warningColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _warningColor.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  size: 14,
                  color: _warningColor,
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
        // Independent toggles, not a single on/off switch — denoising a
        // noisy JPEG without upscaling it, or upscaling an already-clean
        // photo without paying for denoise it doesn't need, are both
        // useful on their own, not just as a combined "Enhance" pass.
        // Stacked (not side by side) so each has room for a longer label.
        // Plain Switch + Text rather than SwitchListTile — ListTile's own
        // minimum height pushed the dialog past its available space by a
        // few pixels (an overflow only a widget test surfaces; visually
        // negligible on a real screen, but still real).
        _ToggleRow(
          label: l10n.aiDenoiseEnhanceDenoiseLabel,
          value: _neuralDenoise,
          onChanged: _setNeuralDenoise,
        ),
        // Only shown once Denoise is on — an amount for a pass that isn't
        // even running has nothing to control. NAFNet-SIDD itself has no
        // strength input (see NeuralEnhanceChoice.denoiseAmount's doc);
        // this blends its full-strength output back toward the original.
        if (_neuralDenoise) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.aiDenoiseEnhanceAmountLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DarkmoonColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '$_denoiseAmount%',
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
              value: _denoiseAmount.toDouble(),
              onChanged: (v) => setState(() => _denoiseAmount = v.round()),
            ),
          ),
        ],
        const SizedBox(height: 4),
        _ToggleRow(
          label: l10n.aiDenoiseEnhanceUpscaleLabel,
          value: _neuralUpscale,
          onChanged: _setNeuralUpscale,
        ),
        const SizedBox(height: 4),
        // Runs on the sensor's own Bayer data before demosaic (see
        // NeuralEnhanceChoice.rawDenoise's doc) — only possible for a
        // standard Bayer RAW, so the toggle is shown disabled with an
        // explanatory caption rather than hidden outright when the current
        // photo can't use it (X-Trans, Foveon/monochrome, or a non-RAW
        // format), so the user learns why it's missing instead of just not
        // finding it.
        _ToggleRow(
          label: l10n.aiDenoiseEnhanceRawDenoiseLabel,
          value: _neuralRawDenoise,
          onChanged: widget.rawDenoiseAvailable ? _setNeuralRawDenoise : null,
        ),
        if (!widget.rawDenoiseAvailable) ...[
          const SizedBox(height: 2),
          Text(
            l10n.aiDenoiseEnhanceRawDenoiseUnavailableCaption,
            style: const TextStyle(
              fontSize: 11,
              color: DarkmoonColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;

  /// Null disables the row entirely (used for a toggle the current photo
  /// can't support at all, e.g. raw denoise on a non-Bayer file) — Switch
  /// already renders a muted, non-interactive look for `onChanged: null`,
  /// so this only needs to also stop the row's own tap-anywhere handler.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    // The whole row toggles on tap (not just the Switch itself), same
    // "tap anywhere in the row" convention SwitchListTile gives elsewhere
    // in this app (e.g. settings_dialog.dart) — GestureDetector here
    // instead, since SwitchListTile's own minimum height overflowed this
    // dialog by a few pixels (see _buildEnhanceTab's comment).
    final enabled = onChanged != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: enabled
                    ? DarkmoonColors.textPrimary
                    : DarkmoonColors.textMuted,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
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
          textAlign: TextAlign.center,
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
