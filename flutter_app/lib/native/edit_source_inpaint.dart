import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../catalog/inpaint_cache.dart';
import '../diagnostics/dev_log.dart';
import '../native/onnx_runtime.dart';
import '../raw_files.dart' show isRawFile;
import '../render/inpaint.dart';
import '../render/mask.dart';
import 'common_image.dart';
import 'edit_source.dart';
import 'image_utils.dart';
import 'isolate_job.dart';
import 'libraw.dart';

/// Which execution provider the LaMa session landed on — sent once,
/// right after the session is created and before the first removal.
class InpaintModelInfo {
  const InpaintModelInfo(this.usingGpu, this.providerLabel, this.gpuError);

  final bool usingGpu;
  final String providerLabel;
  final String? gpuError;
}

/// One removal done, of how many.
class InpaintProgress {
  const InpaintProgress(this.done, this.total);

  final int done;
  final int total;
}

/// Lets a caller stop waiting on the worker — same shape as the colorize
/// token; the worker is asked to stop, releases its session and exits.
class InpaintCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get cancelled => _completer.future;

  void cancel() {
    if (!isCancelled) {
      _completer.complete();
    }
  }
}

/// Export's source for a photo with removals: the full-resolution result.
/// Runs via `compute()`. Null on a corrupt blob.
EditSource? decodeInpaintCacheEntry(Uint8List pngBytes) {
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

class DecodeCachedInpaintArgs {
  const DecodeCachedInpaintArgs(this.pngBytes, this.previewMaxDimension);

  final Uint8List pngBytes;
  final int previewMaxDimension;
}

/// The preview/live pair from a cached result — the fast path when a photo
/// with removals is selected again. Runs via `compute()`.
EditSourcePair? decodeCachedInpaintSources(DecodeCachedInpaintArgs args) {
  final full = img.decodePng(args.pngBytes);
  if (full == null) {
    return null;
  }
  return _pairFrom(full, args.previewMaxDimension);
}

EditSourcePair _pairFrom(img.Image full, int previewMaxDimension) {
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

/// Decodes the photo at full resolution and applies every removal in
/// order, each one a brush mask rasterised at that resolution and filled
/// by the model from its surroundings (see `inpaint.dart`); the result is
/// cached as a PNG under the removals' key. Every removal is redone from
/// the original when the key misses — a few seconds each, and simpler
/// than caching every prefix.
Future<EditSourcePair?> _decodeAndInpaint(
  String path,
  String cacheDir,
  int previewMaxDimension,
  List<BrushGeometry> removals,
  bool editEmbeddedJpeg,
  void Function(Object stage) onStage,
) async {
  final removalsKey = inpaintRemovalsKey(removals);
  final cachedPng = await lookupInpaintCache(
    cacheDir,
    path,
    removalsKey: removalsKey,
  );
  final cachedImage = cachedPng == null ? null : img.decodePng(cachedPng);
  if (cachedImage != null) {
    return _pairFrom(cachedImage, previewMaxDimension);
  }

  final decoded = isRawFile(path)
      ? decodeSourceImage(
          path,
          embeddedJpeg: editEmbeddedJpeg,
          fastPreview: false,
          onStage: onStage,
        )
      : decodeCommonImage(path);
  if (decoded == null) {
    return null;
  }
  final width = decoded.width;
  final height = decoded.height;

  final model = OnnxModel.forSpec(lamaInpaintModelSpec);
  onStage(
    InpaintModelInfo(model.usingGpu, model.provider.label, model.gpuError),
  );
  final size = lamaInpaintModelSpec.inputTileSize;
  final imageInput = model.inputNames[0];
  final maskInput = model.inputNames[1];
  final outputName = model.outputNames.first;

  var rgb = decoded.rgbBytes;
  for (var i = 0; i < removals.length; i++) {
    final alpha = computeMaskAlpha(
      MaskLayer(
        id: 'removal',
        name: 'removal',
        type: MaskType.brush,
        brush: removals[i],
      ),
      width,
      height,
    );
    rgb = inpaintRegion(
      rgb,
      width,
      height,
      alpha,
      modelSize: size,
      runModel: (imageChw, maskHw) {
        final outputs = model.runGraph(
          {
            imageInput: OnnxTensorData.float32([1, 3, size, size], imageChw),
            maskInput: OnnxTensorData.float32([1, 1, size, size], maskHw),
          },
          [outputName],
        );
        return outputs[outputName]!.floats!;
      },
    );
    onStage(InpaintProgress(i + 1, removals.length));
  }

  final full = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgb.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  await storeInpaintCache(
    cacheDir,
    path,
    Uint8List.fromList(img.encodePng(full)),
    removalsKey: removalsKey,
  );
  return _pairFrom(full, previewMaxDimension);
}

class _InpaintIsolateArgs {
  const _InpaintIsolateArgs(
    this.path,
    this.cacheDir,
    this.previewMaxDimension,
    this.removals,
    this.editEmbeddedJpeg,
    this.sendPort,
    this.cancelFlagAddress,
  );

  final String path;
  final String cacheDir;
  final int previewMaxDimension;
  final List<BrushGeometry> removals;
  final bool editEmbeddedJpeg;
  final SendPort sendPort;
  final int cancelFlagAddress;
}

void _inpaintIsolateEntry(_InpaintIsolateArgs args) async {
  final cancel = IsolateCancelFlag.fromAddress(args.cancelFlagAddress);
  EditSourcePair? result;
  try {
    result = await _decodeAndInpaint(
      args.path,
      args.cacheDir,
      args.previewMaxDimension,
      args.removals,
      args.editEmbeddedJpeg,
      (stage) {
        // Cancel checkpoint: every decode stage, the model-info event and
        // each removal's completion pass through here.
        if (cancel.isSet) {
          throw const IsolateCancelled();
        }
        args.sendPort.send(stage);
      },
    );
  } on IsolateCancelled {
    result = null;
  } finally {
    // The session is native memory that would outlive this isolate.
    OnnxModel.releaseAll();
  }
  args.sendPort.send(result);
}

/// See [_decodeAndInpaint]. [cacheDir] is `resolveInpaintCacheDir()`'s
/// result, resolved on the main isolate by the caller. Same isolate,
/// cancellation and error handling as `edit_source_colorize.dart`.
Future<EditSourcePair?> decodeEditSourcesWithInpaint(
  String path,
  String cacheDir,
  void Function(Object stage) onStage, {
  required List<BrushGeometry> removals,
  int previewMaxDimension = defaultPreviewMaxDimension,
  bool editEmbeddedJpeg = false,
  InpaintCancellationToken? cancellationToken,
}) async {
  final receivePort = ReceivePort();
  final exitPort = ReceivePort();
  final cancelFlag = IsolateCancelFlag();
  final isolate = await Isolate.spawn(
    _inpaintIsolateEntry,
    _InpaintIsolateArgs(
      path,
      cacheDir,
      previewMaxDimension,
      removals,
      editEmbeddedJpeg,
      receivePort.sendPort,
      cancelFlag.address,
    ),
    onError: receivePort.sendPort,
    onExit: exitPort.sendPort,
  );
  unawaited(disposeOnIsolateExit(exitPort, cancelFlag));
  try {
    Future<EditSourcePair?> receiveResult() async {
      await for (final message in receivePort) {
        if (message is RawDecodeStage ||
            message is InpaintModelInfo ||
            message is InpaintProgress) {
          onStage(message);
          continue;
        }
        final error = IsolateError.of(message);
        if (error != null) {
          DevLog.logError('Inpaint isolate', error.error, error.trace);
          return null;
        }
        return message as EditSourcePair?;
      }
      return null;
    }

    final cancellation = cancellationToken == null
        ? Completer<EditSourcePair?>().future
        : cancellationToken.cancelled.then((_) {
            cancelFlag.set();
            return null;
          });
    return await Future.any([receiveResult(), cancellation]);
  } finally {
    receivePort.close();
    if (!cancelFlag.isSet) {
      isolate.kill(priority: Isolate.immediate);
    }
  }
}
