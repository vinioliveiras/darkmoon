import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/animated_dialog.dart';
import '../widgets/dialog_chrome.dart';

/// "Move to album": the library's own folders and their subfolders as a
/// tree, in the app's own dialog rather than the system's folder picker
/// (2026-09-11, user's request). Returns the chosen folder, or null.
Future<String?> showAlbumPickerDialog(
  BuildContext context, {
  required List<String> roots,
  String? current,
}) {
  return showAnimatedDialog<String>(
    context: context,
    builder: (context) => _AlbumPickerDialog(roots: roots, current: current),
  );
}

class _AlbumPickerDialog extends StatefulWidget {
  const _AlbumPickerDialog({required this.roots, required this.current});

  final List<String> roots;
  final String? current;

  @override
  State<_AlbumPickerDialog> createState() => _AlbumPickerDialogState();
}

class _AlbumPickerDialogState extends State<_AlbumPickerDialog> {
  String? _chosen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chosen = _chosen;
    final canMove = chosen != null && chosen != widget.current;
    return AlertDialog(
      backgroundColor: DarkmoonColors.dialogBackground,
      shape: dialogShape,
      title: Text(l10n.libraryPickAlbumTitle),
      content: SizedBox(
        width: 440,
        height: 360,
        child: widget.roots.isEmpty
            ? Center(
                child: Text(
                  l10n.libraryEmptyFolders,
                  style: const TextStyle(color: DarkmoonColors.textMuted),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final root in widget.roots)
                      _PickerNode(
                        key: ValueKey(root),
                        path: root,
                        depth: 0,
                        chosen: chosen,
                        onChoose: (path) => setState(() => _chosen = path),
                        onConfirm: (path) => Navigator.of(context).pop(path),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        TextButton(
          onPressed: canMove ? () => Navigator.of(context).pop(chosen) : null,
          child: Text(l10n.libraryPickAlbumConfirm),
        ),
      ],
    );
  }
}

/// One folder row, expandable to its subfolders (listed on first expand).
class _PickerNode extends StatefulWidget {
  const _PickerNode({
    super.key,
    required this.path,
    required this.depth,
    required this.chosen,
    required this.onChoose,
    required this.onConfirm,
  });

  final String path;
  final int depth;
  final String? chosen;
  final ValueChanged<String> onChoose;
  final ValueChanged<String> onConfirm;

  @override
  State<_PickerNode> createState() => _PickerNodeState();
}

class _PickerNodeState extends State<_PickerNode> {
  bool _expanded = false;
  List<String>? _children;

  @override
  void initState() {
    super.initState();
    if (widget.depth == 0) {
      _expanded = true;
      unawaited(_list());
    }
  }

  Future<void> _list() async {
    List<String> dirs;
    try {
      final entries = await Directory(widget.path).list().toList();
      dirs = [for (final e in entries.whereType<Directory>()) e.path]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } catch (_) {
      dirs = const [];
    }
    if (mounted) {
      setState(() => _children = dirs);
    }
  }

  Future<void> _toggle() async {
    if (!_expanded && _children == null) {
      await _list();
    }
    if (mounted) {
      setState(() => _expanded = !_expanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.path == widget.chosen;
    final name = p.basename(widget.path).isEmpty
        ? widget.path
        : p.basename(widget.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: selected
              ? DarkmoonColors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          child: InkWell(
            onTap: () => widget.onChoose(widget.path),
            onDoubleTap: () => widget.onConfirm(widget.path),
            child: Padding(
              padding: EdgeInsets.only(
                left: 6.0 + widget.depth * 16,
                right: 6,
                top: 5,
                bottom: 5,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => unawaited(_toggle()),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: Icon(
                        _expanded
                            ? CupertinoIcons.chevron_down
                            : CupertinoIcons.chevron_right,
                        size: 12,
                        color: DarkmoonColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    CupertinoIcons.folder,
                    size: 14,
                    color: selected
                        ? DarkmoonColors.accent
                        : DarkmoonColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? DarkmoonColors.textPrimary
                            : DarkmoonColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          for (final child in _children ?? const <String>[])
            _PickerNode(
              key: ValueKey(child),
              path: child,
              depth: widget.depth + 1,
              chosen: widget.chosen,
              onChoose: widget.onChoose,
              onConfirm: widget.onConfirm,
            ),
      ],
    );
  }
}
