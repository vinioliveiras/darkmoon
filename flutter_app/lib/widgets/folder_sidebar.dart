import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../animations_config.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';

/// Left-hand library panel, Meridian/Photomator-style: a flat "recent
/// files" list (individual files opened via File > Open File) above a
/// folder tree — one root per folder added via File > Add Folder
/// (persisted in [AppSettings.libraryFolders]), each with subfolders
/// expanded lazily on demand. Clicking a folder loads it into the main
/// editor via [onSelect]; clicking the chevron only expands/collapses
/// without reloading anything. Each root folder also gets a remove
/// button, since only top-level added folders can be removed — subfolders
/// are just navigation, not separately tracked.
class FolderSidebar extends StatelessWidget {
  const FolderSidebar({
    super.key,
    required this.roots,
    required this.recentFiles,
    required this.selectedPath,
    required this.selectedRecentFile,
    required this.onSelect,
    required this.onRemove,
    required this.onSelectRecentFile,
    required this.onRemoveRecentFile,
    required this.rawOnly,
    required this.onRawOnlyChanged,
    required this.includeSubfolders,
    required this.onIncludeSubfoldersChanged,
  });

  final List<String> roots;
  final List<String> recentFiles;
  final String? selectedPath;

  /// The recent-files entry that's currently loaded into the editor, or
  /// null when a folder is loaded instead — highlighted in the list.
  final String? selectedRecentFile;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onSelectRecentFile;
  final ValueChanged<String> onRemoveRecentFile;

  /// Mirrors [AppSettings.rawOnly] — surfaced here too (not just in
  /// Settings) since it directly affects what this browser shows.
  final bool rawOnly;
  final ValueChanged<bool> onRawOnlyChanged;

  /// Mirrors [AppSettings.includeSubfolders] — same reasoning as
  /// [rawOnly], shown right alongside it.
  final bool includeSubfolders;
  final ValueChanged<bool> onIncludeSubfoldersChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (roots.isEmpty && recentFiles.isEmpty) {
      return Container(
        width: 300,
        color: DarkmoonColors.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    l10n.noFolderOpen,
                    style: const TextStyle(
                      color: DarkmoonColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
            _LibraryFilterRow(
              rawOnly: rawOnly,
              onRawOnlyChanged: onRawOnlyChanged,
              includeSubfolders: includeSubfolders,
              onIncludeSubfoldersChanged: onIncludeSubfoldersChanged,
            ),
          ],
        ),
      );
    }
    return Container(
      width: 220,
      color: DarkmoonColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (recentFiles.isNotEmpty) ...[
                    _SidebarSectionHeader(l10n.sidebarRecentFilesSection),
                    for (final path in recentFiles)
                      _RecentFileRow(
                        key: ValueKey(path),
                        path: path,
                        isSelected: path == selectedRecentFile,
                        onTap: () => onSelectRecentFile(path),
                        onRemove: () => onRemoveRecentFile(path),
                      ),
                    const SizedBox(height: 8),
                  ],
                  _SidebarSectionHeader(l10n.sidebarFoldersSection),
                  for (final root in roots)
                    _FolderNode(
                      key: ValueKey(root),
                      path: root,
                      depth: 0,
                      selectedPath: selectedPath,
                      onSelect: onSelect,
                      onRemove: onRemove,
                      initiallyExpanded: true,
                    ),
                ],
              ),
            ),
          ),
          // Pinned below the scrollable folder tree rather than inside it
          // — sits right at the boundary with the Presets section (its
          // sibling below this widget in EditorScreen's layout), not
          // scrolling away with a long folder list.
          _LibraryFilterRow(
            rawOnly: rawOnly,
            onRawOnlyChanged: onRawOnlyChanged,
            includeSubfolders: includeSubfolders,
            onIncludeSubfoldersChanged: onIncludeSubfoldersChanged,
          ),
        ],
      ),
    );
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  const _SidebarSectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// The two library-scan checkboxes, side by side — "RAW files only" and
/// "Subfolder images" (2026-09-01, explicit user request: "à
/// direita do checkbox Raw files only" — to the right of it, not stacked
/// below).
class _LibraryFilterRow extends StatelessWidget {
  const _LibraryFilterRow({
    required this.rawOnly,
    required this.onRawOnlyChanged,
    required this.includeSubfolders,
    required this.onIncludeSubfoldersChanged,
  });

