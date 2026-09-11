import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog/photo_meta_store.dart';
import '../l10n/app_localizations.dart';
import '../raw_files.dart';
import '../theme.dart';
import '../widgets/photo_meta_widgets.dart';
import '../widgets/text_prompt_dialog.dart';
import 'album_picker_dialog.dart';
import 'photo_mover.dart';

/// The library — the "Albums" tab of the editor screen (2026-09-11): a
/// grid of the open album's photos, filtered by name, rating, colour
/// label and keyword, with selection, ratings, moves and deletes. The
/// left column (the album tree, the recent files) is the editor's own,
/// shared with the Editor tab; this widget is the right-hand side, and
/// everything it shows is the editor's state, handed in.
///
/// Albums are folders (the user's call): "new album" creates a folder
/// inside the open one, dropping photos onto a folder in the tree moves
/// them there on disk, dropping a photo onto another photo makes a new
/// album of them. The editor does the moving and re-keys its catalog;
/// see `photo_mover.dart`.
class LibraryBody extends StatefulWidget {
  const LibraryBody({
    super.key,
    required this.files,
    required this.folder,
    required this.title,
    required this.hasLibrary,
    required this.canGoBack,
    required this.onBack,
    required this.thumbnails,
    required this.thumbnailFor,
    required this.metaOf,
    required this.isEdited,
    required this.libraryFolders,
    required this.onOpen,
    required this.onAddFolder,
    required this.onSetRating,
    required this.onSetLabel,
    required this.onSetTags,
    required this.onMovePhotos,
    required this.onCreateFolder,
    required this.onDelete,
    required this.onShowOnDisk,
    required this.onResetEdits,
  });

  /// The photos of the open album (or the single opened file).
  final List<RawFile> files;

  /// The open album's path — null for a single file or nothing open.
  final String? folder;

  /// What the header shows: the album's name, the file's, or the app's
  /// own word for the library.
  final String title;

  /// Whether the library has any folder at all (else the empty state).
  final bool hasLibrary;

  /// Whether the back arrow has a previous album to return to.
  final bool canGoBack;
  final VoidCallback onBack;

  /// The thumbnails the editor already holds, by path; anything missing
  /// is asked of [thumbnailFor].
  final Map<String, Uint8List> thumbnails;
  final Future<Uint8List?> Function(RawFile file) thumbnailFor;
  final PhotoMeta? Function(String path) metaOf;
  final bool Function(String path) isEdited;
  final List<String> Function() libraryFolders;

  /// Opens the photo in the Editor tab.
  final ValueChanged<RawFile> onOpen;
  final Future<void> Function() onAddFolder;
  final void Function(RawFile file, int rating) onSetRating;
  final void Function(RawFile file, String label) onSetLabel;
  final void Function(RawFile file, List<String> tags) onSetTags;

  /// Moves photos into a folder on disk and follows them in the catalog;
  /// the editor reloads the open album afterwards, so [files] changes.
  final Future<MoveOutcome> Function(List<String> paths, String folder)
  onMovePhotos;

  /// Creates a folder inside another; its path, or null when refused.
  final Future<String?> Function(String parent, String name) onCreateFolder;

  /// Sends photos to the Recycle Bin (after the editor's confirmation);
  /// how many went.
  final Future<int> Function(List<RawFile> files) onDelete;
  final void Function(RawFile file) onShowOnDisk;
  final void Function(RawFile file) onResetEdits;

  /// How many thumbnails decode at once for tiles that have none cached.
  static const int thumbnailConcurrency = 3;

  @override
  State<LibraryBody> createState() => _LibraryBodyState();
}

class _LibraryBodyState extends State<LibraryBody> {
  final Map<String, Uint8List?> _fallbackThumbnails = {};
  final Set<String> _thumbnailsLoading = {};
  final List<RawFile> _thumbnailQueue = [];
  int _thumbnailsInFlight = 0;
  final _query = TextEditingController();
  int _minRating = 0;
  String _labelFilter = '';

