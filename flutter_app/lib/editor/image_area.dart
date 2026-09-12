// The image area: the preview itself, the fading transition between
// renders, and the loading overlay.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// imports of its own — the split (2026-09-10) is for navigation, not
// decoupling. Imports live in editor_screen.dart.
part of '../editor_screen.dart';

class _ImageArea extends StatelessWidget {
  const _ImageArea({
    required this.selected,
    required this.fileMissing,
    required this.thumbnail,
    required this.thumbnailIsSmall,
    required this.thumbnailDecodeWidth,
    required this.preview,
    required this.neutralPreview,
    required this.beforeAfterMode,
    required this.viewController,
    required this.viewportKey,
    required this.zoomScale,
    required this.onPointerSignal,
    required this.onResetZoom,
    required this.onDoubleTapZoom,
    required this.editingMask,
    required this.editingSource,
    required this.onMaskGeometryChanged,
    required this.onMaskGeometryChangeEnd,
    required this.brushRadius,
    required this.brushHardness,
    required this.brushErase,
    required this.brushFlow,
    required this.onSampleColor,
    required this.onSampleLuminance,
    required this.wbEyedropperActive,
    required this.onSampleWhiteBalance,
    required this.maskOverlayVisible,
    required this.maskOverlayOpacity,
    required this.aiMaskMaps,
    required this.cropOverlayActive,
    required this.cropTransform,
    required this.cropAspectRatio,
    required this.onCropTransformChanged,
    required this.onCropTransformChangeEnd,
    required this.straighteningActive,
    required this.guidedModeActive,
    required this.onSecondaryTapUp,
    required this.previewFadeGeneration,
  });

  final RawFile? selected;

  /// True when [selected]'s decode failed because the file itself is gone
  /// (moved/renamed/deleted outside darkmoon, or its drive unmounted) —
  /// takes priority over the "decoding..." fallback so the canvas doesn't
  /// spin forever on a decode that will never finish.
  final bool fileMissing;

  final Uint8List? thumbnail;

  /// True when [thumbnail] is the 200px filmstrip entry rather than the
  /// camera's own embedded preview — see [PreviewFrame.isSmallStandIn],
  /// which is the only thing this feeds.
  final bool thumbnailIsSmall;

  /// Caps how wide [thumbnail] is decoded — set only when it is the
  /// camera's embedded preview, which is several thousand pixels wide.
  final int? thumbnailDecodeWidth;

  /// The current render for [selected], already uploaded as a `ui.Image`
  /// (see [PreviewFrame]) — null while it is still being produced, in
  /// which case [thumbnail] stands in.
  final ui.Image? preview;
  final ui.Image? neutralPreview;
  final bool beforeAfterMode;
  final TransformationController viewController;
  final GlobalKey viewportKey;

  /// Current pan/zoom factor, so the mask overlays can counter-scale their
  /// handles/outlines and stay a fixed screen size no matter the zoom.
  final double zoomScale;

  final void Function(PointerSignalEvent) onPointerSignal;

  /// "Fit" toolbar button — resets pan+zoom *and* the parent's
  /// `_zoomScale` (so the % readout and the +/- buttons stay in sync,
  /// which a bare `viewController.value = identity` doesn't do).
  final VoidCallback onResetZoom;

  /// Double-click on the image — zooms in centered on the click point if
  /// not already zoomed in, or back out to Fit if it is (the parent
  /// decides which, since that depends on its own `_zoomScale`).
  final ValueChanged<Offset> onDoubleTapZoom;

  /// The mask currently being edited (Linear/Radial Gradient), if any —
  /// draws its draggable handles over the image. Null outside of
  /// Before/After mode having a real mask (not the "Image" layer)
  /// selected.
  final MaskLayer? editingMask;

  /// The currently-decoded edit source backing [preview] — only its
  /// width/height are used, to work out where `BoxFit.contain` placed the
  /// image so the mask handles line up with it.
  final EditSource? editingSource;
  final ValueChanged<MaskLayer> onMaskGeometryChanged;
  final ValueChanged<MaskLayer> onMaskGeometryChangeEnd;

  /// Current brush tool settings, used when [editingMask] is a Brush or
  /// Flow mask.
  final double brushRadius;
  final double brushHardness;
  final bool brushErase;

