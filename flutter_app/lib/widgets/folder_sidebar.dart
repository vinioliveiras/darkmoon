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
    required this.onOpenFile,
    required this.onOpenFolder,
    this.onDropPaths,
    this.onDropFolder,
    this.refreshToken,
    this.onCreateSubfolder,
    this.onDeleteFolder,
    this.width = 300,
  });

  /// The column's width — the editor passes its left column's, so the
  /// tree fills it edge to edge (it used to be 220 in a 300 column).
  final double width;

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

  /// Behind the "+" beside the FOLDERS heading — the two things that
  /// used to be the File menu.
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;

  /// Photos (a `List<String>` of paths) dragged onto a folder row land
  /// here — the library's "move into this album". Null: rows accept no
  /// drops.
  final void Function(String folder, List<String> paths)? onDropPaths;

  /// A folder row dragged onto another lands here (the dragged folder,
  /// then the folder it was dropped on). Null: folder rows cannot be
  /// dragged. Root folders are never dragged — they are the library.
  final void Function(String folder, String targetParent)? onDropFolder;

  /// Changing this makes every expanded row re-list its subfolders —
  /// after a folder was created or moved.
  final Object? refreshToken;

  /// A folder row's context menu (2026-09-11): "new album here" creates
  /// a folder inside it, "delete album" sends it to the Recycle Bin.
  /// Null: rows have no menu. The header's "+" also offers "new album"
  /// inside the selected folder when this is set.
  final ValueChanged<String>? onCreateSubfolder;
  final ValueChanged<String>? onDeleteFolder;
  final ValueChanged<bool> onIncludeSubfoldersChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Built once and used by both branches below. The empty state needs it
    // as much as the populated one — more, in fact: with no top menu bar
    // any more, this "+" is the only way to open anything at all, and a
    // fresh install that hid it would be a dead end.
    final header = _SidebarSectionHeader(
      l10n.sidebarFoldersSection,
      trailing: PopupMenuButton<VoidCallback>(
        tooltip: l10n.sidebarOpenTooltip,
        offset: const Offset(0, 28),
        itemBuilder: (context) => [
          PopupMenuItem(value: onOpenFile, child: Text(l10n.menuOpenFile)),
          PopupMenuItem(value: onOpenFolder, child: Text(l10n.menuOpenFolder)),
          if (onCreateSubfolder != null && selectedPath != null)
            PopupMenuItem(
              value: () => onCreateSubfolder!(selectedPath!),
              child: Text(l10n.sidebarNewAlbumAction),
            ),
        ],
        onSelected: (callback) => callback(),
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(
            CupertinoIcons.add,
            size: 15,
            color: DarkmoonColors.textSecondary,
          ),
        ),
      ),
    );
    if (roots.isEmpty && recentFiles.isEmpty) {
      return Container(
        width: width,
        color: DarkmoonColors.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The populated branch draws this inside a scroll view that
            // reserves the scrollbar's gutter; without the same inset here
            // the button would jump sideways the moment a folder is added.
            Padding(
              padding: const EdgeInsets.only(right: kScrollbarGutter),
              child: header,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
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
      width: width,
      color: DarkmoonColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: kScrollbarGutter),
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
                  header,
                  for (final root in roots)
                    _FolderNode(
                      key: ValueKey(root),
                      path: root,
                      depth: 0,
                      selectedPath: selectedPath,
                      onSelect: onSelect,
                      onRemove: onRemove,
                      initiallyExpanded: true,
                      onDropPaths: onDropPaths,
                      onDropFolder: onDropFolder,
                      refreshToken: refreshToken,
                      onCreateSubfolder: onCreateSubfolder,
                      onDeleteFolder: onDeleteFolder,
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
  const _SidebarSectionHeader(this.label, {this.trailing});

  final String label;

  /// Sits at the right end of the heading, in the same column as the
  /// remove buttons on the folder rows below it: those are 8px in from
  /// their row's right edge, and the padding here puts this button's
  /// glyph at the same 8 once its own tap padding is counted.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: Theme.of(context).textTheme.labelSmall);
    if (trailing == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: text,
      );
    }
    return Padding(
      // Same 12 on the left as the plain header, so the two section
      // titles line up with each other. Tighter vertically because the
      // button is taller than the label and would otherwise make this
      // heading stand off from its neighbour.
      padding: const EdgeInsets.fromLTRB(12, 4, 2, 2),
      child: Row(
        children: [
          Expanded(child: text),
          trailing!,
        ],
      ),
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
    this.onDropPaths,
    this.onDropFolder,
    this.refreshToken,
    this.onCreateSubfolder,
    this.onDeleteFolder,
  });

  final String path;
  final int depth;
  final String? selectedPath;
  final ValueChanged<String> onSelect;
  final void Function(String folder, List<String> paths)? onDropPaths;
  final void Function(String folder, String targetParent)? onDropFolder;
  final Object? refreshToken;
  final ValueChanged<String>? onCreateSubfolder;
  final ValueChanged<String>? onDeleteFolder;

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

  @override
  void didUpdateWidget(covariant _FolderNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken && _children != null) {
      unawaited(_loadChildren());
    }
  }

  /// Whether a drag carrying [data] may land on this folder: photos
  /// always; a folder unless it is this one or one of its ancestors.
  bool _accepts(Object? data) {
    if (widget.onDropPaths != null && data is List<String>) {
      return true;
    }
    if (widget.onDropFolder != null && data is String) {
      return !p.equals(data, widget.path) && !p.isWithin(data, widget.path);
    }
    return false;
  }

  Future<void> _showMenu(BuildContext context, Offset globalPosition) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.onCreateSubfolder != null)
          PopupMenuItem(
            value: () => widget.onCreateSubfolder!(widget.path),
            child: Text(l10n.sidebarNewAlbumAction),
          ),
        if (widget.onDeleteFolder != null)
          PopupMenuItem(
            value: () => widget.onDeleteFolder!(widget.path),
            child: Text(l10n.sidebarDeleteAlbumAction),
          ),
      ],
    );
    action?.call();
  }

  void _accept(Object data) {
    if (data is List<String>) {
      widget.onDropPaths?.call(widget.path, data);
    } else if (data is String) {
      widget.onDropFolder?.call(data, widget.path);
    }
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
    // Distinct names on purpose: a builder that referred to the variable
    // it is assigned to would build itself, without end.
    final hasMenu =
        widget.onCreateSubfolder != null || widget.onDeleteFolder != null;
    final inner = Material(
      color: isSelected
          ? DarkmoonColors.accent.withValues(alpha: 0.10)
          : Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelect(widget.path),
        onSecondaryTapUp: hasMenu
            ? (details) => unawaited(_showMenu(context, details.globalPosition))
            : null,
        child: row,
      ),
    );
    Widget live = inner;
    if (widget.onDropPaths != null || widget.onDropFolder != null) {
      live = DragTarget<Object>(
        onWillAcceptWithDetails: (details) => _accepts(details.data),
        onAcceptWithDetails: (details) => _accept(details.data),
        builder: (context, candidates, _) => DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: candidates.isNotEmpty
                  ? DarkmoonColors.accent
                  : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: inner,
        ),
      );
    }
    if (widget.onDropFolder != null && widget.depth > 0) {
      final dropTarget = live;
      live = Draggable<String>(
        data: widget.path,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: DarkmoonColors.surfaceRaised,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: DarkmoonColors.accent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.folder,
                  size: 14,
                  color: DarkmoonColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _name,
                  style: const TextStyle(
                    color: DarkmoonColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: dropTarget),
        child: dropTarget,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _missing ? row : live,
        _AnimatedFolderExpand(
          expanded: _expanded && _children != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final dir in _children ?? const <Directory>[])
                _FolderNode(
                  key: ValueKey(dir.path),
                  path: dir.path,
                  depth: widget.depth + 1,
                  selectedPath: widget.selectedPath,
                  onSelect: widget.onSelect,
                  onDropPaths: widget.onDropPaths,
                  onDropFolder: widget.onDropFolder,
                  refreshToken: widget.refreshToken,
                  onCreateSubfolder: widget.onCreateSubfolder,
                  onDeleteFolder: widget.onDeleteFolder,
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
