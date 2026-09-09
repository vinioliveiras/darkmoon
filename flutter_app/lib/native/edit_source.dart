import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../raw_files.dart' show isRawFile;
import 'background_priority.dart';
import 'camera_match.dart';
import 'common_image.dart';
import 'image_utils.dart';
import 'libraw.dart';

/// Default long-edge cap the editing pipeline downscales to instead of the
/// sensor's native resolution — much cheaper to re-render on every
/// adjustment (both the RAW decode itself, via [decodeRawImage]'s
/// `fastPreview`, and every settled-view render afterward) than the
/// sensor's native resolution. Overridable per call (see
/// [decodeEditSources]'s `previewMaxDimension` parameter) — this is just
/// the value used when no explicit choice is passed, and matches the
/// app settings' own default preview resolution (`app_settings.dart`).
///
/// Was raised from 1024 to 1600 (2026-09-01, real complaint: the settled
/// view looked "blurry and blocky" at 1024 on a current 1440p/4K editor
/// panel — confirmed by rendering a real photo and comparing a 1:1 crop).
/// Reverted back to 1024 the next day (2026-09-02): every settled render
/// (including one a toggle switch triggers, not just a slider) runs its
/// ~10-stage GPU shader chain inline on the main UI isolate (`dart:ui`'s
/// GPU primitives can't run off it — see `render_gpu.dart`'s doc
/// comment), and that chain's cost scales with this resolution — at 1600
/// it was consistently long enough to visibly stall the frame pump (a
/// toggle's own Switch animation freezing instead of playing), confirmed
/// fixed by the user dropping their own Settings value to 1024. This is a
/// main-isolate-orchestration cost (Picture recording + rasterize +
/// readback per stage, serialized), not raw GPU compute throughput, so a
/// fast GPU doesn't fix it by itself. The blurry-at-1024 complaint above
/// is still real — this is a deliberate trade back toward interaction
/// smoothness over settled-view sharpness, not a discovery that the
/// earlier bump was wrong. See PENDING.md / project_gpu_render_plan.md
/// for the fuller trail; the real fix (render cheap first, then upgrade
/// quality in the background) would let this go back to 1600 without the
/// stall — not done yet.
const int defaultPreviewMaxDimension = 1024;

/// A smaller version of the same buffer: used while a slider is actively
/// being dragged so re-rendering stays fast enough to feel live, swapped
/// back out for the settled [EditSourcePair.preview] render as soon as the
/// drag ends.
const int livePreviewMaxDimension = 800;

/// One decoded working-resolution RGB buffer (packed, 3 bytes/pixel) that
/// the render pipeline reads from.
class EditSource {
  const EditSource({
    required this.width,
    required this.height,
    required this.rgbBytes,
  });

  final int width;
  final int height;
  final Uint8List rgbBytes;
}

/// The two resolutions [decodeEditSources] produces for one photo.
class EditSourcePair {
  const EditSourcePair({
    required this.preview,
    required this.live,
    this.baseExposureStops,
    this.baseToneCurve,
  });

  final EditSource preview;
  final EditSource live;

  /// [RawImage.baseExposureStops] for the file these came from — null for
  /// anything that carries no camera preview to compare against, which is
  /// every non-RAW source.
  ///
  /// Also null for a pair that came back from a cache rather than a fresh
  /// decode: the offset is measured inside [decodeRawImage], which a cache
  /// hit skips by design. See [probeCameraMatch], which puts it
  /// back.
  final double? baseExposureStops;

  /// [RawImage.baseToneCurve] for the file these came from — the camera's
  /// own tonality, as a [ColorProfile.tone] curve. Null on the same terms
  /// as [baseExposureStops], and lost by a cache the same way.
  ///
  /// Subsumes [baseExposureStops]; the renderer spends one or the other.
  final List<double>? baseToneCurve;

