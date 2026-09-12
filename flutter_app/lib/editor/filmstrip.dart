// The filmstrip along the bottom and its badges.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// imports of its own — the split (2026-09-10) is for navigation, not
// decoupling. Imports live in editor_screen.dart.
part of '../editor_screen.dart';

class _Filmstrip extends StatefulWidget {
  const _Filmstrip({
    required this.files,
    required this.selectedIndex,
    required this.thumbnails,
    required this.onSelect,
    required this.isEdited,
    required this.onResetEdits,
    required this.onShowOnDisk,
    required this.onDelete,
    required this.onCopyEdits,
    required this.onPasteEdits,
    required this.hasCopiedEdits,
    required this.metaOf,
    required this.onSetRating,
    required this.onSetLabel,
  });

  final List<RawFile> files;
  final int? selectedIndex;
  final Map<String, Uint8List> thumbnails;
  final ValueChanged<int> onSelect;

  /// Whether a photo has any saved edit — shows a small badge over its
  /// thumbnail when true.
  final bool Function(String path) isEdited;

  /// Right-click menu actions — each takes the photo it was invoked on,
  /// not necessarily the currently-selected one (right-clicking a
  /// non-selected thumbnail acts on that thumbnail, matching how a file
  /// manager's context menu works).
  final ValueChanged<RawFile> onResetEdits;
  final ValueChanged<RawFile> onShowOnDisk;
  final ValueChanged<RawFile> onDelete;
  final ValueChanged<RawFile> onCopyEdits;
  final ValueChanged<RawFile> onPasteEdits;

  /// Whether there's anything to paste right now — disables "Paste Edits"
  /// in the context menu otherwise, same as the main canvas's own menu.
  final bool hasCopiedEdits;

  /// Rating / colour label / tags of a photo, null when it has none.
  final PhotoMeta? Function(String path) metaOf;
  final void Function(RawFile file, int rating) onSetRating;
  final void Function(RawFile file, String label) onSetLabel;

