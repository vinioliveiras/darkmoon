import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../catalog/inpaint_cache.dart';
import '../catalog/removal.dart';
import '../diagnostics/dev_log.dart';
import '../native/onnx_runtime.dart';
import '../raw_files.dart' show isRawFile;
import '../render/inpaint.dart';
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

/// The plain preview of a photo, handed to the worker so a removal can be
/// applied at the resolution the editor shows rather than the file's —
/// seconds instead of half a minute on a large RAW, whose full-resolution
/// decode alone took 19 s (measured 2026-09-12). Export still gets the
/// full-resolution result, computed then.
class InpaintPreviewSource {
  const InpaintPreviewSource(this.width, this.height, this.rgbBytes);

  final int width;
  final int height;
  final Uint8List rgbBytes;
}

/// The cache key of a preview-resolution result: the removals plus the
/// preview setting they were rendered under, so a changed setting misses.
String inpaintPreviewKey(List<Removal> removals, int previewMaxDimension) =>
    '${inpaintRemovalsKey(removals)}|p$previewMaxDimension';

/// Applies every visible removal in order — each one's coverage brought
/// to the frame's resolution and filled by the model from its
/// surroundings (see `inpaint.dart`) — to [preview] when given, else to
/// the photo decoded at full resolution; the result is cached as a PNG
/// under the removals' key (the preview one carries the preview
/// setting). Every removal is redone from the original when the key
/// misses — a few seconds each, and simpler than caching every prefix.
Future<EditSourcePair?> _decodeAndInpaint(
  String path,
  String cacheDir,
  int previewMaxDimension,
  List<Removal> removals,
  bool editEmbeddedJpeg,
  InpaintPreviewSource? preview,
  void Function(Object stage) onStage,
) async {
  final removalsKey = preview == null
      ? inpaintRemovalsKey(removals)
      : inpaintPreviewKey(removals, previewMaxDimension);
  final cachedPng = await lookupInpaintCache(
    cacheDir,
    path,
    removalsKey: removalsKey,
  );
  final cachedImage = cachedPng == null ? null : img.decodePng(cachedPng);
  if (cachedImage != null) {
    return _pairFrom(cachedImage, previewMaxDimension);
  }

  final int width;
  final int height;
  Uint8List rgb;
  if (preview != null) {
    width = preview.width;
    height = preview.height;
    rgb = preview.rgbBytes;
  } else {
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
    width = decoded.width;
    height = decoded.height;
    rgb = decoded.rgbBytes;
  }

  final visible = [
    for (final removal in removals)
      if (removal.visible) removal,
  ];
  if (visible.isNotEmpty) {
    // The model is only loaded when an AI fill is actually in the list:
    // a photo of clone and heal patches never pays for it.
    OnnxModel? model;
    final size = lamaInpaintModelSpec.inputTileSize;

    for (var i = 0; i < visible.length; i++) {
      final removal = visible[i];
      final stored = decodeAlphaPng(removal.alphaPng);
      if (stored == null) {
        continue;
      }
      final alpha = resampleAlpha(
        stored.alpha,
        stored.width,
        stored.height,
        width,
        height,
      );
      switch (removal.mode) {
        case RemovalMode.clone || RemovalMode.heal:
          rgb = cloneRegion(
            rgb,
            width,
            height,
            alpha,
            offsetX: (removal.sourceDx * width).round(),
            offsetY: (removal.sourceDy * height).round(),
            fill: removal.mode == RemovalMode.heal
                ? CloneFill.heal
                : CloneFill.clone,
          );
          onStage(InpaintProgress(i + 1, visible.length));
          continue;
        case RemovalMode.generative:
          final patch = removal.patchPng == null
              ? null
              : img.decodePng(removal.patchPng!);
          if (patch != null) {
            rgb = compositePatch(
              rgb,
              width,
              height,
              alpha,
              patch,
              left: removal.patchLeft,
              top: removal.patchTop,
              patchWidth: removal.patchWidth,
              patchHeight: removal.patchHeight,
            );
          }
          onStage(InpaintProgress(i + 1, visible.length));
          continue;
        case RemovalMode.ai:
          break;
      }
      final lama = model ??= () {
        final m = OnnxModel.forSpec(lamaInpaintModelSpec);
        onStage(InpaintModelInfo(m.usingGpu, m.provider.label, m.gpuError));
        return m;
      }();
      final imageInput = lama.inputNames[0];
      final maskInput = lama.inputNames[1];
      final outputName = lama.outputNames.first;
      rgb = inpaintRegion(
        rgb,
        width,
        height,
        alpha,
        modelSize: size,
        runModel: (imageChw, maskHw) {
          final outputs = lama.runGraph(
            {
              imageInput: OnnxTensorData.float32([1, 3, size, size], imageChw),
              maskInput: OnnxTensorData.float32([1, 1, size, size], maskHw),
            },
            [outputName],
          );
          return outputs[outputName]!.floats!;
        },
      );
      onStage(InpaintProgress(i + 1, visible.length));
    }
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
    this.preview,
    this.sendPort,
    this.cancelFlagAddress,
  );

  final String path;
  final String cacheDir;
  final int previewMaxDimension;
  final List<Removal> removals;
  final bool editEmbeddedJpeg;
  final InpaintPreviewSource? preview;
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
      args.preview,
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
  required List<Removal> removals,
  int previewMaxDimension = defaultPreviewMaxDimension,
  bool editEmbeddedJpeg = false,
  InpaintCancellationToken? cancellationToken,
  InpaintPreviewSource? preview,
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
      preview,
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
