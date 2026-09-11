import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../render/mask.dart';
import '../theme.dart';
import 'slider_row.dart';
import 'styled_dropdown.dart';

export '../render/mask.dart' show imageMaskId;

/// Photomator-style mask picker: a pill showing the mask currently being
/// edited (tap to switch between "Image" and any added masks) plus a "+"
/// button to add a new one. Only that: the active mask's own controls
/// are [MaskLayerControls], so the picker can stay pinned under the
/// histogram while they scroll with the sections (user's call,
/// 2026-09-11).
class MaskSelector extends StatelessWidget {
  const MaskSelector({
    super.key,
    required this.masks,
    required this.activeId,
    required this.onSelect,
    required this.onAdd,
  });

  final List<MaskLayer> masks;
  final String activeId;
  final ValueChanged<String> onSelect;
  final ValueChanged<MaskType> onAdd;

  IconData _typeIcon(MaskType type) => switch (type) {
    MaskType.linearGradient => CupertinoIcons.arrowtriangle_down_fill,
    MaskType.radialGradient => CupertinoIcons.circle_fill,
    MaskType.brush => CupertinoIcons.paintbrush,
    MaskType.colorRange => CupertinoIcons.eyedropper,
    MaskType.wholeImage => CupertinoIcons.photo,
    MaskType.luminance => CupertinoIcons.sun_max,
    MaskType.flow => CupertinoIcons.drop,
    MaskType.subject => CupertinoIcons.person_crop_square,
    MaskType.sky => CupertinoIcons.cloud,
    MaskType.foreground => CupertinoIcons.square_stack_3d_down_right,
    MaskType.depth => CupertinoIcons.cube_box,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                showBorder: false,
                showBackground: false,
                width: 34,
                menuWidth: 190,
                // Every mask type at once, no scrolling: the list is
                // fixed and short enough to scan, and hiding half of it
                // behind a scroll is how a type nobody knows exists gets
                // added. A generous cap rather than a measured height —
                // the popup shrink-wraps its content, so this only ever
                // matters as the ceiling, and StyledDropdown clamps it to
                // the room actually available.
                maxMenuHeight: 560,
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
                  StyledDropdownItem(
                    value: MaskType.luminance,
                    label: l10n.maskLuminance,
                    icon: _typeIcon(MaskType.luminance),
                  ),
                  StyledDropdownItem(
                    value: MaskType.flow,
                    label: l10n.maskFlow,
                    icon: _typeIcon(MaskType.flow),
                  ),
                  StyledDropdownItem(
                    value: MaskType.wholeImage,
                    label: l10n.maskWholeImage,
                    icon: _typeIcon(MaskType.wholeImage),
                  ),
                  // The four a model answers, grouped last so the menu
                  // reads cheap-and-instant first, then the ones that
                  // think about it.
                  StyledDropdownItem(
                    value: MaskType.subject,
                    label: l10n.maskSubject,
                    icon: _typeIcon(MaskType.subject),
                  ),
                  StyledDropdownItem(
                    value: MaskType.sky,
                    label: l10n.maskSky,
                    icon: _typeIcon(MaskType.sky),
                  ),
                  StyledDropdownItem(
                    value: MaskType.foreground,
                    label: l10n.maskForeground,
                    icon: _typeIcon(MaskType.foreground),
                  ),
                  StyledDropdownItem(
                    value: MaskType.depth,
                    label: l10n.maskDepth,
                    icon: _typeIcon(MaskType.depth),
                  ),
                ],
                onChanged: onAdd,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The active mask's own controls, under the picker: the overlay eye,
/// enable, clone and delete, Invert and the opacity slider. Nothing for
/// the base image layer.
class MaskLayerControls extends StatelessWidget {
  const MaskLayerControls({
    super.key,
    required this.masks,
    required this.activeId,
    required this.onToggleEnabled,
    required this.onToggleInverted,
    required this.onClone,
    required this.onDelete,
    required this.onOpacityChanged,
    required this.onOpacityChangeEnd,
    required this.overlayVisible,
    required this.onToggleOverlayVisible,
    required this.overlayOpacity,
  });

  final List<MaskLayer> masks;
  final String activeId;
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

  MaskLayer? get _active => activeId == imageMaskId
      ? null
      : masks.where((m) => m.id == activeId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final active = _active;
    if (active == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                    active.enabled
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
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