  /// Per-pass deposit rate baked into new strokes — only meaningful when
  /// [editingMask] is a Flow mask (see [BrushStroke.flow]'s doc).
  final double brushFlow;

  /// Fires with normalized image coordinates when the user taps the image
  /// while a Color Range mask is active.
  final void Function(double nx, double ny) onSampleColor;

  /// Fires with normalized image coordinates when the user taps the image
  /// while a Luminance mask is active — mirrors [onSampleColor].
  final void Function(double nx, double ny) onSampleLuminance;

  /// Whether the White Balance eyedropper is armed — shows a tap target
  /// over the whole image regardless of the active layer.
  final bool wbEyedropperActive;
  final void Function(double nx, double ny) onSampleWhiteBalance;

  /// Whether the active mask's shaded overlay/handles are drawn — a
  /// user-toggleable UI preference, same for every mask type.
  final bool maskOverlayVisible;

  /// How opaque that overlay's shading is (0..1), independently per mask
  /// type — see [_EditorScreenState._maskOverlayOpacity].
  final Map<MaskType, double> maskOverlayOpacity;

  /// Resolved model output per mask id, for the AI mask types' overlay —
  /// see `_EditorScreenState._aiMaskMaps`.
  final Map<String, AiMaskMap> aiMaskMaps;

  /// Whether the Crop Overlay's draggable rectangle is shown — mutually
  /// exclusive with mask editing (the caller only sets one at a time).
  final bool cropOverlayActive;
  final CropTransformParams cropTransform;
  final double? cropAspectRatio;
  final ValueChanged<CropTransformParams> onCropTransformChanged;
  final ValueChanged<CropTransformParams> onCropTransformChangeEnd;

  /// True while the Straighten slider is being dragged — [CropOverlay]
  /// shows a denser guide grid while this is set (item 28).
  final bool straighteningActive;

  /// See [CropOverlay.guidedModeActive].
  final bool guidedModeActive;

  /// Right-click on the image — opens the copy/paste-edits context menu.
  final void Function(Offset globalPosition) onSecondaryTapUp;

  /// See [_EditorScreenState._previewFadeGeneration]'s doc — changes
  /// only on a settled edit/preset/reset/undo/redo for the *same* photo,
  /// telling [_fadingImage] when to actually play the fade.
  final int previewFadeGeneration;

  /// Vertical breathing room around the fitted image — without this, a
  /// photo whose aspect ratio closely matches the viewport (most photos,
  /// since BoxFit.contain already maximizes it) sits flush against the
  /// top/bottom toolbar edges with zero margin, reading as cramped even
  /// though "Fit" is working exactly as designed.
  static const double _verticalBreathingRoom = 60;

