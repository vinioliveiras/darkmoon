// The Crop & Transform panel.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// imports of its own — the split (2026-09-10) is for navigation, not
// decoupling. Imports live in editor_screen.dart.
part of '../editor_screen.dart';

/// A clickable section header with a chevron — Meridian-style
/// collapse/expand toggle, shared by every panel section (sliders and
/// the Tone Curve alike).
/// Rotate/straighten/keystone sliders + crop aspect-ratio picker, shown
/// while the Crop Overlay is active — Meridian's Crop Overlay + Transform
/// panels combined, since they share one geometric pipeline stage (see
/// `crop_transform.dart`).
class _CropTransformPanel extends StatelessWidget {
  const _CropTransformPanel({
    required this.params,
    required this.onChanged,
    required this.onChangeEnd,
    required this.aspectRatio,
    required this.onAspectRatioChanged,
    required this.onDone,
    required this.onReset,
    required this.onStraighteningChanged,
    required this.guidedModeActive,
    required this.onToggleGuidedMode,
    required this.onLevel,
    required this.levelBusy,
    required this.onUpright,
    required this.uprightBusy,
  });

  /// Measures the photo and straightens it — the Level mode of PENDING
  /// item 27's Upright set.
  final VoidCallback onLevel;

  /// True while that measurement is running, so the button can say so
  /// instead of looking like it did nothing.
  final bool levelBusy;

  /// Measures the photo and both straightens and de-keystones it, as far
  /// as the chosen mode allows.
  final ValueChanged<UprightMode> onUpright;
  final bool uprightBusy;

  final CropTransformParams params;
  final ValueChanged<CropTransformParams> onChanged;
  final ValueChanged<CropTransformParams> onChangeEnd;
  final double? aspectRatio;
  final ValueChanged<double?> onAspectRatioChanged;

  /// Closes the Crop Overlay, keeping whatever's currently set.
  final VoidCallback onDone;

  /// Resets crop/rotate/keystone back to identity, without closing the
  /// overlay — matches Meridian's own Crop panel "Reset" behavior.
  final VoidCallback onReset;

  /// See [_ControlsPanel.onStraighteningChanged].
  final ValueChanged<bool> onStraighteningChanged;