  @override
  State<_Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<_Filmstrip> {
  final _scrollController = ScrollController();

  /// Key on the currently-selected thumbnail, so [Scrollable.ensureVisible]
  /// can centre it exactly (handling the list padding / viewport math the
  /// rough jump below only approximates).
  final _selectedItemKey = GlobalKey();

  /// Thumbnail slot width (104) plus the 6px right padding between slots —
  /// the stride from one thumbnail's left edge to the next's.
  static const _slotStride = 110.0;
  static const _slotWidth = 104.0;
  static const _listPadding = 8.0;

  @override
  void initState() {
    super.initState();
    _recenterAfterLayout(animated: false);
  }

  @override
  void didUpdateWidget(_Filmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-center when the selection moves, or when a new folder's files
    // arrive (startup restores the last photo, but the strip would
    // otherwise sit at offset 0 with that photo scrolled off-screen).
    final selectionMoved = widget.selectedIndex != oldWidget.selectedIndex;
    final filesChanged = widget.files.length != oldWidget.files.length;
    if ((selectionMoved || filesChanged) && widget.selectedIndex != null) {
      _recenterAfterLayout(animated: selectionMoved && !filesChanged);
    }
  }

  /// The strip and its scroll position aren't laid out yet on the frame a
  /// folder first loads (and on startup the restored folder can take a
  /// while), so retry over the next second or so until the controller has
  /// real content dimensions.
  void _recenterAfterLayout({required bool animated, int attempt = 0}) {
    if (attempt > 40) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_scrollController.hasClients &&
          _scrollController.position.hasContentDimensions) {
        _centerOnSelected(animated: animated);
      } else {
        _recenterAfterLayout(animated: animated, attempt: attempt + 1);
      }
    });
  }

  /// Scrolls so the selected thumbnail sits in the middle of the strip
  /// (clamped at the ends, so the first/last few photos don't leave a gap).
  /// A rough jump gets the target item built, then [Scrollable.ensureVisible]
  /// on its key nudges it to exact centre.
  void _centerOnSelected({required bool animated}) {
    final index = widget.selectedIndex;
    if (index == null || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final slotCenter = _listPadding + index * _slotStride + _slotWidth / 2;
    final rough = (slotCenter - position.viewportDimension / 2).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (animated && (rough - position.pixels).abs() > 1) {
      _scrollController.animateTo(
        rough,
        duration: DarkmoonMotion.of(context, DarkmoonMotion.base),
        curve: DarkmoonMotion.enter,
      );
    } else {
      _scrollController.jumpTo(rough);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final ctx = _selectedItemKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: animated
              ? DarkmoonMotion.of(ctx, DarkmoonMotion.fast)
              : Duration.zero,
          curve: DarkmoonMotion.enter,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Mouse wheels report vertical scroll delta by default, but this list
  // scrolls horizontally — without this, plain wheel scroll over the
  // filmstrip does nothing (Flutter doesn't remap the axis on its own).
  // Ctrl+scroll (Cmd+scroll on macOS) is reserved for image zoom, so this
  // only acts without it.
  void _handleWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        _commandModifierHeld ||
        !_scrollController.hasClients) {
      return;
    }
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    final target = (_scrollController.offset + delta).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
    RawFile file,
  ) async {
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
        PopupMenuItem(
          value: () => widget.onCopyEdits(file),
          child: Text(l10n.imageContextCopyEditsAction),
        ),
        PopupMenuItem(
          value: widget.hasCopiedEdits ? () => widget.onPasteEdits(file) : null,
          enabled: widget.hasCopiedEdits,
          child: Text(l10n.imageContextPasteEditsAction),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          // The row's own stars pop the menu with the pick; a tap beside
          // them falls through to this item and closes it with nothing.
          child: RatingPicker(
            rating: widget.metaOf(file.path)?.rating ?? 0,
            onPick: (rating) => widget.onSetRating(file, rating),
          ),
        ),
        PopupMenuItem(
          child: LabelPicker(
            label: widget.metaOf(file.path)?.label ?? '',
            onPick: (label) => widget.onSetLabel(file, label),
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
        PopupMenuItem(
          value: () => widget.onDelete(file),
          child: Text(l10n.filmstripDeleteAction),
        ),
      ],
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    final selectedIndex = widget.selectedIndex;
    final thumbnails = widget.thumbnails;
    final onSelect = widget.onSelect;
    if (files.isEmpty) {
      return Container(
        height: 114,
        color: DarkmoonColors.canvas,
        alignment: Alignment.center,
        child: Text(
          AppLocalizations.of(context)!.noFolderOpen,
          style: const TextStyle(color: DarkmoonColors.textMuted, fontSize: 11),
        ),
      );
    }
    return Container(
      height: 114,
      color: DarkmoonColors.canvas,
      child: Listener(
        onPointerSignal: _handleWheel,
        // Pressing and moving scrolls the strip, with a mouse as much as
        // a finger; the desktop default only scrolls by wheel and
        // scrollbar. A long press picks the photo up instead (below), so
        // the two never compete and the strip works on a touch screen
        // (user's call, 2026-09-11).
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              // Springs back past either end instead of stopping dead
              // (user's request, 2026-09-12) — the stretch says "this is
              // the end" the way a phone's lists do.
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.all(8),
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final isSelected = index == selectedIndex;
                final thumbnail = thumbnails[file.path];
                final edited = widget.isEdited(file.path);
                final meta = widget.metaOf(file.path);
                return HoverBuilder(
                  builder: (context, hovered, _) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    // Held, then dragged onto the sidebar's folders: the
                    // photo moves there on disk (2026-09-11).
                    child: LongPressDraggable<List<String>>(
                      data: [file.path],
                      delay: const Duration(milliseconds: 300),
                      dragAnchorStrategy: pointerDragAnchorStrategy,
                      feedback: _FilmstripDragFeedback(thumbnail: thumbnail),
                      child: GestureDetector(
                        onTap: () => onSelect(index),
                        onSecondaryTapUp: (details) => _showContextMenu(
                          context,
                          details.globalPosition,
                          file,
                        ),
                        // The selection tint moves from tile to tile and
                        // a hovered tile lifts a little, both at `fast`.
                        child: AnimatedContainer(
                          duration: DarkmoonMotion.of(
                            context,
                            DarkmoonMotion.fast,
                          ),
                          curve: DarkmoonMotion.enter,
                          key: isSelected ? _selectedItemKey : null,
                          width: 104,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? DarkmoonColors.accent.withValues(alpha: 0.28)
                                : hovered
                                ? DarkmoonColors.accent.withValues(alpha: 0.10)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        height: double.infinity,
                                        // A step lighter than the filmstrip's own
                                        // canvas background — using canvas here
                                        // too (tried first) made the thumbnail
                                        // card invisible against the strip.
                                        color:
                                            DarkmoonColors.dropdownBackground,
                                        alignment: Alignment.center,
                                        child: thumbnail == null
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: DarkmoonColors
                                                          .textMuted,
                                                    ),
                                              )
                                            : Image.memory(
                                                thumbnail,
                                                fit: BoxFit.cover,
                                                gaplessPlayback: true,
                                              ),
                                      ),
                                      Positioned(
                                        left: 3,
                                        top: 3,
                                        child: _FileTypeBadge(
                                          label: file.typeLabel,
                                          isRaw: file.isRaw,
                                        ),
                                      ),
                                      if (edited)
                                        const Positioned(
                                          right: 3,
                                          top: 3,
                                          child: _EditedBadge(),
                                        ),
                                      if (meta != null && meta.rating > 0)
                                        Positioned(
                                          left: 3,
                                          bottom: 4,
                                          child: RatingStars(meta.rating),
                                        ),
                                      if (meta != null && meta.label.isNotEmpty)
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            height: 3,
                                            color: photoLabelColor(meta.label),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: DarkmoonColors.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Small file-type pill shown over each filmstrip thumbnail's corner —
/// RAW extensions (RAF/CR2/NEF/...) get the accent color to stand out as
/// the app's primary format, common image formats (JPG/PNG/...) get a
/// neutral gray.
class _FileTypeBadge extends StatelessWidget {
  const _FileTypeBadge({required this.label, required this.isRaw});

  final String label;
  final bool isRaw;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: isRaw
            ? DarkmoonColors.accent.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isRaw ? DarkmoonColors.background : Colors.white,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

/// Small pencil badge shown over a filmstrip thumbnail's corner when
/// [_EditorScreenState._isPhotoEdited] is true for that photo — a filled
/// dot rather than a pill (unlike [_FileTypeBadge]) since it carries no
/// label, just a yes/no signal, matching Meridian's own edited-photo
/// indicator.
class _EditedBadge extends StatelessWidget {
  const _EditedBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: AppLocalizations.of(context)!.filmstripEditedTooltip,
      child: Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          color: DarkmoonColors.accent.withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(
          CupertinoIcons.pencil,
          size: 9,
          color: DarkmoonColors.background,
        ),
      ),
    );
  }
}

/// The filmstrip tile under the pointer while it is dragged to a folder.
class _FilmstripDragFeedback extends StatelessWidget {
  const _FilmstripDragFeedback({required this.thumbnail});

  final Uint8List? thumbnail;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: DarkmoonColors.canvas,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: DarkmoonColors.accent),
            ),
            clipBehavior: Clip.antiAlias,
            child: thumbnail == null
                ? const Icon(
                    CupertinoIcons.photo,
                    color: DarkmoonColors.textMuted,
                  )
                : Image.memory(thumbnail!, fit: BoxFit.cover),
          ),
          // What the drop makes: a folder with a plus, the new-album icon,
          // over the photo being carried (user's request, 2026-09-12).
          const Positioned.fill(
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    CupertinoIcons.folder_badge_plus,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
