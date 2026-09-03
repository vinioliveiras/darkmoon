import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../catalog/colorize_cache.dart';
import '../native/onnx_runtime.dart';
import '../raw_files.dart' show isRawFile;
import '../render/colorize.dart';
import 'common_image.dart';
import 'edit_source.dart';
import 'image_utils.dart';
import 'libraw.dart';

/// Reports which execution provider the DDColor session actually ended up
/// using — same role `ai_enhance_job.dart`'s `AiEnhanceModelInfo` plays,
/// duplicated (not shared) since this is a single always-one-model
/// pipeline, not several — sent once, right after the session is created
/// and before inference starts.
class ColorizeModelInfo {
  const ColorizeModelInfo(this.usingGpu, this.directMlError);

  final bool usingGpu;
  final String? directMlError;
}

/// Lets a caller stop waiting on the colorize isolate — same shape as
/// `ai_enhance_job.dart`'s `AiEnhanceCancellationToken`.
class ColorizeCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get cancelled => _completer.future;

  void cancel() {
    if (!isCancelled) {
      _completer.complete();
    }
  }
}

/// Export's equivalent for a photo with colorize active — the full-
/// resolution colorized buffer, not a plain RAW decode. Runs via
/// `compute()`. Returns null on a corrupt blob.
EditSource? decodeColorizeCacheEntry(Uint8List pngBytes) {
  final decoded = img.decodePng(pngBytes);
  if (decoded == null) {
    return null;
  }
  return EditSource(
    width: decoded.width,
    height: decoded.height,
    rgbBytes: decoded.getBytes(order: img.ChannelOrder.rgb),
  );
}

/// [compute()] argument bundle for [decodeCachedColorizeSources].
class DecodeCachedColorizeArgs {
  const DecodeCachedColorizeArgs(this.pngBytes, this.previewMaxDimension);

  final Uint8List pngBytes;
  final int previewMaxDimension;
}

/// Derives preview/live [EditSourcePair] from a previously-cached colorize
/// PNG — the fast path for reselecting/reopening a photo colorize was
/// already applied to. Runs via `compute()`. Returns null on a corrupt
/// blob.
EditSourcePair? decodeCachedColorizeSources(DecodeCachedColorizeArgs args) {
  final full = img.decodePng(args.pngBytes);
  if (full == null) {
    return null;
  }
  final previewImage = fitToMaxDimension(full, args.previewMaxDimension);
  final liveImage = fitToMaxDimension(previewImage, livePreviewMaxDimension);
  return EditSourcePair(
    preview: EditSource(
      width: previewImage.width,
      height: previewImage.height,
      rgbBytes: previewImage.getBytes(order: img.ChannelOrder.rgb),
    ),
    live: EditSource(
      width: liveImage.width,
      height: liveImage.height,
      rgbBytes: liveImage.getBytes(order: img.ChannelOrder.rgb),
    ),
  );
}

