import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_profile.dart';
import '../render_params.dart';

/// The two points in `renderImageGpu`'s chain whose output is kept across
/// renders, in chain order.
///
/// - [afterAiDenoise]: Exposure/WB → baseline chroma smoothing → AI
///   denoise are done. Everything from Sharpen on still runs.
/// - [afterDehaze]: Sharpen → Texture → Clarity → colour profile → Dehaze
///   are done too. Only the tonal blur and the two point-op passes remain
///   — the Basic panel, the curves, the mixer, grading, vignette and grain
///   all live there.
enum GpuStageBoundary { afterAiDenoise, afterDehaze }

/// Cross-render cache for the GPU chain (added 2026-09-09).
///
/// Before it, every settled render re-ran the whole chain from the
/// uploaded source — a Contrast change re-did the 9-pass chroma smoothing,
/// Sharpen, Texture, Clarity, the profile and Dehaze before the two passes
/// that had actually changed. Measured on a 6 MP frame: 15 passes / ~140
/// ms for a default render of which 2 passes are point ops.
///
/// The cache keeps one `ui.Image` per [GpuStageBoundary], each tagged with
/// a key built from the source's fingerprint, the frame size and *every
/// parameter consumed up to that boundary*. A render looks up the deepest
/// boundary whose key matches and resumes from there; a miss at both
/// boundaries is the old full chain. The stored images belong to the cache
/// (they are detached from the render's own [GpuImagePool]) and are
/// disposed when replaced or on [clear].
///
/// **Keys are the whole correctness story.** [keyFor] must include every
/// field a stage before the boundary reads; a field left out means a stale
/// image on screen. `test/render/gpu_stage_cache_key_test.dart` pins the
/// mapping for every field `RenderParams` has today, and
/// `RenderParams`'s doc comment points new fields here.
///
/// Mask layers never use it: `mask_gpu.dart` renders each layer from the
/// previous layer's output, a fresh image every time, so there is nothing
/// to resume from — only the global layer goes through the cache.
///
/// Main isolate only, like every `ui.Image` in this pipeline.
class GpuStageCache {
  GpuStageCache._();

  static final GpuStageCache instance = GpuStageCache._();

  /// Master switch, for measurement (`gpu_timing_probe_test.dart` times
  /// the cold chain with it off) and for A/B in the integration tests.
  static bool enabled = true;

  final Map<GpuStageBoundary, _Entry> _entries = {};

  /// Diagnostics: how many lookups found a matching image.
  int hits = 0;

  /// Diagnostics: how many lookups did not.
  int misses = 0;

  /// A cheap identity for a packed-RGB source buffer: its size plus an
  /// FNV-1a hash over ~16k bytes sampled at a fixed stride. The editor
  /// hands the same `Uint8List` back for the same photo, but the geometry
  /// pass (crop/lens) allocates a fresh buffer per render, so identity is
  /// not enough; sampled content is, at a cost of microseconds.
  static int sourceFingerprint(Uint8List rgb, int width, int height) {
    const samples = 16384;
    final stride = rgb.length <= samples ? 1 : rgb.length ~/ samples;
    var hash = 0xcbf29ce484222325;
    void mix(int byte) {
      hash ^= byte;
      hash *= 0x100000001b3;
    }

    for (var i = 0; i < rgb.length; i += stride) {
      mix(rgb[i]);
    }
    // The last bytes, which a coarse stride would otherwise skip.
    for (var i = rgb.length < 64 ? 0 : rgb.length - 64; i < rgb.length; i++) {
      mix(rgb[i]);
    }
    mix(rgb.length & 0xff);
    mix((rgb.length >> 8) & 0xff);
    mix((rgb.length >> 16) & 0xff);
    mix(width & 0xff);
    mix((width >> 8) & 0xff);
    mix(height & 0xff);
    mix((height >> 8) & 0xff);
    return hash;
  }

