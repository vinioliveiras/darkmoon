import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../render/ai_denoise.dart';
import '../theme.dart';

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
  const NeuralEnhanceChoice({required this.denoise, required this.upscale});

  final bool denoise;
  final bool upscale;

  bool get active => denoise || upscale;
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

  @override
  State<AiDenoiseDialog> createState() => _AiDenoiseDialogState();
}

class _AiDenoiseDialogState extends State<AiDenoiseDialog>
    with SingleTickerProviderStateMixin {
  late AiDenoiseLevel? _level = widget.initialLevel;
  late bool _neuralDenoise = widget.neuralDenoise;
  late bool _neuralUpscale = widget.neuralUpscale;
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
    initialIndex: (widget.neuralDenoise || widget.neuralUpscale) ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    // Drives the IndexedStack below off the controller's current tab —
    // there's no TabBarView/PageView here (see the `content` comment), so
    // nothing else rebuilds this widget when a tab is tapped.
    _tabController.addListener(() => setState(() {}));
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
    });
  }

  void _setNeuralDenoise(bool value) {
    setState(() {
      _neuralDenoise = value;
      if (value) {
        _level = null;
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

  AiDenoiseChoice get _currentChoice => (_neuralDenoise || _neuralUpscale)
      ? NeuralEnhanceChoice(denoise: _neuralDenoise, upscale: _neuralUpscale)
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
        width: 320,
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
                      !_neuralDenoise && !_neuralUpscale && _level == choice,
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
        _ToggleRow(
          label: l10n.aiDenoiseEnhanceUpscaleLabel,
          value: _neuralUpscale,
          onChanged: _setNeuralUpscale,
        ),
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
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // The whole row toggles on tap (not just the Switch itself), same
    // "tap anywhere in the row" convention SwitchListTile gives elsewhere
    // in this app (e.g. settings_dialog.dart) — GestureDetector here
    // instead, since SwitchListTile's own minimum height overflowed this
    // dialog by a few pixels (see _buildEnhanceTab's comment).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: DarkmoonColors.textPrimary,
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