/// [intensityPercent] (0-100, see `colorize.dart`'s `colorizeImage`
/// `intensity` doc) is a whole percent for the same "don't fragment the
/// cache from a slider drag" reasoning as the AI Enhance amounts.
Future<EditSourcePair?> _decodeAndColorize(
  String path,
  String cacheDir,
  int previewMaxDimension,
  int intensityPercent,
  void Function(Object stage) onStage,
) async {
  int width;
  int height;
  Uint8List colorizedRgb;

  final cachedPng = await lookupColorizeCache(
    cacheDir,
    path,
    intensityPercent: intensityPercent,
  );
  final cachedImage = cachedPng == null ? null : img.decodePng(cachedPng);

  if (cachedImage != null) {
    width = cachedImage.width;
    height = cachedImage.height;
    colorizedRgb = cachedImage.getBytes(order: img.ChannelOrder.rgb);
  } else {
    final decoded = isRawFile(path)
        ? decodeRawImage(path, fastPreview: false, onStage: onStage)
        : decodeCommonImage(path);
    if (decoded == null) {
      return null;
    }

    final model = OnnxModel.forSpec(ddcolorModelSpec);
    onStage(ColorizeModelInfo(model.usingGpu, model.directMlError));

    colorizedRgb = colorizeImage(
      decoded.rgbBytes,
      decoded.width,
      decoded.height,
      runModel: (tile) => model.runToChannels(tile, 2),
      modelInputSize: ddcolorModelSpec.inputTileSize,
      intensity: intensityPercent / 100.0,
    );
    width = decoded.width;
    height = decoded.height;

    final colorizedImage = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: colorizedRgb.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );
    await storeColorizeCache(
      cacheDir,
      path,
      Uint8List.fromList(img.encodePng(colorizedImage)),
      intensityPercent: intensityPercent,
    );
  }

  final full = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: colorizedRgb.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final previewImage = fitToMaxDimension(full, previewMaxDimension);
  final liveImage = fitToMaxDimension(previewImage, livePreviewMaxDimension);
  return EditSourcePair(
    preview: EditSource(
      width: previewImage.width,
      height: previewImage.height,
      rgbBytes: previewImage.getBytes(order: img.ChannelOrder.rgb),
    ),
    live: EditSource(
      width: liveImage.width,
      height: liveImage.height,
      rgbBytes: liveImage.getBytes(order: img.ChannelOrder.rgb),
    ),
  );
}

class _ColorizeIsolateArgs {
  const _ColorizeIsolateArgs(
    this.path,
    this.cacheDir,
    this.previewMaxDimension,
    this.intensityPercent,
    this.sendPort,
  );

  final String path;
  final String cacheDir;
  final int previewMaxDimension;
  final int intensityPercent;
  final SendPort sendPort;
}

void _colorizeIsolateEntry(_ColorizeIsolateArgs args) async {
  final EditSourcePair? result;
  try {
    result = await _decodeAndColorize(
      args.path,
      args.cacheDir,
      args.previewMaxDimension,
      args.intensityPercent,
      (stage) => args.sendPort.send(stage),
    );
  } finally {
    // This isolate is spawned per colorize run and killed right after, but
    // the DDColor session it loaded is native memory that would outlive it
    // — a 934 MB graph leaked once per run. See [OnnxModel.releaseAll].
    OnnxModel.releaseAll();
  }
  args.sendPort.send(result);
}

/// See [_decodeAndColorize]. [cacheDir] is `resolveColorizeCacheDir()`'s
/// result, resolved once on the main isolate by the caller — same
/// `path_provider`-isn't-isolate-safe reasoning every other cache dir in
/// this codebase follows.
///
/// [cancellationToken], if given and cancelled, makes this return `null`
/// right away instead of waiting for the isolate to finish — same
/// `Future.any` race `edit_source_ai_enhance.dart`'s own function uses.
Future<EditSourcePair?> decodeEditSourcesWithColorize(
  String path,
  String cacheDir,
  void Function(Object stage) onStage, {
  required int intensityPercent,
  int previewMaxDimension = defaultPreviewMaxDimension,
  ColorizeCancellationToken? cancellationToken,
}) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
    _colorizeIsolateEntry,
    _ColorizeIsolateArgs(
      path,
      cacheDir,
      previewMaxDimension,
      intensityPercent,
      receivePort.sendPort,
    ),
  );
  try {
    Future<EditSourcePair?> receiveResult() async {
      await for (final message in receivePort) {
        if (message is RawDecodeStage || message is ColorizeModelInfo) {
          onStage(message);
        } else {
          return message as EditSourcePair?;
        }
      }
      return null;
    }

    final cancellation = cancellationToken == null
        ? Completer<EditSourcePair?>().future
        : cancellationToken.cancelled.then((_) => null);
    return await Future.any([receiveResult(), cancellation]);
  } finally {
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}
