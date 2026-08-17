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

/// Every choice offered by [AiDenoiseDialog] — `null` means "Off" (turn a
/// previously-applied level back off), listed first so switching it off is
/// never more than one tap away.
const _choices = <AiDenoiseLevel?>[
  null,
  AiDenoiseLevel.light,
  AiDenoiseLevel.medium,
  AiDenoiseLevel.strong,
];

/// One-shot AI Denoise level picker, opened from the toolbar's AI Denoise
/// button. Deliberately has a single choice (strength, plus Off) rather
/// than the classic denoiser's six sliders — each level is already tuned
/// to a good noise/detail trade-off, so there's nothing else for the user
/// to set. Resolves with an [AiDenoiseChoice] (its `level` null for Off),
/// or with a plain `null` if the dialog was dismissed without a choice.
class AiDenoiseDialog extends StatefulWidget {
  const AiDenoiseDialog({super.key, required this.initialLevel});

  /// The level already applied to the current photo, if any — preselected
  /// so reopening the dialog shows what's active rather than resetting to
  /// a default.
  final AiDenoiseLevel? initialLevel;

  @override
  State<AiDenoiseDialog> createState() => _AiDenoiseDialogState();
}

/// Distinguishes "the user picked Off" (null level, still a real choice)
/// from "the dialog was cancelled" (no choice at all) — both would
/// otherwise collapse to the same `null` return value.
class AiDenoiseChoice {
  const AiDenoiseChoice(this.level);

  final AiDenoiseLevel? level;
}

class _AiDenoiseDialogState extends State<AiDenoiseDialog> {
  late AiDenoiseLevel? _level = widget.initialLevel;

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
        width: 300,
        child: Column(
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
                for (final choice in _choices) ...[
                  if (choice != _choices.first) const SizedBox(width: 8),
                  Expanded(
                    child: _LevelChip(
                      label: _levelLabel(l10n, choice),
                      selected: _level == choice,
                      onTap: () => setState(() => _level = choice),
                    ),
                  ),
                ],
              ],
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
          onPressed: () => Navigator.of(context).pop(AiDenoiseChoice(_level)),
          child: Text(l10n.aiDenoiseApplyButton),
        ),
      ],
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
