import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../presets/preset.dart';
import '../theme.dart';

/// Lightroom-style Presets panel — sits below the folder tree in the same
/// left sidebar. Save the current photo's edits as a new preset, click a
/// saved preset to apply it, and rename/export/delete via each row's
/// menu. Import brings in `.xmp` files from disk (Lightroom presets or
/// ones exported from here). A long-press (or the header's select icon)
/// enters multi-select mode for bulk deletion.
class PresetPanel extends StatefulWidget {
  const PresetPanel({
    super.key,
    required this.presets,
    required this.enabled,
    required this.isApplied,
    required this.onApply,
    required this.onSaveNew,
    required this.onImport,
    required this.onRename,
    required this.onExport,
    required this.onDelete,
    required this.onDeleteMany,
  });

  final List<Preset> presets;

  /// False when no photo is selected — applying/saving a preset needs a
  /// photo to act on.
  final bool enabled;

  /// Whether [preset]'s values/curves are exactly what's currently
  /// applied to the selected photo — used to highlight it in the list.
  final bool Function(Preset preset) isApplied;
  final ValueChanged<Preset> onApply;
  final VoidCallback onSaveNew;
  final VoidCallback onImport;
  final void Function(Preset) onRename;
  final void Function(Preset) onExport;
  final void Function(Preset) onDelete;
  final void Function(List<Preset>) onDeleteMany;

  @override
  State<PresetPanel> createState() => _PresetPanelState();
}

class _PresetPanelState extends State<PresetPanel> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  void _enterSelectionMode(String firstId) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..add(firstId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == widget.presets.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(widget.presets.map((p) => p.id));
      }
    });
  }

  void _confirmBulkDelete() {
    final selected = [
      for (final preset in widget.presets)
        if (_selectedIds.contains(preset.id)) preset,
    ];
    _exitSelectionMode();
    widget.onDeleteMany(selected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectionMode
                      ? l10n.presetSelectedCount(_selectedIds.length)
                      : l10n.sidebarPresetsSection,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              if (_selectionMode) ...[
                _HeaderIconButton(
                  tooltip: l10n.presetSelectAllTooltip,
                  icon: _selectedIds.length == widget.presets.length
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.checkmark_circle,
                  onPressed: _toggleSelectAll,
                ),
                const SizedBox(width: 10),
                _HeaderIconButton(
                  tooltip: l10n.presetDeleteLabel,
                  icon: CupertinoIcons.trash,
                  onPressed: _selectedIds.isEmpty ? null : _confirmBulkDelete,
                ),
                const SizedBox(width: 10),
                _HeaderIconButton(
                  tooltip: l10n.cancelButton,
                  icon: CupertinoIcons.xmark,
                  onPressed: _exitSelectionMode,
                ),
              ] else ...[
                if (widget.presets.isNotEmpty) ...[
                  _HeaderIconButton(
                    tooltip: l10n.presetSelectTooltip,
                    icon: CupertinoIcons.checkmark_circle,
                    onPressed: () =>
                        _enterSelectionMode(widget.presets.first.id),
                  ),
                  const SizedBox(width: 10),
                ],
                _HeaderIconButton(
                  tooltip: l10n.presetImportTooltip,
                  icon: CupertinoIcons.tray_arrow_down,
                  onPressed: widget.onImport,
                ),
                const SizedBox(width: 10),
                _HeaderIconButton(
                  tooltip: l10n.presetSaveNewTooltip,
                  icon: CupertinoIcons.add,
                  onPressed: widget.enabled ? widget.onSaveNew : null,
                ),
              ],
            ],
          ),
        ),
        if (widget.presets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              l10n.presetEmptyHint,
              style: const TextStyle(
                color: DarkmoonColors.textMuted,
                fontSize: 11,
              ),
            ),
          )
        else
          for (final preset in widget.presets)
            _PresetRow(
              preset: preset,
              enabled: widget.enabled,
              applied: widget.isApplied(preset),
              selectionMode: _selectionMode,
              selected: _selectedIds.contains(preset.id),
              onApply: () => widget.onApply(preset),
              onLongPress: () => _enterSelectionMode(preset.id),
              onToggleSelected: () => _toggleSelected(preset.id),
              onRename: () => widget.onRename(preset),
              onExport: () => widget.onExport(preset),
              onDelete: () => widget.onDelete(preset),
            ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      width: 24,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.preset,
    required this.enabled,
    required this.applied,
    required this.selectionMode,
    required this.selected,
    required this.onApply,
    required this.onLongPress,
    required this.onToggleSelected,
    required this.onRename,
    required this.onExport,
    required this.onDelete,
  });

  final Preset preset;
  final bool enabled;
  final bool applied;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onApply;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelected;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: selected ? DarkmoonColors.panel : Colors.transparent,
      child: InkWell(
        onTap: selectionMode ? onToggleSelected : (enabled ? onApply : null),
        onLongPress: selectionMode ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 4, top: 5, bottom: 5),
          child: Row(
            children: [
              if (selectionMode)
                Icon(
                  selected
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  size: 14,
                  color: selected
                      ? DarkmoonColors.accent
                      : DarkmoonColors.textMuted,
                )
              else
                Icon(
                  applied
                      ? CupertinoIcons.checkmark_alt
                      : CupertinoIcons.wand_stars,
                  size: 14,
                  color: applied
                      ? DarkmoonColors.accent
                      : DarkmoonColors.textMuted,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: applied
                        ? DarkmoonColors.textPrimary
                        : DarkmoonColors.textSecondary,
                    fontWeight: applied ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
              ),
              if (!selectionMode)
                PopupMenuButton<VoidCallback>(
                  icon: const Icon(
                    CupertinoIcons.ellipsis,
                    size: 14,
                    color: DarkmoonColors.textMuted,
                  ),
                  padding: EdgeInsets.zero,
                  onSelected: (action) => action(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: onRename,
                      child: Text(l10n.presetRenameLabel),
                    ),
                    PopupMenuItem(
                      value: onExport,
                      child: Text(l10n.presetExportLabel),
                    ),
                    PopupMenuItem(
                      value: onDelete,
                      child: Text(l10n.presetDeleteLabel),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
