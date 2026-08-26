import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../render/mask.dart';
import '../theme.dart';
import 'slider_row.dart';
import 'styled_dropdown.dart';

/// Sentinel id for the always-present base layer — the whole photo, i.e.
/// the editor's existing global adjustments. Not a real [MaskLayer].
const imageMaskId = 'image';

/// Photomator-style mask picker: a pill showing the mask currently being
/// edited (tap to switch between "Image" and any added masks) plus a "+"
/// button to add a new one. When a real mask (not "Image") is active,
/// shows its enabled/invert toggles and a delete button underneath.
class MaskSelector extends StatelessWidget {
  const MaskSelector({
    super.key,
    required this.masks,
    required this.activeId,
    required this.onSelect,
    required this.onAdd,
    required this.onToggleEnabled,
    required this.onToggleInverted,
    required this.onClone,
    required this.onDelete,
    required this.onOpacityChanged,
    required this.onOpacityChangeEnd,
    required this.overlayVisible,
    required this.onToggleOverlayVisible,
    required this.overlayOpacity,
    required this.onOverlayOpacityChanged,
  });

  final List<MaskLayer> masks;
  final String activeId;
  final ValueChanged<String> onSelect;
  final ValueChanged<MaskType> onAdd;
  final VoidCallback onToggleEnabled;
  final VoidCallback onToggleInverted;

  /// Duplicates the active mask (geometry, values, curves — everything
  /// but the id/name) into a new sibling layer, selected right after.
  final VoidCallback onClone;
  final VoidCallback onDelete;

  /// How strongly the active mask's effect applies, 0..100 — see
  /// [MaskLayer.opacity].
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<double> onOpacityChangeEnd;

  /// Whether the active mask's on-canvas overlay (shaded coverage area,
  /// handles) is currently shown.
  final bool overlayVisible;
  final VoidCallback onToggleOverlayVisible;

  /// How opaque that on-canvas overlay's shading is (0..1), one value per
  /// mask type — a display-only preference, independent of
  /// [onOpacityChanged]'s real mask-effect strength. The active mask's own
  /// type picks which entry is shown/edited.
  final Map<MaskType, double> overlayOpacity;
  final void Function(MaskType type, double value) onOverlayOpacityChanged;

  MaskLayer? get _active => activeId == imageMaskId
      ? null
      : masks.where((m) => m.id == activeId).firstOrNull;

  IconData _typeIcon(MaskType type) => switch (type) {
    MaskType.linearGradient => CupertinoIcons.slider_horizontal_3,
    MaskType.radialGradient => CupertinoIcons.circle_fill,
    MaskType.brush => CupertinoIcons.paintbrush,
    MaskType.colorRange => CupertinoIcons.eyedropper,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final active = _active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            l10n.masksTitle,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: StyledDropdown<String>(
                value: activeId,
                items: [
                  StyledDropdownItem(
                    value: imageMaskId,
                    label: l10n.maskImageLayer,
                    icon: CupertinoIcons.photo,
                  ),
                  for (final mask in masks)
                    StyledDropdownItem(
                      value: mask.id,
                      label: mask.name,
                      icon: _typeIcon(mask.type),
                    ),
                ],
                onChanged: onSelect,
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: l10n.maskAddTooltip,
              child: StyledDropdown<MaskType>(
                value: null,
                placeholder: '',
                leadingIcon: CupertinoIcons.add,
                showChevron: false,
                width: 34,
                menuWidth: 190,
                menuAlignRight: true,
                items: [
                  StyledDropdownItem(
                    value: MaskType.linearGradient,
                    label: l10n.maskLinearGradient,
                    icon: _typeIcon(MaskType.linearGradient),
                  ),
                  StyledDropdownItem(
                    value: MaskType.radialGradient,
                    label: l10n.maskRadialGradient,
                    icon: _typeIcon(MaskType.radialGradient),
                  ),
                  StyledDropdownItem(
                    value: MaskType.brush,
                    label: l10n.maskBrush,
                    icon: _typeIcon(MaskType.brush),
                  ),
                  StyledDropdownItem(
                    value: MaskType.colorRange,
                    label: l10n.maskColorRange,
                    icon: _typeIcon(MaskType.colorRange),
                  ),
                ],
                onChanged: onAdd,
              ),
            ),
          ],
        ),
        if (active != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: IconButton(
                    tooltip: overlayVisible
                        ? l10n.maskOverlayVisibleTooltip
                        : l10n.maskOverlayHiddenTooltip,
                    onPressed: onToggleOverlayVisible,
                    icon: Icon(
                      overlayVisible
                          ? CupertinoIcons.eye
                          : CupertinoIcons.eye_slash,
                      size: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: IconButton(
                    tooltip: active.enabled
                        ? l10n.maskDisableTooltip
                        : l10n.maskEnableTooltip,
                    onPressed: onToggleEnabled,
                    icon: Icon(
                      CupertinoIcons.power,
                      size: 15,
                      color: active.enabled
                          ? DarkmoonColors.accent
                          : DarkmoonColors.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: IconButton(
                    tooltip: l10n.maskCloneTooltip,
                    onPressed: onClone,
                    icon: const Icon(CupertinoIcons.square_on_square, size: 15),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: IconButton(
                    tooltip: l10n.maskDeleteTooltip,
                    onPressed: onDelete,
                    icon: const Icon(CupertinoIcons.trash, size: 15),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Enable/disable now lives in the power-icon button above, so this
          // row carries only Invert (full width).
          _MaskToggleChip(
            label: l10n.maskInvertLabel,
            value: active.inverted,
            onTap: onToggleInverted,
          ),
          const SizedBox(height: 8),
          SliderRow(
            name: l10n.maskOpacityLabel,
            min: 0,
            max: 100,
            value: active.opacity,
            decimals: 0,
            defaultValue: 100,
            onChanged: onOpacityChanged,
            onChangeEnd: onOpacityChangeEnd,
          ),
          if (overlayVisible) ...[
            const SizedBox(height: 8),
            SliderRow(
              name: l10n.maskOverlayOpacityLabel,
              min: 0,
              max: 100,
              value: (overlayOpacity[active.type] ?? 0) * 100,
              decimals: 0,
              onChanged: (v) => onOverlayOpacityChanged(active.type, v / 100),
            ),
          ],
        ],
      ],
    );
  }
}

class _MaskToggleChip extends StatelessWidget {
  const _MaskToggleChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value
          ? DarkmoonColors.accent.withValues(alpha: 0.22)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: value ? DarkmoonColors.accent : DarkmoonColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: value
                  ? DarkmoonColors.accent
                  : DarkmoonColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