  /// Selected photos, and the one the last plain click or shift-range
  /// started from. Every action — keys, menu, drag — applies to the
  /// whole selection when the photo it was invoked on is part of it.
  final Set<String> _selection = {};
  String? _anchorPath;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant LibraryBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.files, widget.files)) {
      // The album was reloaded (a move, a delete, another album): keep
      // only what is still here.
      final present = {for (final f in widget.files) f.path};
      _selection.retainWhere(present.contains);
      if (_anchorPath != null && !present.contains(_anchorPath)) {
        _anchorPath = null;
      }
      if (oldWidget.folder != widget.folder) {
        _selection.clear();
        _anchorPath = null;
      }
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Uint8List? _thumbnailOf(RawFile file) =>
      widget.thumbnails[file.path] ?? _fallbackThumbnails[file.path];

  bool _thumbnailKnown(RawFile file) =>
      widget.thumbnails.containsKey(file.path) ||
      _fallbackThumbnails.containsKey(file.path);

  void _requestThumbnail(RawFile file) {
    if (_thumbnailKnown(file) || _thumbnailsLoading.contains(file.path)) {
      return;
    }
    _thumbnailsLoading.add(file.path);
    _thumbnailQueue.add(file);
    _pumpThumbnails();
  }

  void _pumpThumbnails() {
    while (_thumbnailsInFlight < LibraryBody.thumbnailConcurrency &&
        _thumbnailQueue.isNotEmpty) {
      // Newest request first: the tiles on screen now, not the ones the
      // user scrolled past.
      final file = _thumbnailQueue.removeLast();
      _thumbnailsInFlight++;
      unawaited(
        widget
            .thumbnailFor(file)
            .then<Uint8List?>((bytes) => bytes, onError: (_) => null)
            .then((bytes) {
              _thumbnailsInFlight--;
              _thumbnailsLoading.remove(file.path);
              if (mounted) {
                setState(() => _fallbackThumbnails[file.path] = bytes);
                _pumpThumbnails();
              }
            }),
      );
    }
  }

  List<RawFile> get _visibleFiles {
    final query = _query.text.trim().toLowerCase();
    return [
      for (final file in widget.files)
        if ((query.isEmpty || _matchesQuery(file, query)) &&
            _passesMetaFilters(file))
          file,
    ];
  }

  /// File name or any keyword.
  bool _matchesQuery(RawFile file, String query) {
    if (file.name.toLowerCase().contains(query)) {
      return true;
    }
    final tags = widget.metaOf(file.path)?.tags ?? const [];
    return tags.any((tag) => tag.toLowerCase().contains(query));
  }

  bool _passesMetaFilters(RawFile file) {
    if (_minRating == 0 && _labelFilter.isEmpty) {
      return true;
    }
    final meta = widget.metaOf(file.path) ?? const PhotoMeta();
    return meta.rating >= _minRating &&
        (_labelFilter.isEmpty || meta.label == _labelFilter);
  }

  /// The selection in the grid's order.
  List<RawFile> get _selectedFiles => [
    for (final file in widget.files)
      if (_selection.contains(file.path)) file,
  ];

  /// The photo Enter opens: the anchor when it is selected, else the
  /// first selected.
  RawFile? get _primarySelected {
    final selected = _selectedFiles;
    if (selected.isEmpty) {
      return null;
    }
    for (final file in selected) {
      if (file.path == _anchorPath) {
        return file;
      }
    }
    return selected.first;
  }

  /// What an action invoked on [file] applies to: the whole selection
  /// when [file] is in it, else [file] alone.
  List<RawFile> _targets(RawFile file) =>
      _selection.contains(file.path) ? _selectedFiles : [file];

  /// A click on [file]: plain selects it alone, Ctrl (Cmd) toggles it,
  /// Shift extends from the anchor across the visible order.
  void _clickSelect(RawFile file) {
    _focusNode.requestFocus();
    final keys = HardwareKeyboard.instance;
    final toggle = keys.isControlPressed || keys.isMetaPressed;
    final range = keys.isShiftPressed;
    setState(() {
      if (toggle) {
        if (!_selection.remove(file.path)) {
          _selection.add(file.path);
          _anchorPath = file.path;
        }
      } else if (range && _anchorPath != null) {
        final visible = _visibleFiles;
        final a = visible.indexWhere((f) => f.path == _anchorPath);
        final b = visible.indexWhere((f) => f.path == file.path);
        if (a < 0 || b < 0) {
          _selection
            ..clear()
            ..add(file.path);
          _anchorPath = file.path;
        } else {
          final lo = a < b ? a : b;
          final hi = a < b ? b : a;
          _selection.clear();
          for (var i = lo; i <= hi; i++) {
            _selection.add(visible[i].path);
          }
        }
      } else {
        _selection
          ..clear()
          ..add(file.path);
        _anchorPath = file.path;
      }
    });
  }

  void _selectAllVisible() {
    setState(() {
      _selection
        ..clear()
        ..addAll(_visibleFiles.map((f) => f.path));
    });
  }

  // ---- moving (albums are folders)

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _movePhotos(List<String> paths, String folder) async {
    final l10n = AppLocalizations.of(context)!;
    final outcome = await widget.onMovePhotos(paths, folder);
    if (!mounted) {
      return;
    }
    if (outcome.skipped.isNotEmpty) {
      _toast(l10n.libraryMoveSkipped(outcome.skipped.length));
    }
    setState(() => _selection.removeAll(outcome.moved.keys));
  }

  /// "New album": an empty folder inside the open one.
  Future<void> _createAlbum() => _newAlbumWith(const []);

  /// A new album (folder inside the open one) holding [paths] — from a
  /// photo dropped on another, the menu's "new album with these", or
  /// the toolbar button with nothing.
  Future<void> _newAlbumWith(List<String> paths) async {
    final l10n = AppLocalizations.of(context)!;
    final parent = widget.folder;
    if (parent == null) {
      return;
    }
    final name = await showTextPromptDialog(
      context,
      title: l10n.libraryNewAlbumTitle,
    );
    if (name == null || name.trim().isEmpty || !mounted) {
      return;
    }
    final created = await widget.onCreateFolder(parent, name);
    if (!mounted) {
      return;
    }
    if (created == null) {
      _toast(l10n.libraryFolderExists);
      return;
    }
    if (paths.isNotEmpty) {
      await _movePhotos(paths, created);
    }
  }

  /// "Move to album…": the library's own folder tree, then the move.
  Future<void> _moveToPickedAlbum(List<RawFile> targets) async {
    final album = await showAlbumPickerDialog(
      context,
      roots: widget.libraryFolders(),
      current: widget.folder,
    );
    if (album == null || !mounted) {
      return;
    }
    await _movePhotos([for (final f in targets) f.path], album);
  }

  Future<void> _showContextMenu(Offset globalPosition, RawFile file) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    if (!_selection.contains(file.path)) {
      setState(() {
        _selection
          ..clear()
          ..add(file.path);
        _anchorPath = file.path;
      });
    }
    final targets = _targets(file);
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: () => widget.onOpen(file),
          child: Text(l10n.libraryOpenInEditor),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: RatingPicker(
            rating: widget.metaOf(file.path)?.rating ?? 0,
            onPick: (rating) => _setRating(targets, rating),
          ),
        ),
        PopupMenuItem(
          child: LabelPicker(
            label: widget.metaOf(file.path)?.label ?? '',
            onPick: (label) => _setLabel(targets, label),
          ),
        ),
        PopupMenuItem(
          value: () => unawaited(_editTags(file, targets)),
          child: Text(l10n.libraryEditTagsAction),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => unawaited(_moveToPickedAlbum(targets)),
          child: Text(l10n.libraryMoveToAction),
        ),
        if (widget.folder != null)
          PopupMenuItem(
            value: () =>
                unawaited(_newAlbumWith([for (final f in targets) f.path])),
            child: Text(l10n.libraryNewAlbumFromSelection),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () {
            for (final f in targets) {
              widget.onResetEdits(f);
            }
          },
          child: Text(l10n.filmstripResetEditsAction),
        ),
        PopupMenuItem(
          value: () => widget.onShowOnDisk(file),
          child: Text(l10n.filmstripShowOnDiskAction),
        ),
        PopupMenuItem(
          value: () => unawaited(_delete(targets)),
          child: Text(l10n.filmstripDeleteAction),
        ),
      ],
    );
    action?.call();
  }

  Future<void> _delete(List<RawFile> targets) async {
    final deleted = await widget.onDelete(targets);
    if (mounted && deleted > 0) {
      setState(_selection.clear);
    }
  }

  /// Keywords for [targets], edited as one comma-separated line seeded
  /// from [file]'s.
  Future<void> _editTags(RawFile file, List<RawFile> targets) async {
    final l10n = AppLocalizations.of(context)!;
    final current = widget.metaOf(file.path)?.tags ?? const [];
    final text = await showTextPromptDialog(
      context,
      title: l10n.libraryEditTagsTitle,
      initialValue: current.join(', '),
    );
    if (text == null || !mounted) {
      return;
    }
    final seen = <String>{};
    final tags = [
      for (final part in text.split(','))
        if (part.trim().isNotEmpty && seen.add(part.trim())) part.trim(),
    ];
    for (final f in targets) {
      widget.onSetTags(f, tags);
    }
    setState(() {});
  }

  void _setRating(List<RawFile> files, int rating) {
    for (final file in files) {
      widget.onSetRating(file, rating);
    }
    setState(() {});
  }

  void _setLabel(List<RawFile> files, String label) {
    for (final file in files) {
      widget.onSetLabel(file, label);
    }
    setState(() {});
  }

  void _rateSelected(int rating) {
    final selected = _selectedFiles;
    if (selected.isNotEmpty) {
      _setRating(selected, rating);
    }
  }

  /// The label pressed again clears — judged on the primary photo.
  void _labelSelected(String label) {
    final selected = _selectedFiles;
    if (selected.isEmpty) {
      return;
    }
    final current = widget.metaOf(_primarySelected!.path)?.label ?? '';
    _setLabel(selected, current == label ? '' : label);
  }

  static const _digitKeys = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_primarySelected case final file?) {
            widget.onOpen(file);
          }
        },
        const SingleActivator(LogicalKeyboardKey.delete): () {
          final selected = _selectedFiles;
          if (selected.isNotEmpty) {
            unawaited(_delete(selected));
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _selectAllVisible,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            _selectAllVisible,
        for (var stars = 0; stars <= 5; stars++)
          SingleActivator(_digitKeys[stars]): () => _rateSelected(stars),
        for (var i = 0; i < 4; i++)
          SingleActivator(_digitKeys[6 + i]): () =>
              _labelSelected(photoLabelNames[i]),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Container(
          color: DarkmoonColors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildToolbar(l10n),
              Expanded(child: _buildGrid(l10n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(AppLocalizations l10n) {
    final visible = _visibleFiles;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
      decoration: const BoxDecoration(
        color: DarkmoonColors.panel,
        border: Border(bottom: BorderSide(color: DarkmoonColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Tooltip(
                message: l10n.libraryBackFolderTooltip,
                child: IconButton(
                  icon: const Icon(CupertinoIcons.chevron_left, size: 18),
                  color: DarkmoonColors.textSecondary,
                  onPressed: widget.canGoBack ? widget.onBack : null,
                ),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DarkmoonColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _selection.length > 1
                    ? l10n.librarySelectedCount(
                        _selection.length,
                        visible.length,
                      )
                    : l10n.libraryPhotoCount(visible.length),
                style: const TextStyle(
                  color: DarkmoonColors.textMuted,
                  fontSize: 12,
                ),
              ),
              if (widget.folder != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: l10n.libraryNewAlbumTooltip,
                  child: IconButton(
                    icon: const Icon(
                      CupertinoIcons.folder_badge_plus,
                      size: 18,
                    ),
                    color: DarkmoonColors.textSecondary,
                    onPressed: () => unawaited(_createAlbum()),
                  ),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                for (var stars = 1; stars <= 5; stars++)
                  Tooltip(
                    message: l10n.libraryMinRatingTooltip(stars),
                    child: InkWell(
                      onTap: () => setState(
                        () => _minRating = _minRating == stars ? 0 : stars,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          stars <= _minRating
                              ? CupertinoIcons.star_fill
                              : CupertinoIcons.star,
                          size: 15,
                          color: stars <= _minRating
                              ? DarkmoonColors.accent
                              : DarkmoonColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                for (final name in ['', ...photoLabelNames])
                  Tooltip(
                    message: name.isEmpty
                        ? l10n.libraryAllLabelsTooltip
                        : photoLabelName(l10n, name),
                    child: InkWell(
                      onTap: () => setState(() => _labelFilter = name),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: LabelDot(
                          name: name,
                          selected: name == _labelFilter,
                          size: 12,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 100,
                    maxWidth: 240,
                  ),
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _query,
                      style: const TextStyle(
                        color: DarkmoonColors.textPrimary,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        hintText: l10n.librarySearchHint,
                        hintStyle: const TextStyle(
                          color: DarkmoonColors.textMuted,
                          fontSize: 12,
                        ),
                        prefixIcon: const Icon(
                          CupertinoIcons.search,
                          size: 14,
                          color: DarkmoonColors.textMuted,
                        ),
                        filled: true,
                        fillColor: DarkmoonColors.canvas,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(AppLocalizations l10n) {
    if (!widget.hasLibrary && widget.files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.libraryEmptyFolders,
              style: const TextStyle(color: DarkmoonColors.textMuted),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => unawaited(widget.onAddFolder()),
              child: Text(l10n.libraryAddFolder),
            ),
          ],
        ),
      );
    }
    final visible = _visibleFiles;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          widget.files.isEmpty ? l10n.libraryEmpty : l10n.libraryNoMatches,
          style: const TextStyle(color: DarkmoonColors.textMuted),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.84,
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final file = visible[index];
        if (!_thumbnailKnown(file)) {
          _requestThumbnail(file);
        }
        final thumbnail = _thumbnailOf(file);
        final tile = _LibraryTile(
          file: file,
          thumbnail: thumbnail,
          loading: !_thumbnailKnown(file),
          meta: widget.metaOf(file.path),
          edited: widget.isEdited(file.path),
          selected: _selection.contains(file.path),
          onTap: () => _clickSelect(file),
          onDoubleTap: () => widget.onOpen(file),
          onSecondaryTapUp: (details) =>
              unawaited(_showContextMenu(details.globalPosition, file)),
        );
        // Dragging a tile carries the whole selection when the tile is
        // part of it — onto a folder on the left, which moves the files,
        // or onto another photo, which makes a new album of them all.
        return Draggable<List<String>>(
          data: [for (final f in _targets(file)) f.path],
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _DragFeedback(
            count: _targets(file).length,
            thumbnail: thumbnail,
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: tile),
          child: DragTarget<List<String>>(
            onWillAcceptWithDetails: (details) =>
                widget.folder != null && !details.data.contains(file.path),
            onAcceptWithDetails: (details) =>
                unawaited(_newAlbumWith([...details.data, file.path])),
            builder: (context, candidates, _) => Stack(
              fit: StackFit.passthrough,
              children: [
                tile,
                if (candidates.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: DarkmoonColors.accent,
                            width: 2,
                          ),
                          color: DarkmoonColors.accent.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.file,
    required this.thumbnail,
    required this.loading,
    required this.meta,
    required this.edited,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTapUp,
  });

  final RawFile file;
  final Uint8List? thumbnail;

  /// Still decoding; a null [thumbnail] once this is false is a decode
  /// that failed.
  final bool loading;
  final PhotoMeta? meta;
  final bool edited;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final GestureTapUpCallback onSecondaryTapUp;

  @override
  Widget build(BuildContext context) {
    final label = meta?.label ?? '';
    final rating = meta?.rating ?? 0;
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapUp: onSecondaryTapUp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: DarkmoonColors.canvas,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? DarkmoonColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumbnail == null && loading)
                    const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DarkmoonColors.textMuted,
                        ),
                      ),
                    )
                  else if (thumbnail == null)
                    const Center(
                      child: Icon(
                        CupertinoIcons.photo,
                        size: 22,
                        color: DarkmoonColors.textMuted,
                      ),
                    )
                  else
                    Image.memory(
                      thumbnail!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        file.typeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (edited)
                    const Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(
                        CupertinoIcons.pencil_circle_fill,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  if (rating > 0)
                    Positioned(
                      left: 5,
                      bottom: 6,
                      child: RatingStars(rating, size: 10),
                    ),
                  if (label.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 3,
                        color: photoLabelColor(label),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: DarkmoonColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// What travels under the pointer while dragging: the thumbnail with the
/// number of photos carried.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.count, required this.thumbnail});

  final int count;
  final Uint8List? thumbnail;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: DarkmoonColors.canvas,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: DarkmoonColors.accent, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: thumbnail == null
                ? const Icon(
                    CupertinoIcons.photo,
                    color: DarkmoonColors.textMuted,
                  )
                : Image.memory(thumbnail!, fit: BoxFit.cover),
          ),
          if (count > 1)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: DarkmoonColors.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: DarkmoonColors.background,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
