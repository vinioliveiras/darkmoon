import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../render/mask.dart';
import '../theme.dart';
import 'slider_row.dart';

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
        Row(
          children: [
            Expanded(
              child: _MaskPill(
                label: active == null ? l10n.maskImageLayer : active.name,
                icon: active == null
                    ? CupertinoIcons.photo
                    : _typeIcon(active.type),
                onTap: () => _showSwitchMenu(context),
              ),
            ),
            if (active != null) ...[
              const SizedBox(width: 6),
              SizedBox(
                height: 34,
                width: 34,
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
              const SizedBox(width: 6),
              SizedBox(
                height: 34,
                width: 34,
                child: IconButton(
                  tooltip: l10n.maskDeleteTooltip,
                  onPressed: onDelete,
                  icon: const Icon(CupertinoIcons.trash, size: 15),
                ),
              ),
            ],
            const SizedBox(width: 6),
            SizedBox(
              height: 34,
              width: 34,
              child: IconButton(
                tooltip: l10n.maskAddTooltip,
                onPressed: () => _showAddMenu(context),
                icon: const Icon(CupertinoIcons.add, size: 16),
              ),
            ),
          ],
        ),
        if (active != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _MaskToggleChip(
                  label: l10n.maskEnabledLabel,
                  value: active.enabled,
                  onTap: onToggleEnabled,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MaskToggleChip(
                  label: l10n.maskInvertLabel,
                  value: active.inverted,
                  onTap: onToggleInverted,
                ),
              ),
            ],
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

  Future<void> _showSwitchMenu(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final box = context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      ),
      Offset.zero &
          (Overlay.of(context).context.findRenderObject()! as RenderBox).size,
    );
    final selected = await showMenu<String>(
      context: context,
      position: position,
      color: DarkmoonColors.surfaceRaised,
      items: [
        PopupMenuItem(value: imageMaskId, child: Text(l10n.maskImageLayer)),
        for (final mask in masks)
          PopupMenuItem(value: mask.id, child: Text(mask.name)),
      ],
    );
    if (selected != null) {
      onSelect(selected);
    }
  }

  Future<void> _showAddMenu(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final box = context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      ),
      Offset.zero &
          (Overlay.of(context).context.findRenderObject()! as RenderBox).size,
    );
    final selected = await showMenu<MaskType>(
      context: context,
      position: position,
      color: DarkmoonColors.surfaceRaised,
      items: [
        PopupMenuItem(
          value: MaskType.linearGradient,
          child: Row(
            children: [
              const Icon(CupertinoIcons.slider_horizontal_3, size: 15),
              const SizedBox(width: 8),
              Text(l10n.maskLinearGradient),
            ],
          ),
        ),
        PopupMenuItem(
          value: MaskType.radialGradient,
          child: Row(
            children: [
              const Icon(CupertinoIcons.circle_fill, size: 15),
              const SizedBox(width: 8),
              Text(l10n.maskRadialGradient),
            ],
          ),
        ),
        PopupMenuItem(
          value: MaskType.brush,
          child: Row(
            children: [
              const Icon(CupertinoIcons.paintbrush, size: 15),
              const SizedBox(width: 8),
              Text(l10n.maskBrush),
            ],
          ),
        ),
        PopupMenuItem(
          value: MaskType.colorRange,
          child: Row(
            children: [
              const Icon(CupertinoIcons.eyedropper, size: 15),
              const SizedBox(width: 8),
              Text(l10n.maskColorRange),
            ],
          ),
        ),
      ],
    );
    if (selected != null) {
      onAdd(selected);
    }
  }
}

class _MaskPill extends StatelessWidget {
  const _MaskPill({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DarkmoonColors.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: DarkmoonColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: DarkmoonColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DarkmoonColors.textPrimary,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_down,
                size: 13,
                color: DarkmoonColors.textMuted,
              ),
            ],
          ),
        ),
      ),
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
