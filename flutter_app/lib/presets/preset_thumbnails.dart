import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../native/edit_source.dart';
import '../render/render.dart';
import '../render/render_params.dart';
import 'preset.dart';

/// Long edge of a preset thumbnail, in pixels.
///
/// Above the 86px the list draws it at, so it is never upscaled, and with
/// enough over for a display running at 150%. Measured render cost at
/// this size is about 14ms, against 5ms at 64 — which would be cheaper
/// and visibly soft, and softness defeats the point of a preview.
const int kPresetThumbnailEdge = 128;

/// One tiny render, shaped for `compute()`.
class PresetThumbnailJob {
  const PresetThumbnailJob({
    required this.width,
    required this.height,
    required this.rgb,
    required this.params,
  });

  final int width;
  final int height;
  final Uint8List rgb;
  final RenderParams params;
}

/// `compute()` entry point.
Uint8List renderPresetThumbnail(PresetThumbnailJob job) =>
    renderRgb(job.width, job.height, job.rgb, job.params);

/// Builds the render params for one preset — supplied by the editor,
/// since they depend on the photo's as-shot white balance and on the
/// colour profile in force, neither of which this store knows about.
typedef PresetThumbnailParams = RenderParams Function(Preset preset);

/// The current photo rendered once per preset, for the preset list.
///
/// Three things make this affordable with a library of eighty presets.
///
/// It renders tiny: a 128px frame costs about 14 milliseconds, against
/// seconds for a real preview. It renders one at a time, on another
/// isolate, so a long queue never becomes a stutter — 14 milliseconds is
/// most of a frame, which is far too much to spend on the UI thread
/// eighty times over. And it renders only what is asked for, which the
/// panel ties to what is on screen.
///
/// The cache is keyed by preset and dropped whole when [signature]
/// changes. That signature is deliberately not just the photo: a
/// thumbnail is of this photo *through the colour profile in force*, so
/// changing the profile has to invalidate them too. What must NOT
/// invalidate them is selecting a different preset — every other
/// thumbnail is still of the same photo, and re-rendering eighty of them
/// on every click is exactly the trap this is written to avoid.
class PresetThumbnailStore extends ChangeNotifier {
  String? _signature;
  Uint8List? _rgb;
  int _width = 0;
  int _height = 0;
  PresetThumbnailParams? _paramsFor;

  final Map<String, ui.Image> _cache = {};
  final List<Preset> _pending = [];
  final Set<String> _queued = {};
  bool _busy = false;
  bool _disposed = false;

  /// True when there is a photo to render thumbnails of.
  bool get hasSource => _rgb != null;

  /// Points the store at a photo. [signature] identifies everything a
  /// thumbnail depends on besides the preset itself; when it changes,
  /// every cached thumbnail is of something else and is dropped.
  ///
  /// Passing a null [source] clears the store — no photo, no thumbnails.
  void setSource({
    required String signature,
    required EditSource? source,
    required PresetThumbnailParams paramsFor,
  }) {
    if (signature == _signature && (source == null) == (_rgb == null)) {
      // Same photo and same profile: keep what has already been rendered,
      // but take the newer builder in case a closure captured stale state.
      _paramsFor = paramsFor;
      return;
    }
    _signature = signature;
    _paramsFor = paramsFor;
    _pending.clear();
    _queued.clear();
    _dropCache();
    if (source == null) {
      _rgb = null;
      _width = 0;
      _height = 0;
    } else {
      final scaled = _downscale(source);
      _rgb = scaled.rgb;
      _width = scaled.width;
      _height = scaled.height;
    }
    // Deferred, because the editor calls this from build: notifying
    // synchronously there would mark a listener dirty during the same
    // build, which Flutter rejects outright.
    scheduleMicrotask(() {
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  /// The thumbnail for [presetId], or null while it has not been rendered.
  ui.Image? thumbnailFor(String presetId) => _cache[presetId];

  /// Asks for [preset]'s thumbnail. Idempotent and cheap: returns at once
  /// if it is cached or already in the queue, so a widget can call it on
  /// every build.
  void request(Preset preset) {
    if (_disposed ||
        _rgb == null ||
        _cache.containsKey(preset.id) ||
        !_queued.add(preset.id)) {
      return;
    }
    _pending.add(preset);
    _pump();
  }

  Future<void> _pump() async {
    if (_busy || _pending.isEmpty || _disposed) {
      return;
    }
    _busy = true;
    final preset = _pending.removeAt(0);
    final signature = _signature;
    final rgb = _rgb;
    final paramsFor = _paramsFor;
    try {
      if (rgb == null || paramsFor == null) {
        return;
      }
      final rendered = await compute(
        renderPresetThumbnail,
        PresetThumbnailJob(
          width: _width,
          height: _height,
          rgb: rgb,
          params: paramsFor(
            preset,
          ).withRenderScaleFor(_width, _height),
        ),
      );
      // The photo can change while an isolate is working. Anything that
      // comes back for a signature that is no longer current is of the
      // wrong photo, and caching it would show the previous image under
      // the new one's presets.
      if (_disposed || signature != _signature) {
        return;
      }
      final image = await _decode(rendered, _width, _height);
      if (_disposed || signature != _signature) {
        image.dispose();
        return;
      }
      _cache.remove(preset.id)?.dispose();
      _cache[preset.id] = image;
      notifyListeners();
    } finally {
      _queued.remove(preset.id);
      _busy = false;
      if (!_disposed && _pending.isNotEmpty) {
        unawaited(_pump());
      }
    }
  }

  void _dropCache() {
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _pending.clear();
    _queued.clear();
    _dropCache();
    super.dispose();
  }
}

/// Box-averaged down to [kPresetThumbnailEdge] on the long side.
///
/// Averaged rather than point-sampled: a thumbnail of a detailed photo
/// point-sampled at a twentieth of its size is mostly aliasing, and the
/// whole job here is to show what a preset does to the colour and tone.
({Uint8List rgb, int width, int height}) _downscale(EditSource source) {
  final longest = source.width > source.height ? source.width : source.height;
  final step = longest <= kPresetThumbnailEdge
      ? 1
      : (longest / kPresetThumbnailEdge).ceil();
  final width = (source.width ~/ step).clamp(1, source.width);
  final height = (source.height ~/ step).clamp(1, source.height);
  final out = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var r = 0;
      var g = 0;
      var b = 0;
      var count = 0;
      for (var sy = 0; sy < step; sy++) {
        final srcY = y * step + sy;
        if (srcY >= source.height) {
          break;
        }
        for (var sx = 0; sx < step; sx++) {
          final srcX = x * step + sx;
          if (srcX >= source.width) {
            break;
          }
          final i = (srcY * source.width + srcX) * 3;
          r += source.rgbBytes[i];
          g += source.rgbBytes[i + 1];
          b += source.rgbBytes[i + 2];
          count++;
        }
      }
      final o = (y * width + x) * 3;
      if (count > 0) {
        out[o] = r ~/ count;
        out[o + 1] = g ~/ count;
        out[o + 2] = b ~/ count;
      }
    }
  }
  return (rgb: out, width: width, height: height);
}

Future<ui.Image> _decode(Uint8List rgb, int width, int height) {
  final rgba = Uint8List(width * height * 4);
  for (var i = 0, o = 0; i < rgb.length; i += 3, o += 4) {
    rgba[o] = rgb[i];
    rgba[o + 1] = rgb[i + 1];
    rgba[o + 2] = rgb[i + 2];
    rgba[o + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