  /// The main preview `Image`, wrapped so a settled render fades in
  /// (see [previewFadeGeneration]) instead of popping — a live drag
  /// frame doesn't bump the generation, so it updates in place with no
  /// animation, same as before this existed. Instant (no transition at
  /// all) when Settings > animations is off. A [Builder] rather than
  /// threading a `BuildContext` down from `build()` through several
  /// intermediate methods (`_zoomableImage`/`_fittedImage`/…) — any
  /// descendant context works for [AnimationsConfig.of].
  ///
  /// A [PreviewFrame] whose `isPlaceholder` is set is standing in for
  /// [preview] while it's still rendering — the camera's own embedded
  /// image where the RAW carries one, the 200px filmstrip thumbnail
  /// otherwise.
  Widget _fadingImage(PreviewFrame frame) {
    return Builder(
      builder: (context) => FadingPreviewImage(
        frame: frame,
        fadeGeneration: previewFadeGeneration,
        duration: DarkmoonMotion.of(context, DarkmoonMotion.slow),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          key: viewportKey,
          color: DarkmoonColors.canvas,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: _verticalBreathingRoom),
          child: _buildContent(l10n),
        ),
        // A sibling of the padded Container above, not a descendant of its
        // child — [_buildContent]'s own coordinate space starts *after*
        // that padding is applied, so a title positioned there at
        // `top: 14` would actually land 14px into the fitted image itself
        // (getting in the way of editing) rather than in the blank
        // breathing room genuinely reserved above it. Anchored here
        // instead, `top: 14` is 14px into that reserved margin, which the
        // image can never intrude into regardless of zoom/pan/aspect
        // ratio (the Container's padding — not this widget's zoom level —
        // is what carves out that space).
        _titleOverlay(),
      ],
    );
  }

  /// The photo's filename (minus extension) and its format badge, floating
  /// in the breathing room [_verticalBreathingRoom] leaves above the fitted
  /// image — always readable, and never over the photo itself, regardless
  /// of zoom/pan or Before/After mode.
  Widget _titleOverlay() {
    final file = selected;
    if (file == null) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 14,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    p.basenameWithoutExtension(file.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 6),
                _FileTypeBadge(label: file.typeLabel, isRaw: file.isRaw),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    if (selected == null) {
      return Text(
        l10n.emptyStateOpenFolder,
        textAlign: TextAlign.center,
        style: const TextStyle(color: DarkmoonColors.textMuted),
      );
    }
    if (fileMissing) {
      // Takes priority over any stale cached preview still sitting in
      // [preview]/[thumbnail] from before the file went away — showing an
      // outdated image here would be more misleading than showing nothing.
      return Text(
        l10n.photoNotFoundMessage(selected!.name),
        textAlign: TextAlign.center,
        style: const TextStyle(color: DarkmoonColors.textMuted),
      );
    }
    // Prefer the full RAW decode; fall back to the fast embedded thumbnail
    // while it's still decoding, so something appears immediately (the
    // blurry-to-sharp jump this produces is now a fade, not a pop — see
    // _fadingImage/FadingPreviewImage).
    final rendered = preview;
    final placeholder = thumbnail;
    final PreviewFrame frame;
    if (rendered != null) {
      frame = PreviewFrame.rendered(rendered);
    } else if (placeholder != null) {
      frame = PreviewFrame.placeholder(
        placeholder,
        decodeWidth: thumbnailDecodeWidth,
        isSmallStandIn: thumbnailIsSmall,
      );
    } else {
      return Text(
        l10n.decodingPhoto(selected!.name),
        textAlign: TextAlign.center,
        style: const TextStyle(color: DarkmoonColors.textMuted),
      );
    }
    if (beforeAfterMode) {
      // Both sides share the same viewController, so Ctrl+scroll/pan stays
      // in sync between them instead of only working in the single-image
      // view.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Falls back to the edited image until the neutral render finishes.
          Expanded(
            child: _zoomableLabeledImage(
              l10n.beforeLabel,
              neutralPreview == null
                  ? frame
                  : PreviewFrame.rendered(neutralPreview!),
            ),
          ),
          Container(width: 1, color: DarkmoonColors.divider),
          Expanded(child: _zoomableLabeledImage(l10n.afterLabel, frame)),
        ],
      );
    }
    return _zoomableImage(frame);
  }

  Widget _zoomableImage(PreviewFrame frame) {
    // Double-click zooms in (Meridian/Photoshop-style, centered on the
    // click point) if not already zoomed in, or back out to Fit if it is
    // — but not while a mode with its own tap handling is active (mask
    // editing, crop overlay, eyedropper), where the tap-delay double-tap
    // introduces would make those laggy.
    final doubleTapZoomEnabled =
        editingMask == null && !cropOverlayActive && !wbEyedropperActive;
    // onDoubleTapDown fires (with the tap's position) just before
    // onDoubleTap itself, which carries no position of its own — capturing
    // it here and reading it back a moment later is the standard Flutter
    // pattern for a positioned double-tap gesture.
    Offset doubleTapPosition = Offset.zero;
    return Listener(
      onPointerSignal: onPointerSignal,
      child: GestureDetector(
        onDoubleTapDown: doubleTapZoomEnabled
            ? (details) => doubleTapPosition = details.localPosition
            : null,
        onDoubleTap: doubleTapZoomEnabled
            ? () => onDoubleTapZoom(doubleTapPosition)
            : null,
        onSecondaryTapUp: (details) => onSecondaryTapUp(details.globalPosition),
        child: InteractiveViewer(
          transformationController: viewController,
          minScale: _minZoom,
          maxScale: _maxZoom,
          // InteractiveViewer has its own built-in pinch/trackpad scale
          // gesture handling that's entirely separate from the Listener
          // above — without this it zoomed on trackpad pinch/two-finger
          // scroll regardless of Ctrl, since that gesture never goes
          // through onPointerSignal at all. Panning (drag) stays enabled.
          scaleEnabled: false,
          child: _fittedImage(frame),
        ),
      ),
    );
  }

  Widget _zoomableLabeledImage(String label, PreviewFrame frame) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _zoomableImage(frame),
        Positioned(
          left: 8,
          top: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // SizedBox.expand forces the image into the full available box regardless
  // of the source resolution (the "live" low-res render during a slider
  // drag is a different pixel size than the full-res one), so BoxFit.contain
  // always fits against the same fixed box — without this, the displayed
  // image visibly shrank and grew back as the source resolution changed.
  Widget _fittedImage(PreviewFrame frame) {
    final mask = editingMask;
    final source = editingSource;
    if (wbEyedropperActive && source != null) {
      return SizedBox.expand(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                _fadingImage(frame),
                WhiteBalanceEyedropperOverlay(
                  containerSize: Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  ),
                  imageWidth: source.width,
                  imageHeight: source.height,
                  onSample: onSampleWhiteBalance,
                ),
              ],
            );
          },
        ),
      );
    }
    if (cropOverlayActive && source != null) {
      // Displayed frame is straightened/keystoned but not yet cropped
      // (see _EditorScreenState._renderPreview) — its dimensions match
      // the source's, swapped for an odd quarter-turn count, since
      // straighten/keystone/scale don't change the canvas span.
      final rotated = cropTransform.rotateQuarterTurns.isOdd;
      final frameWidth = rotated ? source.height : source.width;
      final frameHeight = rotated ? source.width : source.height;
      // A margin around the whole thing while cropping, photo and overlay
      // together, so a full-frame crop's corners never sit on a clip
      // boundary in the first place.
      //
      // Clip.none on the Stack below was not enough on its own: something
      // further up still clipped, and chasing it would have meant relaxing
      // a clip that exists for another reason. Insetting the pair costs a
      // few pixels of preview size only while the crop tool is open, and
      // nothing can cut a handle that is not near an edge. It is also what
      // other editors do — the photo steps back when you start cropping.
      return Padding(
        padding: const EdgeInsets.all(_cropHandleMargin),
        child: SizedBox.expand(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final containerSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return Stack(
                fit: StackFit.expand,
                // Belt and braces with the margin above: the handles are
                // drawn centred on the crop corners, so anything that clips
                // to the overlay's own bounds takes half of each dot.
                // That clip is what the handles were nudged inward to avoid;
                // letting them paint past it is the fix that keeps them
                // where the corners actually are.
                clipBehavior: Clip.none,
                children: [
                  _fadingImage(frame),
                  CropOverlay(
                    containerSize: containerSize,
                    imageWidth: frameWidth,
                    imageHeight: frameHeight,
                    params: cropTransform,
                    lockedAspectRatio: cropAspectRatio,
                    onChanged: onCropTransformChanged,
                    onChangeEnd: onCropTransformChangeEnd,
                    straighteningActive: straighteningActive,
                    guidedModeActive: guidedModeActive,
                  ),
                ],
              );
            },
          ),
        ),
      );
    }
    // Whole Image has no geometry of its own (it's a full-coverage no-op
    // mask) — nothing to draw a handle/overlay for, so it takes the same
    // no-overlay path as the "Image" base layer.
    final noOverlay =
        mask == null || source == null || mask.type == MaskType.wholeImage;
    return SizedBox.expand(
      child: noOverlay
          ? _fadingImage(frame)
          : LayoutBuilder(
              builder: (context, constraints) {
                final containerSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _previewFrameWidget(frame, fit: BoxFit.contain),
                    if (mask.type == MaskType.brush ||
                        mask.type == MaskType.flow)
                      BrushMaskOverlay(
                        containerSize: containerSize,
                        imageWidth: source.width,
                        imageHeight: source.height,
                        zoomScale: zoomScale,
                        mask: mask,
                        brushRadius: brushRadius,
                        brushHardness: brushHardness,
                        brushErase: brushErase,
                        brushFlow: brushFlow,
                        onChanged: onMaskGeometryChanged,
                        onChangeEnd: onMaskGeometryChangeEnd,
                        showOverlay: maskOverlayVisible,
                        overlayOpacity: maskOverlayOpacity[mask.type]!,
                      )
                    else if (mask.type == MaskType.colorRange ||
                        mask.type == MaskType.luminance)
                      ColorRangeOverlay(
                        containerSize: containerSize,
                        imageWidth: source.width,
                        imageHeight: source.height,
                        onSample: mask.type == MaskType.luminance
                            ? onSampleLuminance
                            : onSampleColor,
                        mask: mask,
                        previewImage: frame.image,
                        showOverlay: maskOverlayVisible,
                        overlayOpacity: maskOverlayOpacity[mask.type]!,
                      )
                    else if (aiMaskTypes.contains(mask.type))
                      AiMaskOverlay(
                        containerSize: containerSize,
                        imageWidth: source.width,
                        imageHeight: source.height,
                        mask: mask,
                        map: aiMaskMaps[mask.id],
                        onChanged: onMaskGeometryChanged,
                        onChangeEnd: onMaskGeometryChangeEnd,
                        showOverlay: maskOverlayVisible,
                        overlayOpacity: maskOverlayOpacity[mask.type]!,
                      )
                    else
                      GradientMaskOverlay(
                        containerSize: containerSize,
                        imageWidth: source.width,
                        imageHeight: source.height,
                        zoomScale: zoomScale,
                        mask: mask,
                        onChanged: onMaskGeometryChanged,
                        onChangeEnd: onMaskGeometryChangeEnd,
                        showOverlay: maskOverlayVisible,
                        overlayOpacity: maskOverlayOpacity[mask.type]!,
                      ),
                  ],
                );
              },
            ),
    );
  }
}

