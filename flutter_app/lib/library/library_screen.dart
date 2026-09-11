import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../catalog/photo_meta_store.dart';
import '../l10n/app_localizations.dart';
import '../raw_files.dart';
import '../theme.dart';
import '../widgets/folder_sidebar.dart';
import '../widgets/photo_meta_widgets.dart';
import '../widgets/text_prompt_dialog.dart';
import 'photo_mover.dart';

/// What the library hands back to the editor when a photo is chosen: the
/// folder to load (null for a single file opened from the recent list)
/// and the photo to select in it.
class LibraryOpenRequest {
  const LibraryOpenRequest({required this.folder, required this.path});

  final String? folder;
  final String path;
}

/// The Home screen (2026-09-11, the user's Solstice-style library): the
/// library's folders on the left, a grid of the chosen folder's photos on
/// the right, filtered by name, rating, colour label and keyword; a
/// double-click (or Enter) opens the photo in the editor. Pushed over the
/// editor as a route and pops with a [LibraryOpenRequest].
///
/// Albums are folders (the user's call): "new album" creates a folder
/// inside the one shown, dragging photos onto a folder in the tree moves
/// them there on disk, dragging a folder onto another moves the folder.
/// The editor does the moving and re-keys its catalog; see
/// `photo_mover.dart`.
///
/// Everything it shows belongs to the editor — the folder list and the
/// filters are settings, the thumbnails come from the editor's cache, the
/// ratings from its store — so it takes getters and callbacks rather than
/// copies: a folder added or a filter toggled here is the editor's own
/// state, re-read after the callback returns.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.libraryFolders,
    required this.recentFiles,
    required this.rawOnly,
    required this.includeSubfolders,
    required this.initialFolder,
    required this.thumbnailFor,
    required this.metaOf,
    required this.isEdited,
    required this.onSetRating,
    required this.onSetLabel,
    required this.onRawOnlyChanged,
    required this.onIncludeSubfoldersChanged,
    required this.onAddFolder,
    required this.onRemoveFolder,
    required this.onOpenFile,
    required this.onRemoveRecentFile,
    required this.onShowOnDisk,
    required this.onResetEdits,
    required this.onSetTags,
    required this.onMovePhotos,
    required this.onMoveFolder,
    required this.onCreateFolder,
  });

  final List<String> Function() libraryFolders;
  final List<String> Function() recentFiles;
  final bool Function() rawOnly;
  final bool Function() includeSubfolders;

  /// The folder to show first — the editor's current one, if any.
  final String? initialFolder;

  /// A photo's filmstrip-sized JPEG thumbnail, from the editor's caches or
  /// decoded on demand; null when it cannot be produced.
  final Future<Uint8List?> Function(RawFile file) thumbnailFor;
  final PhotoMeta? Function(String path) metaOf;
  final bool Function(String path) isEdited;
  final void Function(RawFile file, int rating) onSetRating;
  final void Function(RawFile file, String label) onSetLabel;
  final ValueChanged<bool> onRawOnlyChanged;
  final ValueChanged<bool> onIncludeSubfoldersChanged;
  final Future<void> Function() onAddFolder;
  final ValueChanged<String> onRemoveFolder;
  final Future<void> Function() onOpenFile;
  final ValueChanged<String> onRemoveRecentFile;
  final void Function(RawFile file) onShowOnDisk;
  final void Function(RawFile file) onResetEdits;
  final void Function(RawFile file, List<String> tags) onSetTags;

  /// Moves photos into a folder on disk and follows them in the catalog.
  final Future<MoveOutcome> Function(List<String> paths, String folder)
  onMovePhotos;

  /// Moves a folder into another; the new path, or null when refused.
  final Future<String?> Function(String folder, String targetParent)
  onMoveFolder;

  /// Creates a folder inside another; its path, or null when refused.
  final Future<String?> Function(String parent, String name) onCreateFolder;

  /// How many thumbnails decode at once for tiles that have none cached.
  static const int thumbnailConcurrency = 3;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String? _folder;
  String? _recentFile;
  List<RawFile> _files = const [];
  bool _listing = false;
  int _generation = 0;
  final Map<String, Uint8List?> _thumbnails = {};
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

  /// Bumped after a folder is created or moved, so the tree re-lists.
  int _treeToken = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    final folders = widget.libraryFolders();
    final initial = widget.initialFolder;
    final start = initial != null && folders.contains(initial)
        ? initial
        : (initial ?? (folders.isEmpty ? null : folders.first));
    if (start != null) {
      unawaited(_showFolder(start));
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _showFolder(String folder) async {
    final generation = ++_generation;
    setState(() {
      _folder = folder;
      _recentFile = null;
      _listing = true;
      _selection.clear();
      _anchorPath = null;
    });
    final files = await listRawFiles(
      folder,
      rawOnly: widget.rawOnly(),
      includeSubfolders: widget.includeSubfolders(),
    );
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _files = files;
      _listing = false;
    });
  }

  void _showRecentFile(String path) {
    _generation++;
    setState(() {
      _folder = null;
      _recentFile = path;
      _listing = false;
      _files = [RawFile(path, DateTime.now())];
      _selection
        ..clear()
        ..add(path);
      _anchorPath = path;
    });
  }

  /// Re-lists after a setting the sidebar changed (RAW only, subfolders).
  Future<void> _refresh() async {
    if (_folder case final folder?) {
      await _showFolder(folder);
    } else {
      setState(() {});
    }
  }

  void _requestThumbnail(RawFile file) {
    if (_thumbnails.containsKey(file.path) ||
        _thumbnailsLoading.contains(file.path)) {
      return;
    }
    _thumbnailsLoading.add(file.path);
    _thumbnailQueue.add(file);
    _pumpThumbnails();
  }

  void _pumpThumbnails() {
    while (_thumbnailsInFlight < LibraryScreen.thumbnailConcurrency &&
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
                setState(() => _thumbnails[file.path] = bytes);
                _pumpThumbnails();
              }
            }),
      );
    }
  }

  List<RawFile> get _visibleFiles {
    final query = _query.text.trim().toLowerCase();
    return [
      for (final file in _files)
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

  void _open(RawFile file) {
    Navigator.of(
      context,
    ).pop(LibraryOpenRequest(folder: _folder, path: file.path));
  }

  /// The selection in the grid's order.
  List<RawFile> get _selectedFiles => [
    for (final file in _files)
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

  /// Moves [paths] into [folder] and re-lists what is shown.
  Future<void> _movePhotos(List<String> paths, String folder) async {
    final l10n = AppLocalizations.of(context)!;
    final outcome = await widget.onMovePhotos(paths, folder);
    if (!mounted) {
      return;
    }
    if (outcome.skipped.isNotEmpty) {
      _toast(l10n.libraryMoveSkipped(outcome.skipped.length));
    }
    _selection.removeAll(outcome.moved.keys);
    _treeToken++;
    await _refresh();
  }

  Future<void> _moveFolder(String folder, String targetParent) async {
    final l10n = AppLocalizations.of(context)!;
    final moved = await widget.onMoveFolder(folder, targetParent);
    if (!mounted) {
      return;
    }
    if (moved == null) {
      _toast(l10n.libraryFolderExists);
      return;
    }
    if (_folder != null) {
      _folder = rekeyUnderFolder(_folder!, folder, moved);
    }
    _treeToken++;
    await _refresh();
  }

  /// "New album": a folder inside the one shown.
  Future<void> _createAlbum() async {
    final l10n = AppLocalizations.of(context)!;
    final parent = _folder;
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
    setState(() => _treeToken++);
  }

  /// "Move to folder…": a folder picker, then the move.
  Future<void> _moveToPickedFolder(List<RawFile> targets) async {
    final l10n = AppLocalizations.of(context)!;
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.libraryMoveToAction,
    );
    if (folder == null || !mounted) {
      return;
    }
    await _movePhotos([for (final f in targets) f.path], folder);
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
          value: () => _open(file),
          child: Text(l10n.libraryOpenInEditor),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: RatingPicker(
            rating: widget.metaOf(file.path)?.rating ?? 0,
            onPick: (rating) => Navigator.of(
              context,
            ).pop<VoidCallback>(() => _setRating(targets, rating)),
          ),
        ),
        PopupMenuItem(
          child: LabelPicker(
            label: widget.metaOf(file.path)?.label ?? '',
            onPick: (label) => Navigator.of(
              context,
            ).pop<VoidCallback>(() => _setLabel(targets, label)),
          ),
        ),
        PopupMenuItem(
          value: () => unawaited(_editTags(file, targets)),
          child: Text(l10n.libraryEditTagsAction),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => unawaited(_moveToPickedFolder(targets)),
          child: Text(l10n.libraryMoveToAction),
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
      ],
    );
    action?.call();
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
    final folders = widget.libraryFolders();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_primarySelected case final file?) {
            _open(file);
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
        child: Scaffold(
          backgroundColor: DarkmoonColors.background,
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 260,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LibraryHeader(l10n: l10n),
                    Expanded(
                      child: FolderSidebar(
                        roots: folders,
                        recentFiles: widget.rawOnly()
                            ? widget.recentFiles().where(isRawFile).toList()
                            : widget.recentFiles(),
                        selectedPath: _folder,
                        selectedRecentFile: _recentFile,
                        onSelect: (path) => unawaited(_showFolder(path)),
                        onRemove: (path) {
                          widget.onRemoveFolder(path);
                          if (_folder == path) {
                            _generation++;
                            _folder = null;
                            _files = const [];
                          }
                          setState(() {});
                        },
                        onSelectRecentFile: _showRecentFile,
                        onRemoveRecentFile: (path) {
                          widget.onRemoveRecentFile(path);
                          if (_recentFile == path) {
                            _recentFile = null;
                            _files = const [];
                          }
                          setState(() {});
                        },
                        rawOnly: widget.rawOnly(),
                        onRawOnlyChanged: (value) {
                          widget.onRawOnlyChanged(value);
                          unawaited(_refresh());
                        },
                        includeSubfolders: widget.includeSubfolders(),
                        onIncludeSubfoldersChanged: (value) {
                          widget.onIncludeSubfoldersChanged(value);
                          unawaited(_refresh());
                        },
                        onOpenFile: () => unawaited(
                          widget.onOpenFile().then((_) {
                            if (mounted) {
                              setState(() {});
                            }
                          }),
                        ),
                        onOpenFolder: () => unawaited(
                          widget.onAddFolder().then((_) {
                            if (!mounted) {
                              return;
                            }
                            final added = widget.libraryFolders();
                            final newest = added.isEmpty ? null : added.last;
                            if (newest != null && newest != _folder) {
                              unawaited(_showFolder(newest));
                            } else {
                              setState(() {});
                            }
                          }),
                        ),
                        onDropPaths: (folder, paths) =>
                            unawaited(_movePhotos(paths, folder)),
                        onDropFolder: (folder, target) =>
                            unawaited(_moveFolder(folder, target)),
                        refreshToken: _treeToken,
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: DarkmoonColors.divider,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildToolbar(l10n),
                    Expanded(child: _buildGrid(l10n, folders)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(AppLocalizations l10n) {
    final visible = _visibleFiles;
    final title = _recentFile != null
        ? p.basename(_recentFile!)
        : _folder == null
        ? l10n.menuLibrary
        : p.basename(_folder!);
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
                message: l10n.libraryBackTooltip,
                child: IconButton(
                  icon: const Icon(CupertinoIcons.chevron_left, size: 18),
                  color: DarkmoonColors.textSecondary,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(
                child: Text(
                  title,
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
              if (_folder != null) ...[
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

  Widget _buildGrid(AppLocalizations l10n, List<String> folders) {
    if (folders.isEmpty && _recentFile == null) {
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
    if (_listing) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: DarkmoonColors.textMuted,
          ),
        ),
      );
    }
    final visible = _visibleFiles;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          _files.isEmpty ? l10n.libraryEmpty : l10n.libraryNoMatches,
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
        if (!_thumbnails.containsKey(file.path)) {
          _requestThumbnail(file);
        }
        final tile = _LibraryTile(
          file: file,
          thumbnail: _thumbnails[file.path],
          loading: !_thumbnails.containsKey(file.path),
          meta: widget.metaOf(file.path),
          edited: widget.isEdited(file.path),
          selected: _selection.contains(file.path),
          onTap: () => _clickSelect(file),
          onDoubleTap: () => _open(file),
          onSecondaryTapUp: (details) =>
              unawaited(_showContextMenu(details.globalPosition, file)),
        );
        // Dragging a tile carries the whole selection when the tile is
        // part of it — onto a folder on the left, which moves the files.
        return Draggable<List<String>>(
          data: [for (final f in _targets(file)) f.path],
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _DragFeedback(
            count: _targets(file).length,
            thumbnail: _thumbnails[file.path],
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: tile),
          child: tile,
        );
      },
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: DarkmoonColors.panel,
        border: Border(bottom: BorderSide(color: DarkmoonColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.house_fill,
            size: 15,
            color: DarkmoonColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            l10n.menuLibrary,
            style: const TextStyle(
              color: DarkmoonColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
