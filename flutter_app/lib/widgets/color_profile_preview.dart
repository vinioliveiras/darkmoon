import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../render/color_profile.dart';
import '../theme.dart';

/// Shows [source] with [profile] applied, live.
///
/// Runs `applyColorProfile` — the pipeline's own CPU implementation, not a
/// re-derivation of it — so what this shows is what the renderer does. The
/// buffer is small enough that the cost is irrelevant next to being
/// certain the preview and the photo agree.
///
/// Only the profile is applied, deliberately: no exposure, no curves, none
/// of the photo's own edits. The question this answers is "what does this
/// profile do", and mixing in the rest would make it unanswerable.
class ColorProfilePreview extends StatefulWidget {
  const ColorProfilePreview({
    super.key,
    required this.source,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.profile,
  });

  /// Packed RGB, 0..255 valued, three floats per pixel — the pipeline's
  /// own working format.
  final Float32List source;
  final int sourceWidth;
  final int sourceHeight;
  final ColorProfile profile;

  @override
  State<ColorProfilePreview> createState() => _ColorProfilePreviewState();
}

class _ColorProfilePreviewState extends State<ColorProfilePreview> {
  ui.Image? _image;

  /// A rebuild is in flight; another was asked for while it ran.
  bool _building = false;
  bool _restartWanted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_rebuild());
  }

  @override
  void didUpdateWidget(ColorProfilePreview old) {
    super.didUpdateWidget(old);
    if (!identical(old.profile, widget.profile) ||
        !identical(old.source, widget.source)) {
      unawaited(_rebuild());
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _rebuild() async {
    // Coalesce rather than queue. Dragging a slider asks for a rebuild on
    // every frame; running them all would fall further behind the pointer
    // with each one, and every result but the last is already stale.
    if (_building) {
      _restartWanted = true;
      return;
    }
    _building = true;
    try {
      do {
        _restartWanted = false;
        final image = await _render(widget.source, widget.profile);
        if (!mounted) {
          image.dispose();
          return;
        }
        // The old image is replaced and disposed here and nowhere else —
        // this widget owns every image it creates.
        final previous = _image;
        setState(() => _image = image);
        previous?.dispose();
      } while (_restartWanted);
    } finally {
      _building = false;
    }
  }

  Future<ui.Image> _render(Float32List source, ColorProfile profile) async {
    final working = Float32List.fromList(source);
    applyColorProfile(working, profile, 1.0);

    final rgba = Uint8List(widget.sourceWidth * widget.sourceHeight * 4);
    for (var p = 0, i = 0; i < working.length; p += 4, i += 3) {
      rgba[p] = working[i].clamp(0.0, 255.0).round();
      rgba[p + 1] = working[i + 1].clamp(0.0, 255.0).round();
      rgba[p + 2] = working[i + 2].clamp(0.0, 255.0).round();
      rgba[p + 3] = 255;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      widget.sourceWidth,
      widget.sourceHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return AspectRatio(
      aspectRatio: widget.sourceWidth / widget.sourceHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ColoredBox(
          color: DarkmoonColors.canvas,
          child: image == null
              ? const SizedBox.expand()
              // A clone, not the image itself: RenderImage takes ownership
              // of whatever it is handed and disposes it when replaced
              // (rendering/image.dart's `image` setter), so passing the
              // original would have it disposed underneath this widget and
              // then disposed again here — a double free.
              //
              // Cloning on every build is safe and does not leak: that
              // same setter checks isCloneOf and disposes a redundant
              // clone straight away.
              : RawImage(image: image.clone(), fit: BoxFit.cover),
        ),
      ),
    );
  }
}