/// Shows [bytes], fading it in whenever [fadeGeneration] changes (a
/// settled edit/preset/reset/undo/redo — see `_ImageArea.previewFadeGeneration`'s
/// doc) rather than the [AnimatedSwitcher] this replaced, which
/// crossfaded the old and new image simultaneously — with both
/// partially transparent at once, the dark canvas behind them showed
/// through for a moment, reading as a "blink". Here the previous frame
/// stays fully opaque as a base layer the whole time; only the new
/// frame fades in on top of it, so the canvas is never exposed.
/// Cross-fades the canvas from one [PreviewFrame] to the next.
///
/// Public only so test/widgets/fading_preview_image_test.dart can mount it
/// directly — the frame-ownership contract it implements (see
/// [_FadingPreviewImageState._currentFrame]) is subtle enough that it
/// needs a regression test that actually drives the widget.
class FadingPreviewImage extends StatefulWidget {
  const FadingPreviewImage({
    super.key,
    required this.frame,
    required this.fadeGeneration,
    required this.duration,
  });

  /// The frame to paint — see [PreviewFrame], whose `isPlaceholder` says
  /// whether this is the real render or the thumbnail standing in for it.
  final PreviewFrame frame;
  final int fadeGeneration;
  final Duration duration;

  @override
  State<FadingPreviewImage> createState() => _FadingPreviewImageState();
}

