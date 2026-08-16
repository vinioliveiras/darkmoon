import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';

/// Left-hand folder tree, Lightroom/Photomator-style: one root per folder
/// added via File > Add Folder (persisted in [AppSettings.libraryFolders]),
/// each with subfolders expanded lazily on demand. Clicking a folder loads
/// it into the main editor via [onSelect]; clicking the chevron only
/// expands/collapses without reloading anything. Each root folder also
/// gets a remove button, since only top-level added folders can be removed
/// — subfolders are just navigation, not separately tracked.
class FolderSidebar extends StatelessWidget {
  const FolderSidebar({
    super.key,
    required this.roots,
    required this.selectedPath,
    required this.onSelect,
    required this.onRemove,
  });

  final List<String> roots;
  final String? selectedPath;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: 220,
      color: DarkmoonColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              l10n.sidebarFoldersSection,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          Expanded(
            child: roots.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      l10n.noFolderOpen,
                      style: const TextStyle(
                        color: DarkmoonColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
        ],
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

  String get _name {
    final parts = widget.path
        .split(Platform.pathSeparator)
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? widget.path : parts.last;
  }

  Future<void> _toggleExpanded() async {
    if (!_expanded && _children == null) {
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
    setState(() => _expanded = !_expanded);
  }

  static Future<List<Directory>> _listSubfolders(String path) async {
    try {
      final entries = await Directory(path).list().toList();
      final dirs = entries.whereType<Directory>().toList()
        ..sort(
          (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
        );
      return dirs;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.path == widget.selectedPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: isSelected
              ? DarkmoonColors.accent.withValues(alpha: 0.22)
              : Colors.transparent,
          child: InkWell(
            onTap: () => widget.onSelect(widget.path),
            child: Padding(
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
                    onTap: _toggleExpanded,
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
                          : Icon(
                              _expanded
                                  ? Icons.keyboard_arrow_down
                                  : Icons.chevron_right,
                              size: 16,
                              color: DarkmoonColors.textMuted,
                            ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.folder,
                    size: 15,
                    color: isSelected
                        ? DarkmoonColors.accent
                        : DarkmoonColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _name,
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
                  if (widget.onRemove != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onRemove!(widget.path),
                      child: Tooltip(
                        message: AppLocalizations.of(
                          context,
                        )!.sidebarRemoveFolderTooltip,
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: DarkmoonColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded && _children != null)
          for (final dir in _children!)
            _FolderNode(
              path: dir.path,
              depth: widget.depth + 1,
              selectedPath: widget.selectedPath,
              onSelect: widget.onSelect,
            ),
      ],
    );
  }
}