  /// See [CropOverlay.guidedModeActive].
  final bool guidedModeActive;
  final VoidCallback onToggleGuidedMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DarkmoonColors.sectionCardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DarkmoonColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cropAspectLabel,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in cropAspectPresets)
                _AspectChip(
                  label: preset.label,
                  selected: aspectRatio == preset.ratio,
                  onTap: () => onAspectRatioChanged(preset.ratio),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _ToolbarPill(
            children: [
              _ToolbarSegment(
                icon: CupertinoIcons.rotate_left,
                tooltip: l10n.cropRotateLeftTooltip,
                onTap: () {
                  final next = params.copyWith(
                    rotateQuarterTurns: (params.rotateQuarterTurns - 1) % 4,
                  );
                  onChangeEnd(next);
                },
              ),
              _ToolbarSegment(
                icon: CupertinoIcons.rotate_right,
                tooltip: l10n.cropRotateRightTooltip,
                onTap: () {
                  final next = params.copyWith(
                    rotateQuarterTurns: (params.rotateQuarterTurns + 1) % 4,
                  );
                  onChangeEnd(next);
                },
              ),
              _ToolbarSegment(
                label: l10n.cropGuidedLabel,
                selected: guidedModeActive,
                tooltip: l10n.cropGuidedTooltip,
                onTap: onToggleGuidedMode,
              ),
              // Beside Guided, as asked: one works the correction out on
              // its own, the other is told.
              _ToolbarSegment(
                label: l10n.transformLevelButton,
                tooltip: l10n.transformLevelButton,
                onTap: levelBusy ? null : onLevel,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // The three perspective modes get their own row, ordered by how
          // much each will do: Auto corrects the verticals when it is sure
          // of them, Vertical does regardless, Full adds the horizontals
          // too. Three labels is what this panel's width comfortably takes
          // — a fourth left German's "Ausrichten" ellipsised.
          _ToolbarPill(
            children: [
              _ToolbarSegment(
                label: l10n.transformAutoButton,
                tooltip: l10n.transformAutoTooltip,
                onTap: uprightBusy ? null : () => onUpright(UprightMode.auto),
              ),
              _ToolbarSegment(
                label: l10n.transformVerticalButton,
                tooltip: l10n.transformVerticalTooltip,
                onTap: uprightBusy
                    ? null
                    : () => onUpright(UprightMode.vertical),
              ),
              _ToolbarSegment(
                label: l10n.transformFullButton,
                tooltip: l10n.transformFullTooltip,
                onTap: uprightBusy ? null : () => onUpright(UprightMode.full),
              ),
            ],
          ),
          if (guidedModeActive) ...[
            const SizedBox(height: 8),
            Text(
              l10n.cropGuidedHint,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: DarkmoonColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SliderRow(
            name: l10n.transformStraightenLabel,
            min: -45,
            max: 45,
            value: params.straightenAngle,
            decimals: 1,
            defaultValue: 0,
            // Nailing an exact horizon angle needs finer per-pixel
            // control than the default drag sensitivity gives — nearly
            // 3x the usual full-range drag distance.
            maxFullRangeDragPixels: 1400,
            onChanged: (v) {
              onStraighteningChanged(true);
              onChanged(params.copyWith(straightenAngle: v));
            },
            onChangeEnd: (v) {
              onStraighteningChanged(false);
              onChangeEnd(params.copyWith(straightenAngle: v));
            },
          ),
          const SizedBox(height: 10),
          SliderRow(
            name: l10n.transformVerticalLabel,
            min: -100,
            max: 100,
            value: params.vertical,
            decimals: 0,
            defaultValue: 0,
            onChanged: (v) => onChanged(params.copyWith(vertical: v)),
            onChangeEnd: (v) => onChangeEnd(params.copyWith(vertical: v)),
          ),
          const SizedBox(height: 10),
          SliderRow(
            name: l10n.transformHorizontalLabel,
            min: -100,
            max: 100,
            value: params.horizontal,
            decimals: 0,
            defaultValue: 0,
            onChanged: (v) => onChanged(params.copyWith(horizontal: v)),
            onChangeEnd: (v) => onChangeEnd(params.copyWith(horizontal: v)),
          ),
          const SizedBox(height: 10),
          SliderRow(
            name: l10n.transformAspectLabel,
            min: -100,
            max: 100,
            value: params.aspect,
            decimals: 0,
            defaultValue: 0,
            onChanged: (v) => onChanged(params.copyWith(aspect: v)),
            onChangeEnd: (v) => onChangeEnd(params.copyWith(aspect: v)),
          ),
          const SizedBox(height: 10),
          SliderRow(
            name: l10n.transformScaleLabel,
            min: 100,
            max: 150,
            value: params.scale,
            decimals: 0,
            defaultValue: 100,
            onChanged: (v) => onChanged(params.copyWith(scale: v)),
            onChangeEnd: (v) => onChangeEnd(params.copyWith(scale: v)),
          ),
          const SizedBox(height: 6),
          // Constrain Crop: keeps the crop inside the transformed content,
          // like Meridian's checkbox. The editor applies it on every
          // transform change (see _constrainCropIfOn).
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.cropConstrainLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              SizedBox(
                width: 34,
                height: 21,
                child: FittedBox(
                  child: Switch(
                    key: const Key('crop-constrain'),
                    value: params.constrain,
                    onChanged: (v) =>
                        onChangeEnd(params.copyWith(constrain: v)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    onPressed: onReset,
                    child: Text(l10n.resetTooltip),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: FilledButton(
                    onPressed: onDone,
                    child: Text(l10n.cropDoneButton),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AspectChip extends StatelessWidget {
  const _AspectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DarkmoonColors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? DarkmoonColors.accent : DarkmoonColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? DarkmoonColors.background
                  : DarkmoonColors.textSecondary,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed width of the right-hand controls column, and the horizontal inset
/// its scrolling content sits at. [_SectionHeader] needs both so it can
/// break back out of that inset and paint its bar edge-to-edge.
const _controlsPanelWidth = 300.0;

/// Space kept clear around the photo while the crop tool is open, so the
/// corner handles — drawn centred on the crop rect's corners — always have
/// room to draw in full.
///
/// Slightly wider than the handle's own radius, so the dot clears the edge
/// rather than merely touching it.
const _cropHandleMargin = 10.0;

const _controlsPanelInset = 16.0;