  final bool rawOnly;
  final ValueChanged<bool> onRawOnlyChanged;
  final bool includeSubfolders;
  final ValueChanged<bool> onIncludeSubfoldersChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: _LibraryFilterCheckbox(
              label: l10n.settingsRawOnlyLabel,
              value: rawOnly,
              onChanged: onRawOnlyChanged,
            ),
          ),
          Expanded(
            child: _LibraryFilterCheckbox(
              label: l10n.settingsIncludeSubfoldersLabel,
              value: includeSubfolders,
              onChanged: onIncludeSubfoldersChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryFilterCheckbox extends StatelessWidget {
  const _LibraryFilterCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: FittedBox(
                  child: Checkbox(
                    value: value,
                    onChanged: (v) => onChanged(v ?? false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DarkmoonColors.textSecondary,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentFileRow extends StatelessWidget {
  const _RecentFileRow({
    super.key,
    required this.path,
    required this.isSelected,
    required this.onTap,
    required this.onRemove,
  });

  final String path;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? DarkmoonColors.accent.withValues(alpha: 0.10)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              const SizedBox(width: 18),
              const SizedBox(width: 2),
              Icon(
                CupertinoIcons.doc,
                size: 14,
                color: isSelected
                    ? DarkmoonColors.accent
                    : DarkmoonColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected
                        ? DarkmoonColors.textPrimary
                        : DarkmoonColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Tooltip(
                  message: AppLocalizations.of(
                    context,
                  )!.sidebarRemoveRecentFileTooltip,
                  child: const Icon(
                    CupertinoIcons.xmark,
                    size: 12,
                    color: DarkmoonColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderNode extends StatefulWidget {
  const _FolderNode({
    super.key,
    required this.path,
    required this.depth,
    required this.selectedPath,
    required this.onSelect,
    this.onRemove,
    this.initiallyExpanded = false,
  });

  final String path;
  final int depth;
  final String? selectedPath;
  final ValueChanged<String> onSelect;

  /// Only set on root nodes (depth 0) — subfolders aren't independently
  /// removable, so their nested [_FolderNode]s are built without this.
  final ValueChanged<String>? onRemove;
  final bool initiallyExpanded;

  @override
  State<_FolderNode> createState() => _FolderNodeState();
}

class _FolderNodeState extends State<_FolderNode> {
  late bool _expanded = widget.initiallyExpanded;
  List<Directory>? _children;
  bool _loading = false;

  /// True when this folder no longer exists on disk (deleted/moved/
  /// renamed outside darkmoon, or an external drive unmounted). A cheap
  /// synchronous check — cheaper than round-tripping through an isolate,
  /// and this only runs once per node when it's built, not per frame.
  late final bool _missing = !Directory(widget.path).existsSync();

  @override
  void initState() {
    super.initState();
    // A root node starts with its chevron already drawn as "expanded"
    // (initiallyExpanded: true), but _children is still null at this
    // point — without fetching here, the chevron and the actual "are
    // children showing" state (_expanded && _children != null) disagree
    // until the first tap, which _toggleExpanded then reads as "already
    // expanded, nothing to fetch" and just flips _expanded to false,
    // visually collapsing a node that was never really showing its
    // children. A second tap was needed to finally fetch and show them.
    if (widget.initiallyExpanded) {
      unawaited(_loadChildren());
    }
  }

  String get _name {
    final parts = widget.path
        .split(Platform.pathSeparator)
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? widget.path : parts.last;
  }

  Future<void> _loadChildren() async {
    setState(() => _loading = true);
    final dirs = await _listSubfolders(widget.path);
    if (!mounted) {
      return;
    }
    setState(() {
      _children = dirs;
      _loading = false;
    });
  }

  Future<void> _toggleExpanded() async {
    if (!_expanded && _children == null) {
      await _loadChildren();
    }
    setState(() => _expanded = !_expanded);
  }

  static Future<List<Directory>> _listSubfolders(String path) async {
    try {
      final entries = await Directory(path).list().toList();
      final dirs = entries.whereType<Directory>().toList()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      return dirs;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.path == widget.selectedPath;
    final l10n = AppLocalizations.of(context)!;
    // A missing folder can't usefully be selected or expanded — there's
    // nothing to load or list — so it just reads as disabled/dimmed with
    // a warning icon in place of the usual folder one; the remove button
    // (root nodes only) stays the one live affordance, wrapped in a
    // tooltip explaining why.
    final row = Padding(
      padding: EdgeInsets.only(
        left: 8.0 + widget.depth * 16,
        right: 8,
        top: 5,
        bottom: 5,
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _missing ? null : _toggleExpanded,
            child: SizedBox(
              width: 18,
              height: 18,
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(3),
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: DarkmoonColors.textMuted,
                      ),
                    )
                  : _missing
                  ? null
                  : AnimatedRotation(
                      duration: AnimationsConfig.duration(
                        context,
                        const Duration(milliseconds: 160),
                      ),
                      curve: Curves.easeOutCubic,
                      // chevron_right rotated a quarter turn *is*
                      // chevron_down, so one icon smoothly rotates
                      // between the two states instead of an instant
                      // icon swap.
                      turns: _expanded ? 0.25 : 0.0,
                      child: const Icon(
                        CupertinoIcons.chevron_right,
                        size: 12,
                        color: DarkmoonColors.textMuted,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            _missing
                ? CupertinoIcons.exclamationmark_triangle
                : CupertinoIcons.folder,
            size: 14,
            color: _missing
                ? DarkmoonColors.textMuted
                : (isSelected
                      ? DarkmoonColors.accent
                      : DarkmoonColors.textMuted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _missing
                    ? DarkmoonColors.textMuted
                    : (isSelected
                          ? DarkmoonColors.textPrimary
                          : DarkmoonColors.textSecondary),
                fontSize: 12,
              ),
            ),
          ),
          if (widget.onRemove != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onRemove!(widget.path),
              child: Tooltip(
                message: _missing
                    ? l10n.sidebarFolderNotFoundTooltip
                    : l10n.sidebarRemoveFolderTooltip,
                child: const Icon(
                  CupertinoIcons.xmark,
                  size: 12,
                  color: DarkmoonColors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _missing
            ? row
            : Material(
                color: isSelected
                    ? DarkmoonColors.accent.withValues(alpha: 0.10)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => widget.onSelect(widget.path),
                  child: row,
                ),
              ),
        _AnimatedFolderExpand(
          expanded: _expanded && _children != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final dir in _children ?? const <Directory>[])
                _FolderNode(
                  path: dir.path,
                  depth: widget.depth + 1,
                  selectedPath: widget.selectedPath,
                  onSelect: widget.onSelect,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Animates a folder row's children growing/shrinking in under it —
/// [child] stays mounted the whole time (so a nested folder's own
/// expanded state survives a collapse/expand of its parent), just laid
/// out at zero height and fully transparent while [expanded] is false.
/// `ClipRect` hides the part of [child] that doesn't fit during the
/// animation.
class _AnimatedFolderExpand extends StatelessWidget {
  const _AnimatedFolderExpand({required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = AnimationsConfig.duration(
      context,
      const Duration(milliseconds: 180),
    );
    return ClipRect(
      child: AnimatedAlign(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: expanded ? 1.0 : 0.0,
        child: AnimatedOpacity(
          duration: duration,
          curve: Curves.easeOutCubic,
          opacity: expanded ? 1.0 : 0.0,
          child: child,
        ),
      ),
    );
  }
}
