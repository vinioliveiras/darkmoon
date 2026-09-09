import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../animations_config.dart';
import '../l10n/app_localizations.dart';
import '../presets/preset.dart';
import '../presets/preset_thumbnails.dart';
import '../theme.dart';

/// How long entering or leaving selection mode takes. Matches the folder
/// tree's expand/collapse, which is the other place in this sidebar where
/// a control grows out of nothing.
const _selectionModeDuration = Duration(milliseconds: 180);
const _selectionModeCurve = Curves.easeOutCubic;

/// Meridian-style Presets panel — sits below the folder tree in the same
/// left sidebar. Save the current photo's edits as a new preset, click a
/// saved preset to apply it, and rename/export/delete via each row's
/// menu. Import brings in `.xmp` files from disk (Meridian presets or
/// ones exported from here). The header's select icon enters multi-select
/// mode for bulk delete / export.
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
    required this.onExportMany,
    this.thumbnails,
  });

  /// Renders the current photo through each preset. Null when the
  /// preview is switched off in Settings, which is the whole of what
  /// switching it off does — no thumbnails asked for, none rendered.
  final PresetThumbnailStore? thumbnails;

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
  final void Function(List<Preset>) onExportMany;

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

  List<Preset> get _selectedPresets => [
    for (final preset in widget.presets)
      if (_selectedIds.contains(preset.id)) preset,
  ];

  void _confirmBulkDelete() {
    final selected = _selectedPresets;
    _exitSelectionMode();
    widget.onDeleteMany(selected);
  }

  void _bulkExport() {
    final selected = _selectedPresets;
    _exitSelectionMode();
    widget.onExportMany(selected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header stays outside the scroll view below so the section title
        // and action buttons remain fixed in place while a long preset
        // list scrolls underneath them.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
          child: Row(
            children: [
              Expanded(
                // Keyed on the mode, not on the text: within selection
                // mode the count changes on every tap, and cross-fading
                // the header on each one reads as flicker rather than as
                // feedback.
                child: AnimatedSwitcher(
                  duration: AnimationsConfig.duration(
                    context,
                    _selectionModeDuration,
                  ),
                  switchInCurve: _selectionModeCurve,
                  switchOutCurve: _selectionModeCurve,
                  // AnimatedSwitcher's default layout builder stacks its
                  // children centred, which put this heading in the middle
                  // of the Expanded instead of at its left edge — visibly
                  // out of line with the FOLDERS heading above it, a plain
                  // Text at the same 12px inset (2026-09-09). Same stack,
                  // anchored to the start instead.
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [...previous, if (current != null) current],
                  ),
                  child: Text(
                    _selectionMode
                        ? l10n.presetSelectedCount(_selectedIds.length)
                        : l10n.sidebarPresetsSection,
                    key: ValueKey(_selectionMode),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
              // Both sets of buttons are always here, interleaved so the
              // two that share the checkmark glyph sit in the same place:
              // entering selection mode then reads as the header growing
              // around a control that stayed put, rather than as one bar
              // being replaced by another.
              _CollapsibleSlot(
                visible: _selectionMode,
                child: _HeaderIconButton(
                  tooltip: l10n.presetSelectAllTooltip,
                  icon: _selectedIds.length == widget.presets.length
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.checkmark_circle,
                  onPressed: _toggleSelectAll,
                ),
              ),
              _CollapsibleSlot(
                visible: !_selectionMode && widget.presets.isNotEmpty,
                child: _HeaderIconButton(
                  tooltip: l10n.presetSelectTooltip,
                  icon: CupertinoIcons.checkmark_circle,
                  onPressed: widget.presets.isEmpty
                      ? null
                      : () => _enterSelectionMode(widget.presets.first.id),
                ),
              ),
              _CollapsibleSlot(
                visible: _selectionMode,
                child: _HeaderIconButton(
                  tooltip: l10n.presetExportManyTooltip,
                  icon: CupertinoIcons.tray_arrow_up,
                  onPressed: _selectedIds.isEmpty ? null : _bulkExport,
                ),
              ),
              _CollapsibleSlot(
                visible: !_selectionMode,
                child: _HeaderIconButton(
                  tooltip: l10n.presetImportTooltip,
                  icon: CupertinoIcons.tray_arrow_down,
                  onPressed: widget.onImport,
                ),
              ),
              _CollapsibleSlot(
                visible: _selectionMode,
                child: _HeaderIconButton(
                  tooltip: l10n.presetDeleteLabel,
                  icon: CupertinoIcons.trash,
                  onPressed: _selectedIds.isEmpty ? null : _confirmBulkDelete,
                ),
              ),
              _CollapsibleSlot(
                visible: !_selectionMode,
                child: _HeaderIconButton(
                  tooltip: l10n.presetSaveNewTooltip,
                  icon: CupertinoIcons.add,
                  onPressed: widget.enabled ? widget.onSaveNew : null,
                ),
              ),
              _CollapsibleSlot(
                visible: _selectionMode,
                child: _HeaderIconButton(
                  tooltip: l10n.cancelButton,
                  icon: CupertinoIcons.xmark,
                  onPressed: _exitSelectionMode,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.presets.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    l10n.presetEmptyHint,
                    style: const TextStyle(
                      color: DarkmoonColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                )
              // A builder, not a Column: it constructs only the rows on
              // screen, and a row asks for its thumbnail when it is built.
              // That is what keeps a library of eighty presets from
              // queueing eighty renders the moment the panel opens.
              : ListView.builder(
                  padding: const EdgeInsets.only(right: kScrollbarGutter),
                  itemCount: widget.presets.length,
                  itemBuilder: (context, index) {
                    final preset = widget.presets[index];
                    return _PresetRow(
                      preset: preset,
                      enabled: widget.enabled,
                      applied: widget.isApplied(preset),
                      selectionMode: _selectionMode,
                      selected: _selectedIds.contains(preset.id),
                      thumbnails: widget.thumbnails,
                      onApply: () => widget.onApply(preset),
                      onToggleSelected: () => _toggleSelected(preset.id),
                      onRename: () => widget.onRename(preset),
                      onExport: () => widget.onExport(preset),
                      onDelete: () => widget.onDelete(preset),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// A header slot that grows in from nothing and fades in when [visible],
/// and collapses back out when not.
///
/// The horizontal twin of the folder tree's expand/collapse, and the
/// reason the header can morph between its two sets of buttons instead of
/// swapping them: an [AnimatedSwitcher] across the whole group would size
/// itself to whichever set is wider for the duration of the cross-fade and
/// snap at the end, which is the jump this exists to avoid. Every button
/// is always in the tree; only its width and opacity move.
///
/// The gap between buttons lives inside the slot so it collapses with it —
/// a fixed `SizedBox` between slots would leave a growing run of dead
/// space as buttons disappeared.
class _CollapsibleSlot extends StatelessWidget {
  const _CollapsibleSlot({
    required this.visible,
    required this.child,
    this.gap = 10,
  });

  final bool visible;
  final Widget child;

  /// Leading space, folded into the slot so it collapses with it. Zero for
  /// a slot that is already first in its row.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final duration = AnimationsConfig.duration(
      context,
      _selectionModeDuration,
    );
    return ClipRect(
      child: AnimatedAlign(
        duration: duration,
        curve: _selectionModeCurve,
        alignment: Alignment.centerLeft,
        widthFactor: visible ? 1.0 : 0.0,
        child: AnimatedOpacity(
          duration: duration,
          curve: _selectionModeCurve,
          opacity: visible ? 1.0 : 0.0,
          // A collapsed slot is still a hit target at zero width in some
          // layouts, and a button nobody can see must not be pressable.
          child: IgnorePointer(
            ignoring: !visible,
            child: Padding(
              padding: EdgeInsets.only(left: gap),
              child: child,
            ),
          ),
        ),
      ),
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
        padding: const EdgeInsets.only(right: kScrollbarGutter),
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
      ),
    );
  }
}

class _PresetRow extends StatefulWidget {
  const _PresetRow({
    required this.preset,
    required this.enabled,
    required this.applied,
    required this.selectionMode,
    required this.selected,
    required this.thumbnails,
    required this.onApply,
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
  final PresetThumbnailStore? thumbnails;
  final VoidCallback onApply;
  final VoidCallback onToggleSelected;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  State<_PresetRow> createState() => _PresetRowState();
}

class _PresetRowState extends State<_PresetRow> {
  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(_PresetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _request();
  }

  /// Asking on build is safe and is the point: the store answers at once
  /// when the thumbnail is cached or already queued, so a row scrolling
  /// back into view costs nothing, and a row that has never been seen is
  /// the only thing that ever queues work.
  void _request() => widget.thumbnails?.request(widget.preset);

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    final enabled = widget.enabled;
    final applied = widget.applied;
    final selectionMode = widget.selectionMode;
    final selected = widget.selected;
    final onApply = widget.onApply;
    final onToggleSelected = widget.onToggleSelected;
    final onRename = widget.onRename;
    final onExport = widget.onExport;
    final onDelete = widget.onDelete;
    final l10n = AppLocalizations.of(context)!;
    final showThumbnail = widget.thumbnails != null;
    // A card per row rather than a flush list line: the thumbnail is the
    // point of this list now, and a picture needs an edge of its own to
    // read as a picture rather than as part of the row above it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      child: Material(
        color: selected
            ? DarkmoonColors.panel
            : (applied
                  ? DarkmoonColors.accent.withValues(alpha: 0.12)
                  : DarkmoonColors.sectionCardBackground),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selectionMode ? onToggleSelected : (enabled ? onApply : null),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              showThumbnail ? 8 : 12,
              showThumbnail ? 8 : 6,
              4,
              showThumbnail ? 8 : 6,
            ),
            child: Row(
              children: [
                // Only in selection mode: outside it the thumbnail is what
                // identifies the row, so a leading glyph beside a picture
                // of the preset is just clutter. It slides the row's
                // contents aside as it grows rather than appearing under
                // them, which is what makes entering the mode read as one
                // movement across the whole list.
                _CollapsibleSlot(
                  visible: selectionMode,
                  gap: 0,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      selected
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      size: 14,
                      color: selected
                          ? DarkmoonColors.accent
                          : DarkmoonColors.textMuted,
                    ),
                  ),
                ),
                if (showThumbnail)
                  _PresetThumbnail(
                    store: widget.thumbnails!,
                    presetId: preset.id,
                  )
                else if (!selectionMode)
                  // With previews off the row still needs something to
                  // anchor its left edge.
                  Icon(
                    CupertinoIcons.film,
                    size: 14,
                    color: applied
                        ? DarkmoonColors.accent
                        : DarkmoonColors.textMuted,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        preset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: applied
                              ? DarkmoonColors.accent
                              : DarkmoonColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.film,
                            size: 10,
                            color: DarkmoonColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.presetTypeBadge,
                            style: const TextStyle(
                              color: DarkmoonColors.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              // Fixed-width trailing slot in *both* modes — an empty box
              // in selection mode instead of just dropping the menu
              // button, so switching modes doesn't reflow the name column
              // and make the list look like it jumped.
              SizedBox(
                width: 26,
                height: 26,
                // Fades rather than vanishing, so the row's right edge
                // settles at the same moment its left edge does.
                child: AnimatedOpacity(
                  duration: AnimationsConfig.duration(
                    context,
                    _selectionModeDuration,
                  ),
                  curve: _selectionModeCurve,
                  opacity: selectionMode ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: selectionMode,
                    child: PopupMenuButton<VoidCallback>(
                        // Uses `child` rather than `icon` — `icon` wraps in
                        // an IconButton, which inherits the app's global
                        // IconButtonTheme (a bordered, filled rounded-square
                        // background meant for standalone toolbar buttons).
                        // That reads as a distracting box around a menu
                        // trigger that's supposed to sit quietly at the end
                        // of a list row, so this stays a bare icon with no
                        // persistent background.
                        padding: const EdgeInsets.only(right: kScrollbarGutter),
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
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            CupertinoIcons.ellipsis,
                            size: 14,
                            color: DarkmoonColors.textMuted,
                          ),
                        ),
                      ),
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The current photo rendered through one preset, or an empty well while
/// that render is still queued.
///
/// The well is drawn either way so the row does not change height when
/// the image arrives — a list that reflows as you scroll it is worse than
/// one that starts blank.
class _PresetThumbnail extends StatelessWidget {
  const _PresetThumbnail({required this.store, required this.presetId});

  final PresetThumbnailStore store;
  final String presetId;

  /// Square, by request. It centre-crops the frame rather than showing
  /// all of it, which costs some of the scene — but a preset's whole
  /// effect is colour and tone, and those read from any part of the
  /// picture. It also keeps the name column wider.
  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final image = store.thumbnailFor(presetId);
        return Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: DarkmoonColors.canvas,
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: image == null
              ? null
              // Cloned because RawImage's render object takes ownership of
              // what it is handed and disposes it, and the store still
              // needs this one for every other row and rebuild.
              : RawImage(image: image.clone(), fit: BoxFit.cover),
        );
      },
    );
  }
}
