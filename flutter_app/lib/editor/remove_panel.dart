// The panel shown while objects are being removed.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// imports of its own — the split is for navigation, not decoupling.
part of '../editor_screen.dart';

/// Takes the whole controls panel while removal mode is on, the way the
/// crop panel does. After Solstice's inpainting panel: paint with the
/// brush and press Remove, or take an existing mask (Subject, Sky, a
/// gradient, a colour range) as the removal; Expand grows the coverage
/// past a segmentation's exact edge; and every removal made is a patch
/// in a list, to hide or delete on its own.
class _RemoveObjectsPanel extends StatelessWidget {
  const _RemoveObjectsPanel({
    required this.brushRadius,
    required this.brushHardness,
    required this.brushErase,
    required this.grow,
    required this.hasStrokes,
    required this.masks,
    required this.removals,
    required this.busy,
    required this.actions,
  });

  final double brushRadius;
  final double brushHardness;
  final bool brushErase;

  /// How far the coverage is grown, in percent of the photo's width.
  final double grow;

  /// Whether anything is painted and waiting to be removed.
  final bool hasStrokes;

  /// The photo's masks, offered as removals.
  final List<MaskLayer> masks;

  /// The removals the photo carries, oldest first.
  final List<Removal> removals;

  /// The model is running; the buttons wait for it.
  final bool busy;

  final _ControlsPanelActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: DarkmoonColors.textMuted,
    );
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
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SliderRow(
            name: l10n.removeGrowLabel,
            min: 0,
            max: 5,
            value: grow,
            decimals: 1,
            valueSuffix: '%',
            defaultValue: 0.5,
            onChanged: actions.onRemoveGrowChanged,
            onChangeEnd: actions.onRemoveGrowChanged,
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
        const SizedBox(height: 14),
        // The crop panel's pair: an outlined secondary and a filled
        // primary, side by side, 34 tall.
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: OutlinedButton(
                  onPressed: hasStrokes && !busy
                      ? actions.onClearRemoveStrokes
                      : null,
                  child: Text(l10n.removeClearStrokes),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: hasStrokes && !busy ? actions.onRunRemoval : null,
                  child: Text(l10n.removeRunButton),
                ),
              ),
            ),
          ],
        ),
        if (masks.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(l10n.removeWithMaskLabel, style: muted),
          const SizedBox(height: 6),
          // Choosing a mask runs the removal at once, the way the add-mask
          // menu adds at once — there is nothing else to set first.
          StyledDropdown<String>(
            value: null,
            placeholder: l10n.removeWithMaskPlaceholder,
            items: [
              for (final mask in masks)
                StyledDropdownItem(value: mask.id, label: mask.name),
            ],
            onChanged: busy ? (_) {} : actions.onRemoveWithMask,
          ),
        ],
        if (removals.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(l10n.removeListTitle, style: muted),
          const SizedBox(height: 4),
          for (var i = 0; i < removals.length; i++)
            Row(
              children: [
                SizedBox(
                  height: 30,
                  width: 30,
                  child: IconButton(
                    tooltip: removals[i].visible
                        ? l10n.removeVisibleTooltip
                        : l10n.removeHiddenTooltip,
                    onPressed: busy
                        ? null
                        : () => actions.onToggleRemovalVisible(i),
                    icon: Icon(
                      removals[i].visible
                          ? CupertinoIcons.eye
                          : CupertinoIcons.eye_slash,
                      size: 14,
                      color: removals[i].visible
                          ? DarkmoonColors.textPrimary
                          : DarkmoonColors.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    removals[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: removals[i].visible
                          ? DarkmoonColors.textPrimary
                          : DarkmoonColors.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  height: 30,
                  width: 30,
                  child: IconButton(
                    tooltip: l10n.removeDeleteTooltip,
                    onPressed: busy ? null : () => actions.onDeleteRemoval(i),
                    icon: const Icon(CupertinoIcons.trash, size: 14),
                  ),
                ),
              ],
            ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 34,
          child: OutlinedButton(
            onPressed: busy ? null : actions.onToggleRemoveMode,
            child: Text(l10n.removeDoneButton),
          ),
        ),
      ],
    );
  }
}