  /// The key an image at [boundary] is stored under: source, frame size and
  /// every parameter consumed by the stages up to that boundary — no more,
  /// so a later-stage change still hits, and no less, so an earlier-stage
  /// change never does.
  static String keyFor(
    GpuStageBoundary boundary,
    int sourceFingerprint,
    int width,
    int height,
    RenderParams p,
  ) {
    final sb = StringBuffer()
      ..write(sourceFingerprint)
      ..write('|')
      ..write(width)
      ..write('x')
      ..write(height)
      // renderScale feeds every radius from chroma smoothing on
      // (detailScale derives from it).
      ..write('|rs=')
      ..write(p.renderScale)
      // negative.frag, the very first pass when the section is on: its
      // sliders and the measured bounds both change every pixel after.
      ..write('|ng=')
      ..write(
        p.negative.enabled
            ? [
                p.negative.redWeight,
                p.negative.greenWeight,
                p.negative.blueWeight,
                p.negative.exposure,
                p.negative.contrast,
                ...?p.negativeBounds?.min,
                ...?p.negativeBounds?.max,
              ].join(',')
            : '0',
      )
      // _runPreDenoise: white balance and exposure.
      ..write('|t=')
      ..write(p.temperature)
      ..write('|ti=')
      ..write(p.tint)
      ..write('|ak=')
      ..write(p.asShotKelvin)
      ..write('|at=')
      ..write(p.asShotTint)
      ..write('|ex=')
      ..write(p.exposure)
      // runAiDenoiseGpu.
      ..write('|dn=')
      ..write(p.aiDenoise.level?.index ?? -1);
    if (boundary == GpuStageBoundary.afterAiDenoise) {
      return sb.toString();
    }
    sb
      // runSharpenGpu.
      ..write('|sa=')
      ..write(p.sharpen.amount)
      ..write('|sr=')
      ..write(p.sharpen.radius)
      ..write('|sd=')
      ..write(p.sharpen.detail)
      ..write('|sm=')
      ..write(p.sharpen.masking)
      // runLocalContrastGpu, twice.
      ..write('|tx=')
      ..write(p.texture)
      ..write('|cl=')
      ..write(p.clarity)
      // runColorProfileGpu.
      ..write('|bc=')
      ..write(p.baseContrast)
      ..write('|cps=')
      ..write(p.colorProfileStrength)
      ..write('|cp=');
    _writeProfile(sb, p.colorProfile);
    sb
      // runDehazeGpu.
      ..write('|dh=')
      ..write(p.dehaze);
    return sb.toString();
  }

  /// The profile by content, not by id: the profile editor changes a
  /// profile's tables under the same id while previewing.
  static void _writeProfile(StringBuffer sb, ColorProfile? profile) {
    if (profile == null) {
      sb.write('none');
      return;
    }
    sb
      ..write(profile.id)
      ..write(':')
      ..writeAll(profile.tone, ',')
      ..write(';')
      ..writeAll(profile.hueShift, ',')
      ..write(';')
      ..writeAll(profile.satMul, ',')
      ..write(';')
      ..writeAll(profile.lumMul, ',');
  }

  /// Whether a render of [params] over this source could skip the source
  /// upload entirely — i.e. at least one boundary would hit. Lets
  /// `renderRgbaGpu` skip `decodeRgbImage` on a hit.
  bool canResume(int sourceFingerprint, int width, int height, RenderParams p) {
    if (!enabled) {
      return false;
    }
    for (final boundary in GpuStageBoundary.values) {
      final entry = _entries[boundary];
      if (entry != null &&
          entry.key == keyFor(boundary, sourceFingerprint, width, height, p)) {
        return true;
      }
    }
    return false;
  }

  /// The image stored at [boundary] if its key is [key], else `null`. The
  /// image stays owned by the cache; the caller must treat it as borrowed.
  ui.Image? lookup(GpuStageBoundary boundary, String key) {
    if (!enabled) {
      return null;
    }
    final entry = _entries[boundary];
    if (entry == null || entry.key != key) {
      misses++;
      return null;
    }
    hits++;
    return entry.image;
  }

  /// Takes ownership of [image] as the entry for [boundary] and returns
  /// `true`; the caller must then stop treating the image as its own to
  /// dispose. Returns `false` — and touches nothing — while disabled, in
  /// which case the image stays the caller's.
  ///
  /// The entry it replaces is disposed unless the same `ui.Image` is also
  /// held at the other boundary — which happens when every stage between
  /// the two was an identity and handed its input straight through.
  bool adopt(GpuStageBoundary boundary, String key, ui.Image image) {
    if (!enabled) {
      return false;
    }
    final previous = _entries[boundary];
    _entries[boundary] = _Entry(key, image);
    if (previous != null &&
        !identical(previous.image, image) &&
        !_isHeld(previous.image)) {
      previous.image.dispose();
    }
    return true;
  }

  bool _isHeld(ui.Image image) =>
      _entries.values.any((e) => identical(e.image, image));

  /// Disposes every stored image. Cheap to call when nothing is stored.
  void clear() {
    final distinct = <ui.Image>{};
    for (final entry in _entries.values) {
      if (distinct.every((other) => !identical(other, entry.image))) {
        distinct.add(entry.image);
      }
    }
    _entries.clear();
    for (final image in distinct) {
      image.dispose();
    }
  }
}

class _Entry {
  const _Entry(this.key, this.image);

  final String key;
  final ui.Image image;
}
