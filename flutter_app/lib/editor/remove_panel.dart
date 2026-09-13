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
    required this.autoRepairSensitivity,
    required this.hasStrokes,
    required this.mode,
    required this.sourcePicking,
    required this.sourcePicked,
    required this.prompt,
    required this.generativeConfigured,
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

  /// Magical Repair's sensitivity, 0..100 (see spot_detect.dart).
  final double autoRepairSensitivity;

  /// Whether anything is painted and waiting to be removed.
  final bool hasStrokes;

  /// The fill for the next removal and its per-mode state — see
  /// `catalog/removal.dart`'s RemovalMode.
  final RemovalMode mode;
  final bool sourcePicking;
  final bool sourcePicked;
  final String prompt;
  final bool generativeConfigured;

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
        const SizedBox(height: 12),
        // How the hole is filled. AI is the model; Clone and Heal copy
        // from a point the user picks (Heal blends the copy into place);
        // Generative asks the server named in Settings for a prompt.
        Row(
          children: [
            for (final m in RemovalMode.values) ...[
              if (m != RemovalMode.values.first) const SizedBox(width: 4),
              Expanded(
                child: _RemoveModeChip(
                  label: switch (m) {
                    RemovalMode.ai => l10n.removeModeAi,
                    RemovalMode.clone => l10n.removeModeClone,
                    RemovalMode.heal => l10n.removeModeHeal,
                    RemovalMode.generative => l10n.removeModeGenerative,
                  },
                  selected: mode == m,
                  onTap: busy ? null : () => actions.onRemoveModeChanged(m),
                ),
              ),
            ],
          ],
        ),
        if (mode == RemovalMode.clone || mode == RemovalMode.heal) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                height: 30,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : actions.onToggleRemoveSourcePick,
                  style: sourcePicking
                      ? OutlinedButton.styleFrom(
                          foregroundColor: DarkmoonColors.accent,
                          side: const BorderSide(color: DarkmoonColors.accent),
                        )
                      : null,
                  icon: const Icon(CupertinoIcons.scope, size: 14),
                  label: Text(l10n.removePickSourceButton),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sourcePicking
                      ? l10n.removePickSourceHint
                      : sourcePicked
                      ? l10n.removeSourcePickedHint
                      : l10n.removeSourceDefaultHint,
                  style: muted,
                ),
              ),
            ],
          ),
        ],
        if (mode == RemovalMode.generative) ...[
          const SizedBox(height: 8),
          Text(l10n.removePromptLabel, style: muted),
          const SizedBox(height: 4),
          TextFormField(
            key: const Key('remove-prompt'),
            initialValue: prompt,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: l10n.removePromptHint,
              isDense: true,
            ),
            style: theme.textTheme.bodyMedium,
            onChanged: actions.onRemovePromptChanged,
          ),
          if (!generativeConfigured) ...[
            const SizedBox(height: 6),
            Text(
              l10n.removeGenerativeNotConfigured,
              style: muted?.copyWith(color: const Color(0xFFE8A33D)),
            ),
          ],
        ],
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
                  onPressed:
                      hasStrokes &&
                          !busy &&
                          (mode != RemovalMode.generative ||
                              generativeConfigured)
                      ? actions.onRunRemoval
                      : null,
                  child: Text(l10n.removeRunButton),
                ),
              ),
            ),
          ],
        ),
        // Magical Repair (2026-09-13): the detector's sensitivity and its
        // one button — every speck it finds becomes one AI-fill removal.
        const SizedBox(height: 14),
        Text(l10n.removeAutoRepairLabel, style: muted),
        const SizedBox(height: 4),
        Text(
          l10n.removeAutoRepairHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: DarkmoonColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        SliderRow(
          name: l10n.removeAutoRepairSensitivity,
          min: 0,
          max: 100,
          value: autoRepairSensitivity,
          decimals: 0,
          valueSuffix: '%',
          defaultValue: 50,
          onChanged: actions.onAutoRepairSensitivityChanged,
          onChangeEnd: actions.onAutoRepairSensitivityChanged,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: OutlinedButton(
            key: const Key('remove-auto-repair'),
            onPressed: busy ? null : actions.onAutoRepair,
            child: Text(l10n.removeAutoRepairButton),
          ),
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

/// One of the Remove panel's fill choices, styled like the export
/// dialog's format chips: a flat pill, filled with the accent when
/// chosen.
class _RemoveModeChip extends StatelessWidget {
  const _RemoveModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DarkmoonMotion.of(context, DarkmoonMotion.fast),
        curve: DarkmoonMotion.enter,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? DarkmoonColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? DarkmoonColors.accent : DarkmoonColors.border,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            color: selected
                ? DarkmoonColors.background
                : (onTap == null
                      ? DarkmoonColors.textMuted
                      : DarkmoonColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
