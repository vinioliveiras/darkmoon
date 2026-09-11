import 'dart:async';

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
/// the right, filtered by name, rating and colour label; a double-click
/// (or Enter) opens the photo in the editor. Pushed over the editor as a
/// route and pops with a [LibraryOpenRequest].
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
  String? _selectedPath;
  final _focusNode = FocusNode();

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
      _selectedPath = null;
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
      _selectedPath = path;
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
        if ((query.isEmpty || file.name.toLowerCase().contains(query)) &&
            _passesMetaFilters(file))
          file,
    ];
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

  RawFile? get _selectedFile {
    final path = _selectedPath;
    if (path == null) {
      return null;
    }
    for (final file in _files) {
      if (file.path == path) {
        return file;
      }
    }
    return null;
  }

  Future<void> _showContextMenu(Offset globalPosition, RawFile file) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    setState(() => _selectedPath = file.path);
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
            ).pop<VoidCallback>(() => _setRating(file, rating)),
          ),
        ),
        PopupMenuItem(
          child: LabelPicker(
            label: widget.metaOf(file.path)?.label ?? '',
            onPick: (label) => Navigator.of(
              context,
            ).pop<VoidCallback>(() => _setLabel(file, label)),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => widget.onResetEdits(file),
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

  void _setRating(RawFile file, int rating) {
    widget.onSetRating(file, rating);
    setState(() {});
  }

  void _setLabel(RawFile file, String label) {
    widget.onSetLabel(file, label);
    setState(() {});
  }

  void _rateSelected(int rating) {
    if (_selectedFile case final file?) {
      _setRating(file, rating);
    }
  }

  void _labelSelected(String label) {
    if (_selectedFile case final file?) {
      final current = widget.metaOf(file.path)?.label ?? '';
      _setLabel(file, current == label ? '' : label);
    }
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
          if (_selectedFile case final file?) {
            _open(file);
          }
        },
        for (var stars = 0; stars <= 5; stars++)
          SingleActivator(_digitKeys[stars]): () => _rateSelected(stars),
        for (var i = 0; i < 4; i++)
          SingleActivator(_digitKeys[6 + i]): () =>
              _labelSelected(photoLabelNames[i]),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Material(
          color: DarkmoonColors.background,
          child: Row(
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
                l10n.libraryPhotoCount(visible.length),
                style: const TextStyle(
                  color: DarkmoonColors.textMuted,
                  fontSize: 12,
                ),
              ),
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
        return _LibraryTile(
          file: file,
          thumbnail: _thumbnails[file.path],
          loading: !_thumbnails.containsKey(file.path),
          meta: widget.metaOf(file.path),
          edited: widget.isEdited(file.path),
          selected: file.path == _selectedPath,
          onTap: () {
            _focusNode.requestFocus();
            setState(() => _selectedPath = file.path);
          },
          onDoubleTap: () => _open(file),
          onSecondaryTapUp: (details) =>
              unawaited(_showContextMenu(details.globalPosition, file)),
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