class _FadingPreviewImageState extends State<FadingPreviewImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// This widget's own handle on the frame it is painting — taken with
  /// [PreviewFrame.cloneHandle] the moment `widget.frame` arrives, never
  /// later.
  ///
  /// The editor's preview map disposes a frame synchronously the instant
  /// its replacement lands (inside `setState`, before this widget is even
  /// rebuilt), so by the time `didUpdateWidget` runs, the frame it is
  /// handed as `old.frame` is already dead. Cloning it *there* — which is
  /// what this did until 2026-09-03 — throws `StateError`, which Flutter
  /// turns into an `ErrorWidget`: a plain grey rectangle over the whole
  /// canvas, on every settled edit, in release builds. Holding the handle
  /// from the start means the outgoing frame below is one this widget
  /// already owns and is guaranteed still alive.
  late PreviewFrame _currentFrame;

  /// The outgoing frame, kept as a fully-opaque base layer only while
  /// [_controller] is actively fading the new one in on top of it —
  /// released once the fade completes (or immediately, for an instant/
  /// live-drag update) so a stale frame doesn't linger in the tree, and
  /// its handle doesn't keep a full-size image alive for no reason.
  PreviewFrame? _previousFrame;

  bool get _shouldAnimate => widget.duration > Duration.zero;

  @override
  void initState() {
    super.initState();
    _currentFrame = widget.frame.cloneHandle();
    // The very first frame shown for a freshly-opened photo fades in
    // from nothing too (see _EditorScreenState._buildContent, which
    // shows a "decoding…" placeholder — not a previous image — until
    // this widget first mounts).
    _controller = AnimationController(
      vsync: this,
      value: _shouldAnimate ? 0.0 : 1.0,
      duration: widget.duration,
    );
    // Without this, _previousFrame stayed set forever after the very
    // first fade — invisible while the new (sharp, opaque) layer fully
    // covers it, but exposed as a lingering blurred halo wherever
    // BoxFit.contain letterboxes the new layer without fully covering
    // the old one's own footprint underneath.
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && _previousFrame != null) {
        setState(() {
          _previousFrame!.disposeHandle();
          _previousFrame = null;
        });
      }
    });
    if (_shouldAnimate) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(FadingPreviewImage old) {
    super.didUpdateWidget(old);
    final frameChanged = !identical(widget.frame, old.frame);
    if (widget.fadeGeneration != old.fadeGeneration && _shouldAnimate) {
      setState(() {
        // The handle this widget already held becomes the outgoing layer —
        // still alive even though the editor's map has disposed the image
        // behind it. Never cloned from old.frame here; see _currentFrame.
        _previousFrame?.disposeHandle();
        _previousFrame = _currentFrame;
        _currentFrame = widget.frame.cloneHandle();
      });
      _controller
        ..duration = widget.duration
        ..forward(from: 0);
    } else {
      // A live drag frame, or animations are off — swap instantly.
      if (frameChanged || _previousFrame != null) {
        setState(() {
          _previousFrame?.disposeHandle();
          _previousFrame = null;
          if (frameChanged) {
            _currentFrame.disposeHandle();
            _currentFrame = widget.frame.cloneHandle();
          }
        });
      }
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _previousFrame?.disposeHandle();
    _currentFrame.disposeHandle();
    _controller.dispose();
    super.dispose();
  }

  /// Blurred only while the frame is the *small* stand-in — see
  /// [PreviewFrame.isSmallStandIn].
  ///
  /// Blurring the 200px filmstrip thumbnail is honest: it is magnified
  /// several times to fill the viewport and is going to look wrong
  /// anyway, so the blur says "not the real thing yet" rather than
  /// letting it read as a soft render. Blurring the camera's own embedded
  /// image is not: that one is wider than the viewport, and showing it
  /// unaltered is the entire point.
  Widget _layer(PreviewFrame frame) {
    if (!frame.isPlaceholder || !frame.isSmallStandIn) {
      return _previewFrameWidget(frame, fit: BoxFit.contain);
    }
    // Blur the image at its own intrinsic size (letting it lay out
    // unconstrained inside FittedBox) instead of stretched to the full
    // box, then let FittedBox scale the already-blurred result down to
    // fit — this keeps the photo's true aspect ratio (BoxFit.cover here
    // would distort/crop it when the box's aspect doesn't match, e.g. a
    // portrait photo in a wide viewport) while still keeping the blur
    // kernel confined to the photo's own pixels, with no transparent
    // margin around it for the blur to bleed into.
    return FittedBox(
      fit: BoxFit.contain,
      // ImageFiltered has no clip of its own — the blur paints past the
      // image's own bounds (that's how a blur naturally grows past its
      // source), so without this ClipRect the blurred rect visibly
      // overshoots the real image size, not just its (now-crisp) edges.
      child: ClipRect(
        child: ImageFiltered(
          // TileMode.clamp (not .decal) so the blur samples the edge
          // pixels' own color past the boundary instead of transparent —
          // .decal fades the whole border toward see-through, reading as
          // a soft vignette instead of a crisp-edged rectangle.
          //
          // Applied at the stand-in's own native size and then scaled by
          // the FittedBox above, so 4 reads like 40 on a 200px thumbnail
          // filling the viewport. That is exactly the case this now runs
          // in, and the only one.
          imageFilter: ImageFilter.blur(
            sigmaX: 4,
            sigmaY: 4,
            tileMode: TileMode.clamp,
          ),
          child: _previewFrameWidget(frame),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previous = _previousFrame;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (previous != null) _layer(previous),
        FadeTransition(opacity: _controller, child: _layer(_currentFrame)),
      ],
    );
  }
}

/// What the loading overlay shows: a message, an optional real progress
/// fraction (null means indeterminate — no measurable sub-steps yet).
class _LoadingInfo {
  const _LoadingInfo({
    required this.message,
    this.progress,
    this.isStatus = false,
  });

  final String message;
  final double? progress;

  /// True for a brief, non-cancellable confirmation (e.g. "Done!" after an
  /// export) rather than an actual in-progress operation — hides the
  /// Cancel button and the progress bar, neither of which mean anything
  /// once the operation they'd apply to has already finished.
  final bool isStatus;
}

/// A dark scrim with a centered card, shown over the whole editor area
/// (below the menu bar) during long operations like opening a folder —
/// real progress when [info.progress] is known, an indeterminate bar
/// otherwise, plus a way to cancel out of whatever's running.
class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({
    required this.info,
    required this.onCancel,
    required this.onHide,
  });

  final _LoadingInfo info;
  final VoidCallback onCancel;

  /// Dismisses the overlay while letting the operation keep running in
  /// the background.
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = info.progress;
    // Not Positioned.fill any more: the editor wraps this in a fade and
    // supplies the Positioned itself (see _overlayInfo's call site).
    return SizedBox.expand(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          decoration: BoxDecoration(
            color: DarkmoonColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DarkmoonColors.border),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 24, spreadRadius: 2),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                info.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DarkmoonColors.textPrimary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: progress == null
                      ? const LinearProgressIndicator(
                          backgroundColor: DarkmoonColors.border,
                          valueColor: AlwaysStoppedAnimation(
                            DarkmoonColors.accent,
                          ),
                        )
                      : LinearProgressIndicator(
                          value: progress,
                          backgroundColor: DarkmoonColors.border,
                          valueColor: const AlwaysStoppedAnimation(
                            DarkmoonColors.accent,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: onCancel,
                      child: Text(l10n.cancelButton),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: onHide,
                      child: Text(l10n.hideButton),
                    ),
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

/// The compact loading status line every operation now shows (folder
/// open, AI denoise, slow render, export) — plain white text + bar with no
/// card or scrim, sitting in the preview's bottom breathing room so it
/// reads as chrome rather than a modal. The message and bar are centred on
/// the preview; the Cancel button is pinned to the right edge without
/// stealing width from the bar, so the status doesn't look off-centre.
class _HiddenLoadingIndicator extends StatelessWidget {
  const _HiddenLoadingIndicator({required this.info, required this.onCancel});

  final _LoadingInfo info;
  final VoidCallback onCancel;

  /// Fixed width so the bar length (and the centring) is stable regardless
  /// of message length — matches [_LoadingOverlay]'s card width.
  static const double _width = 300;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = info.progress;
    return SizedBox(
      width: _width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Balances the Cancel button on the right so the message
              // stays visually centred over the bar.
              const SizedBox(width: 24),
              Expanded(
                child: Text(
                  info.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5),
                ),
              ),
              SizedBox(
                width: 24,
                height: 20,
                // A status message (e.g. "Done!") has nothing left running
                // to cancel — leave the space blank instead of a
                // meaningless button.
                child: info.isStatus
                    ? null
                    : IconButton(
                        onPressed: onCancel,
                        tooltip: l10n.cancelButton,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 20,
                        ),
                        // Override the app-wide IconButtonTheme's filled
                        // rounded-square + border — this bar is meant to
                        // read as bare chrome (see this class's doc
                        // comment), not another boxed toolbar button.
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side: BorderSide.none,
                          shape: const CircleBorder(),
                        ),
                        iconSize: 15,
                        color: Colors.white,
                        icon: const Icon(CupertinoIcons.xmark),
                      ),
              ),
            ],
          ),
          // A status message doesn't have real progress to show — the bar
          // below is either genuine percent-complete or an indeterminate
          // "something's happening" spinner, neither of which applies once
          // the operation it described is already done.
          if (!info.isStatus) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                child: progress == null
                    ? const LinearProgressIndicator(
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      )
                    : LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Side length of the toolbar's square icon-only buttons (Fit to window,
/// Undo/Reset/Redo, Crop, AI Denoise, Before/After) — the toolbar's most
/// frequently-tapped controls, sized up from the default pill height (40)
/// and made exactly 1:1 rather than the usual wider-than-tall rectangle.
const double _squareButtonSize = 38;
const double _squareButtonIconSize = 16;
