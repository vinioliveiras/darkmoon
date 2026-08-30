import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../catalog/cloud_denoise_cache.dart';
import '../cloud_denoise/cloud_denoise_provider.dart';
import '../raw_files.dart' show isRawFile;
import 'common_image.dart';
import 'edit_source.dart';
import 'image_utils.dart';
import 'libraw.dart';

/// Sibling to `edit_source_ai_enhance.dart`'s `_decodeAndEnhance`, for the
/// cloud AI denoise pipeline instead of the on-device ONNX one: full-
/// resolution decode (cache permitting), one HTTP round-trip to a paid
/// third-party provider, then derives `preview`/`live` from the result —
/// same "becomes the new base for every later edit/mask/export" model.
///
/// Unlike the ONNX pipeline there's no tiling here — cloud providers take
/// one whole image per call, not per-tile inference — so the source is
/// JPEG-encoded (quality 92, not PNG) before upload: keeps the request
/// well under every provider's size limit (OpenAI's 50MB/image, Topaz's
/// 500MB/request) and, since Topaz bills by output resolution, keeps cost
/// down without a meaningfully different result — none of these providers
/// promise literal bit-exactness on a PNG upload either.
///
/// [onStage] receives a plain [String] stage name ('uploading',
/// 'processing', 'downloading' — see each `CloudDenoiseProvider.denoise`'s
/// own `onStage` calls) instead of a typed hierarchy the way the ONNX
/// pipeline's `RawDecodeStage`/`AiEnhanceProgress` are, since there's just
/// the one linear HTTP flow here, no per-tile progress to report.
Future<EditSourcePair?> _decodeAndCloudDenoise(
  String path,
  String cacheDir,
  int previewMaxDimension,
  CloudDenoiseProviderKind provider,
  String apiKey,
  void Function(String stage) onStage,
) async {
  int width;
  int height;
  Uint8List resultRgb;

  final cachedPng = await lookupCloudDenoiseCache(cacheDir, path, provider);
  final cachedImage = cachedPng == null ? null : img.decodePng(cachedPng);

  if (cachedImage != null) {
    width = cachedImage.width;
    height = cachedImage.height;
    resultRgb = cachedImage.getBytes(order: img.ChannelOrder.rgb);
  } else {
    onStage('decoding');
    final decoded = isRawFile(path)
        ? decodeRawImage(path, fastPreview: false)
        : decodeCommonImage(path);
    if (decoded == null) {
      return null;
    }

    final sourceImage = img.Image.fromBytes(
      width: decoded.width,
      height: decoded.height,
      bytes: decoded.rgbBytes.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );
    final uploadBytes = Uint8List.fromList(
      img.encodeJpg(sourceImage, quality: 92),
    );

    final resultBytes = await providerFor(
      provider,
    ).denoise(uploadBytes, apiKey, onStage: onStage);
    final resultImage = img.decodeImage(resultBytes);
    if (resultImage == null) {
      throw const FormatException(
        'Cloud provider returned bytes that could not be decoded as an image.',
      );
    }
    width = resultImage.width;
    height = resultImage.height;
    resultRgb = resultImage.getBytes(order: img.ChannelOrder.rgb);

    await storeCloudDenoiseCache(
      cacheDir,
      path,
      provider,
      Uint8List.fromList(
        img.encodePng(
          img.Image.fromBytes(
            width: width,
            height: height,
            bytes: resultRgb.buffer,
            numChannels: 3,
            order: img.ChannelOrder.rgb,
          ),
        ),
      ),
    );
  }

  final full = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: resultRgb.buffer,
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

/// [compute()] argument bundle for [decodeCachedCloudDenoiseSources].
class DecodeCachedCloudDenoiseArgs {
  const DecodeCachedCloudDenoiseArgs(this.pngBytes, this.previewMaxDimension);

  final Uint8List pngBytes;
  final int previewMaxDimension;
}

/// Derives preview/live [EditSourcePair] from a previously-cached cloud
/// denoise PNG — the fast path taken when reselecting/reopening a photo
/// a cloud provider already denoised, instead of paying for the same call
/// again. Runs via `compute()`. Returns null on a corrupt blob. Mirrors
/// `edit_source_ai_enhance.dart`'s `decodeCachedAiEnhanceSources` exactly.
EditSourcePair? decodeCachedCloudDenoiseSources(
  DecodeCachedCloudDenoiseArgs args,
) {
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

/// Reconstructs the *full* native-resolution [EditSource] from a cached
/// cloud-denoise PNG — needed by export, mirroring
/// `edit_source_ai_enhance.dart`'s `decodeAiEnhanceCacheEntry` exactly.
EditSource? decodeCloudDenoiseCacheEntry(Uint8List pngBytes) {
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

class _CloudDenoiseDecodeIsolateArgs {
  const _CloudDenoiseDecodeIsolateArgs(
    this.path,
    this.cacheDir,
    this.previewMaxDimension,
    this.provider,
    this.apiKey,
    this.sendPort,
  );

  final String path;
  final String cacheDir;
  final int previewMaxDimension;
  final CloudDenoiseProviderKind provider;
  final String apiKey;
  final SendPort sendPort;
}

void _cloudDenoiseDecodeIsolateEntry(_CloudDenoiseDecodeIsolateArgs args) async {
  try {
    final result = await _decodeAndCloudDenoise(
      args.path,
      args.cacheDir,
      args.previewMaxDimension,
      args.provider,
      args.apiKey,
      (stage) => args.sendPort.send(stage),
    );
    args.sendPort.send(result);
  } catch (e) {
    // CloudDenoiseException (or any other failure — a malformed response,
    // a network error) doesn't cross the isolate boundary as itself; wrap
    // it as a plain string the caller can show directly, same reasoning
    // as ai_enhance_job.dart's AiEnhanceIsolateResult.failure.
    args.sendPort.send(_CloudDenoiseFailure(e.toString()));
  }
}

/// Carries a failure message back across the isolate boundary — see
/// `_cloudDenoiseDecodeIsolateEntry`'s catch block.
class _CloudDenoiseFailure {
  const _CloudDenoiseFailure(this.message);
  final String message;
}

/// Lets a caller stop waiting on the cloud denoise isolate without the
/// isolate itself needing to cooperate — same shape as
/// `AiEnhanceCancellationToken`/`ExportCancellationToken`.
class CloudDenoiseCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get cancelled => _completer.future;

  void cancel() {
    if (!isCancelled) {
      _completer.complete();
    }
  }
}

/// Result of [decodeEditSourcesWithCloudDenoise] — a sealed success/failure
/// pair rather than a nullable `EditSourcePair?`, since a cloud call can
/// fail for a reason worth showing the user directly (bad key, provider
/// error, network failure), unlike the ONNX pipeline's null-on-any-failure
/// (which is always some flavor of "this local model/file didn't work").
sealed class CloudDenoiseResult {
  const CloudDenoiseResult();
}

class CloudDenoiseSuccess extends CloudDenoiseResult {
  const CloudDenoiseSuccess(this.sources);
  final EditSourcePair sources;
}

class CloudDenoiseFailed extends CloudDenoiseResult {
  const CloudDenoiseFailed(this.message);
  final String message;
}

class CloudDenoiseCancelled extends CloudDenoiseResult {
  const CloudDenoiseCancelled();
}

/// See [_decodeAndCloudDenoise]. [cacheDir] is
/// `resolveCloudDenoiseCacheDir()`'s result, resolved once on the main
/// isolate by the caller — same `path_provider`-isn't-isolate-safe
/// reasoning every other cache dir in this codebase follows.
Future<CloudDenoiseResult> decodeEditSourcesWithCloudDenoise(
  String path,
  String cacheDir,
  void Function(String stage) onStage, {
  required CloudDenoiseProviderKind provider,
  required String apiKey,
  int previewMaxDimension = defaultPreviewMaxDimension,
  CloudDenoiseCancellationToken? cancellationToken,
}) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
    _cloudDenoiseDecodeIsolateEntry,
    _CloudDenoiseDecodeIsolateArgs(
      path,
      cacheDir,
      previewMaxDimension,
      provider,
      apiKey,
      receivePort.sendPort,
    ),
  );
  try {
    Future<CloudDenoiseResult> receiveResult() async {
      await for (final message in receivePort) {
        if (message is String) {
          onStage(message);
        } else if (message is _CloudDenoiseFailure) {
          return CloudDenoiseFailed(message.message);
        } else {
          return message == null
              ? const CloudDenoiseFailed(
                  'The photo could not be decoded for upload.',
                )
              : CloudDenoiseSuccess(message as EditSourcePair);
        }
      }
      return const CloudDenoiseFailed(
        'Cloud denoise isolate closed unexpectedly.',
      );
    }

    final cancellation = cancellationToken == null
        ? Completer<CloudDenoiseResult>().future
        : cancellationToken.cancelled.then((_) => const CloudDenoiseCancelled());
    return await Future.any([receiveResult(), cancellation]);
  } finally {
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}
