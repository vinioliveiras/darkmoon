// The panel shown while objects are being removed.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// imports of its own — the split is for navigation, not decoupling.
part of '../editor_screen.dart';

/// Takes the whole controls panel while removal mode is on, the way the
/// crop panel does: the brush's size and hardness, the strokes' undo and
/// clear, the Remove button that runs the model over what was painted,
/// and a way back out. The strokes themselves are painted on the canvas.
class _RemoveObjectsPanel extends StatelessWidget {
  const _RemoveObjectsPanel({
    required this.brushRadius,
    required this.brushHardness,
    required this.brushErase,
    required this.hasStrokes,
    required this.removalCount,
    required this.busy,
    required this.actions,
  });

  final double brushRadius;
  final double brushHardness;
  final bool brushErase;

  /// Whether anything is painted and waiting to be removed.
  final bool hasStrokes;

  /// How many removals the photo already carries.
  final int removalCount;

  /// The model is running; the buttons wait for it.
  final bool busy;

  final _ControlsPanelActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(l10n.removePanelTitle, style: theme.textTheme.labelSmall),
        ),
        Text(
          l10n.removePanelHint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: DarkmoonColors.textMuted,
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SliderRow(
            name: l10n.maskBrushSizeLabel,
            min: 0.01,
            max: 0.4,
            value: brushRadius,
            decimals: 2,
            onChanged: actions.onBrushRadiusChanged,
            onChangeEnd: actions.onBrushRadiusChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SliderRow(
            name: l10n.maskBrushHardnessLabel,
            min: 0,
            max: 1,
            value: brushHardness,
            decimals: 2,
            onChanged: actions.onBrushHardnessChanged,
            onChangeEnd: actions.onBrushHardnessChanged,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.maskBrushEraseLabel,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            SizedBox(
              width: 34,
              height: 21,
              child: FittedBox(
                child: Switch(
                  value: brushErase,
                  onChanged: (_) => actions.onToggleBrushErase(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 32,
              width: 32,
              child: IconButton(
                tooltip: l10n.maskUndoStrokeTooltip,
                onPressed: hasStrokes && !busy
                    ? actions.onUndoRemoveStroke
                    : null,
                icon: const Icon(CupertinoIcons.arrow_uturn_left, size: 15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: hasStrokes && !busy ? actions.onRunRemoval : null,
          child: Text(l10n.removeRunButton),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton(
              onPressed: hasStrokes && !busy
                  ? actions.onClearRemoveStrokes
                  : null,
              child: Text(l10n.removeClearStrokes),
            ),
            const Spacer(),
            TextButton(
              onPressed: removalCount > 0 && !busy
                  ? actions.onUndoRemoval
                  : null,
              child: Text(l10n.removeUndoRemoval),
            ),
          ],
        ),
        if (removalCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.removeCountLabel(removalCount),
              style: theme.textTheme.labelSmall?.copyWith(
                color: DarkmoonColors.textMuted,
              ),
            ),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy ? null : actions.onToggleRemoveMode,
            child: Text(l10n.removeDoneButton),
          ),
        ),
      ],
    );
  }
}