  /// This pair with [match] measured onto it — the one thing a cache hit
  /// cannot reconstruct on its own.
  EditSourcePair withCameraMatch(CameraMatch match) => EditSourcePair(
    preview: preview,
    live: live,
    baseExposureStops: match.stops,
    baseToneCurve: match.tone,
  );
}

/// What a decode learns by comparing itself against the camera's own
/// embedded rendering of the same shot: how far off it is overall, and how
/// its tonality is distributed.
///
/// The two are measured from the same pair and are always present or
/// absent together. They are alternatives, not layers — see
/// [cameraToneCurve].
class CameraMatch {
  const CameraMatch({this.stops, this.tone});

  static const none = CameraMatch();

  final double? stops;
  final List<double>? tone;

  bool get isEmpty => stops == null && tone == null;
}

Uint8List _rgbBytes(img.Image image) =>
    image.getBytes(order: img.ChannelOrder.rgb);

/// Fully decodes the RAW file at [path] once and derives the two working
/// resolutions the editor renders against, so later adjustments only need
/// to re-run the (much cheaper) pixel-math pipeline, not the RAW decode.
///
/// [previewMaxDimension] is the long-edge cap [EditSourcePair.preview] is
/// downscaled to — see [AppSettings.previewResolution], which callers
/// should pass through here rather than relying on the
/// [defaultPreviewMaxDimension] fallback.
///
/// [onStage], if given, is called as each [RawDecodeStage] of the
/// underlying LibRaw decode starts — see [decodeRawImage].
///
/// Designed to run via `compute()` (when [onStage] is null — a `compute()`
/// call only returns once, at the end, so it can't carry intermediate
/// stage signals) or via [decodeEditSourcesWithProgress] otherwise.
EditSourcePair? decodeEditSources(
  String path, {
  int previewMaxDimension = defaultPreviewMaxDimension,
  void Function(RawDecodeStage stage)? onStage,
}) {
  final decoded = isRawFile(path)
      ? decodeRawImage(path, fastPreview: true, onStage: onStage)
      : decodeCommonImage(path);
  if (decoded == null) {
    return null;
  }
  final full = img.Image.fromBytes(
    width: decoded.width,
    height: decoded.height,
    bytes: decoded.rgbBytes.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  // Zero means native: no cap at all, so the editing buffer is the
  // sensor's own resolution. fitToMaxDimension would read a zero as
  // "shrink to nothing", so it never sees one.
  final previewImage = previewMaxDimension <= 0
      ? full
      : fitToMaxDimension(full, previewMaxDimension);
  final liveImage = fitToMaxDimension(previewImage, livePreviewMaxDimension);
  return EditSourcePair(
    baseExposureStops: decoded.baseExposureStops,
    baseToneCurve: decoded.baseToneCurve,
    preview: EditSource(
      width: previewImage.width,
      height: previewImage.height,
      rgbBytes: _rgbBytes(previewImage),
    ),
    live: EditSource(
      width: liveImage.width,
      height: liveImage.height,
      rgbBytes: _rgbBytes(liveImage),
    ),
  );
}

class _EditSourcesIsolateArgs {
  const _EditSourcesIsolateArgs(
    this.path,
    this.previewMaxDimension,
    this.sendPort, {
    this.lowPriority = false,
  });

  final String path;
  final int previewMaxDimension;
  final SendPort sendPort;
  final bool lowPriority;
}

void _decodeEditSourcesIsolateEntry(_EditSourcesIsolateArgs args) {
  if (args.lowPriority) {
    lowerBackgroundThreadPriority();
  }
  final result = decodeEditSources(
    args.path,
    previewMaxDimension: args.previewMaxDimension,
    onStage: (stage) => args.sendPort.send(stage),
  );
  args.sendPort.send(result);
}

/// Same work as [decodeEditSources], but run in a dedicated [Isolate]
/// (rather than `compute()`, which only returns once at the very end) so
/// [onProgress] can be called as each [RawDecodeStage] starts — the same
/// pattern `export_job.dart`'s `exportPhotoWithProgress` uses.
///
/// [lowPriority] drops the decode isolate's OS thread to below-normal
/// priority — pass it for speculative prewarming (the preview-cache
/// preload when a folder opens), never for a decode the user is actively
/// waiting on.
Future<EditSourcePair?> decodeEditSourcesWithProgress(
  String path,
  void Function(RawDecodeStage stage) onProgress, {
  int previewMaxDimension = defaultPreviewMaxDimension,
  bool lowPriority = false,
}) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
    _decodeEditSourcesIsolateEntry,
    _EditSourcesIsolateArgs(
      path,
      previewMaxDimension,
      receivePort.sendPort,
      lowPriority: lowPriority,
    ),
  );
  try {
    await for (final message in receivePort) {
      if (message is RawDecodeStage) {
        onProgress(message);
      } else {
        return message as EditSourcePair?;
      }
    }
    return null;
  } finally {
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

/// Encodes [pair]'s preview resolution as a JPEG for the on-disk preview
/// cache (see `catalog/preview_cache_dir.dart`) — deliberately only the
/// preview, not the smaller `live` resolution: `live` is always cheaply
/// re-derived from `preview` via [fitToMaxDimension] (see
/// [decodeEditSourcePairFromCachedJpeg] below), so caching it separately
/// would just double the disk cost for no benefit.
///
/// Designed to run via `compute()` — JPEG-encoding a full preview isn't
/// free, and this only runs once per photo (right after a cache-miss RAW
/// decode), not on every render.
Uint8List encodePreviewForCache(EditSourcePair pair) {
  final image = img.Image.fromBytes(
    width: pair.preview.width,
    height: pair.preview.height,
    bytes: pair.preview.rgbBytes.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  return Uint8List.fromList(
    img.encodeJpg(image, quality: 90, chroma: img.JpegChroma.yuv420),
  );
}

/// Reconstructs an [EditSourcePair] from a JPEG previously produced by
/// [encodePreviewForCache] — the fast path a preview-cache *hit* takes,
/// skipping the RAW decode (and its LibRaw isolate) entirely: decoding an
/// already-downscaled JPEG back to pixels is a small fraction of the cost
/// of demosaicing the original sensor data again.
///
/// Returns null if [jpegBytes] doesn't decode (corrupt cache entry) —
/// callers should fall back to a real RAW decode in that case, same as a
/// cache miss.
///
/// Designed to run via `compute()`.
EditSourcePair? decodeEditSourcePairFromCachedJpeg(Uint8List jpegBytes) {
  final decoded = img.decodeJpg(jpegBytes);
  if (decoded == null) {
    return null;
  }
  final liveImage = fitToMaxDimension(decoded, livePreviewMaxDimension);
  return EditSourcePair(
    preview: EditSource(
      width: decoded.width,
      height: decoded.height,
      rgbBytes: _rgbBytes(decoded),
    ),
    live: EditSource(
      width: liveImage.width,
      height: liveImage.height,
      rgbBytes: _rgbBytes(liveImage),
    ),
  );
}

/// Re-measures the camera match for a photo whose pixels
/// came back from a cache instead of a fresh RAW decode.
///
/// The offset is measured inside [decodeRawImage], so a cache hit — the
/// plain preview cache and the three pipeline caches alike — handed back a
/// pair carrying none, and the photo rendered at LibRaw's auto-brightened
/// exposure with nothing pulling it back down. That is the highlights
/// blowing out on every open after the first, reported 2026-09-09 and the
/// reason this exists.
///
/// Measuring again here, rather than storing the number alongside the
/// cache entry, is deliberate: it is the same comparison against the same
/// embedded JPEG, it needs no change to any of the four cache formats, and
/// it repairs the entries already sitting on disk instead of only the ones
/// written from now on.
///
/// [source] is the cached *preview*, not the full sensor frame the fresh
/// path measures — a mean is scale-invariant, so the two agree to within
/// the cache JPEG's own rounding.
///
/// Designed to run via `compute()` (record arg, since `compute` takes one
/// value).
CameraMatch probeCameraMatch(
  ({EditSource source, Uint8List embeddedJpeg}) args,
) => CameraMatch(
  stops: cameraExposureOffsetStops(
    args.source.rgbBytes,
    args.source.width,
    args.source.height,
    args.embeddedJpeg,
  ),
  tone: cameraToneCurve(
    args.source.rgbBytes,
    args.source.width,
    args.source.height,
    args.embeddedJpeg,
  ),
);

/// [probeCameraMatch] at below-normal OS-thread priority — the form the
/// folder-open preview-cache preload uses, so re-measuring a photo nobody
/// has selected yet yields to the UI isolate.
CameraMatch probeCameraMatchLowPriority(
  ({EditSource source, Uint8List embeddedJpeg}) args,
) {
  lowerBackgroundThreadPriority();
  return probeCameraMatch(args);
}

/// [decodeEditSourcePairFromCachedJpeg] wrapped to run at below-normal
/// OS-thread priority — the form the folder-open preview-cache preload
/// uses via `compute()`, so prewarming photos nobody's selected yet
/// yields to the UI isolate. A genuine selection decodes at normal
/// priority (the plain function above), since the user is waiting on it.
EditSourcePair? decodeEditSourcePairFromCachedJpegLowPriority(
  Uint8List jpegBytes,
) {
  lowerBackgroundThreadPriority();
  return decodeEditSourcePairFromCachedJpeg(jpegBytes);
}

/// Decodes the photo at [path] at full native resolution — no preview
/// downscale, and (for a RAW file, unlike
/// [decodeEditSources]) `fastPreview: false` for LibRaw's slower
/// higher-quality demosaic regardless of sensor, so "full quality" means
/// the same thing regardless of camera. Backs the editor's opt-in
/// full-quality view toggle: pixel math over 10s of megapixels instead of
/// ~1.7M is a real cost, so this is only decoded when the user explicitly
/// asks for it. Common image formats have no quality knob to skip —
/// they're always decoded at their one native resolution.
///
/// Designed to run via `compute()`.
EditSource? decodeFullQualitySource(String path) {
  final decoded = isRawFile(path)
      ? decodeRawImage(path, fastPreview: false)
      : decodeCommonImage(path);
  if (decoded == null) {
    return null;
  }
  return EditSource(
    width: decoded.width,
    height: decoded.height,
    rgbBytes: decoded.rgbBytes,
  );
}

/// Encodes a native-resolution [EditSource] as a high-quality JPEG for
/// `catalog/native_source_cache.dart` — quality 96, no chroma subsampling
/// (4:4:4), since this is a *source* that gets re-rendered: baking in
/// half-resolution chroma here would show up amplified after tone/colour
/// work. Designed to run via `compute()`.
Uint8List encodeNativeSourceForCache(EditSource source) {
  final image = img.Image.fromBytes(
    width: source.width,
    height: source.height,
    bytes: source.rgbBytes.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 96));
}

/// Reconstructs the native-resolution [EditSource] from a JPEG produced by
/// [encodeNativeSourceForCache] — the fast path a native-source-cache hit
/// takes, skipping the RAW demosaic entirely. Returns null on a corrupt
/// blob (caller falls back to [decodeFullQualitySource]). Runs via
/// `compute()`.
EditSource? decodeNativeSourceFromCachedJpeg(Uint8List jpegBytes) {
  final decoded = img.decodeJpg(jpegBytes);
  if (decoded == null) {
    return null;
  }
  return EditSource(
    width: decoded.width,
    height: decoded.height,
    rgbBytes: _rgbBytes(decoded),
  );
}

/// [decodeFullQualitySource] at below-normal OS-thread priority — used
/// when the decode is a background nicety rather than something the user
/// is blocked on, so it must yield to the UI isolate. Runs via
/// `compute()`.
EditSource? decodeFullQualitySourceLowPriority(String path) {
  lowerBackgroundThreadPriority();
  return decodeFullQualitySource(path);
}

