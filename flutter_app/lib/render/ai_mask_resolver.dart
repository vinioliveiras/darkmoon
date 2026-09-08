import 'package:flutter/foundation.dart';

import '../catalog/ai_mask_cache.dart';
import '../native/ai_mask_models.dart';
import '../native/edit_source.dart';
import '../native/onnx_runtime.dart';
import 'crop_transform.dart';
import 'lens_correction.dart';
import 'mask.dart';
import 'render_job.dart';
import 'render_params.dart';

/// What one AI mask needs answered: which model, and what the user aimed
/// it at. Only [SubjectGeometry] is a prompt — Sky, Foreground and Depth
/// ask the same question of every photo.
@immutable
class AiMaskRequest {
  const AiMaskRequest({
    required this.maskId,
    required this.type,
    this.subject = const SubjectGeometry(),
  });

  final String maskId;
  final MaskType type;
  final SubjectGeometry subject;

  /// The part of the cache key the user controls. Rounded to four
  /// decimals so that nudging a box by a hundredth of a pixel — which no
  /// model output could resolve — doesn't miss the cache.
  String get promptKey => type == MaskType.subject
      ? '${subject.startX.toStringAsFixed(4)},'
            '${subject.startY.toStringAsFixed(4)},'
            '${subject.endX.toStringAsFixed(4)},'
            '${subject.endY.toStringAsFixed(4)}'
      : '';
}

/// One `compute()` argument bundle — the frame to look at, and every mask
/// that needs an answer about it.
///
/// Carries the same geometry inputs [RenderJob] does because it rebuilds
/// exactly the frame the render will run on: masks are computed after
/// lens correction and crop, so a map made from the uncropped photo would
/// be offset from everything it is composited against.
@immutable
class AiMaskResolveRequest {
  const AiMaskResolveRequest({
    required this.source,
    required this.requests,
    required this.cacheDir,
    this.cropTransform = const CropTransformParams(),
    this.lensCorrection = const LensCorrectionParams(),
    this.lensProfile,
    this.focalLengthMm = 0,
    this.apertureFNumber = 0,
  });

  final EditSource source;
  final List<AiMaskRequest> requests;
  final String cacheDir;
  final CropTransformParams cropTransform;
  final LensCorrectionParams lensCorrection;
  final LensProfile? lensProfile;
  final double focalLengthMm;
  final double apertureFNumber;
}

/// What [resolveAiMaskMaps] came back with: a map per mask that succeeded,
/// and a message per mask that didn't.
///
/// Failures are per-mask rather than one thrown exception because the
/// models are independent and their most likely failure — a missing model
/// file — hits one type at a time. A photo with a Sky mask and a Depth
/// mask should not lose both because one model is absent.
@immutable
class AiMaskResolveResult {
  const AiMaskResolveResult({required this.maps, required this.failures});

  final Map<String, AiMaskMap> maps;
  final Map<String, String> failures;
}

/// Computes (or reads from cache) the model output behind every mask in
/// [request].
///
/// Meant for `compute()`: it blocks for seconds and holds ONNX sessions,
/// neither of which belongs on the main isolate. Releases those sessions
/// before returning — a spawned isolate's native memory outlives it
/// otherwise, which is a real leak this app has already paid for once
/// (see [OnnxModel.releaseAll]).
Future<AiMaskResolveResult> resolveAiMaskMaps(
  AiMaskResolveRequest request,
) async {
  final maps = <String, AiMaskMap>{};
  final failures = <String, String>{};
  if (request.requests.isEmpty) {
    return AiMaskResolveResult(maps: maps, failures: failures);
  }

  try {
    // The same frame the render will see: lens correction and crop
    // applied, then scaled down to the working resolution every model
    // here is fed at.
    final geometry = prepareRenderGeometry(
      RenderJob(
        source: request.source,
        // prepareRenderGeometry reads only the lens and crop fields;
        // the adjustment pipeline never runs here.
        params: const RenderParams(),
        cropTransform: request.cropTransform,
        lensCorrection: request.lensCorrection,
        lensProfile: request.lensProfile,
        focalLengthMm: request.focalLengthMm,
        apertureFNumber: request.apertureFNumber,
      ),
    );
    final frame = _toWorkingResolution(
      geometry.rgbBytes,
      geometry.width,
      geometry.height,
    );
    final signature = aiMaskFrameSignature(frame.rgb);

    // At most one embedding per resolve, however many Subject masks the
    // photo has: the encoder looks at the photo, not at the prompt, so
    // two subjects share one 3.5-second pass.
    Float32List? embedding;
    Future<Float32List> embeddingFor() async {
      if (embedding != null) {
        return embedding!;
      }
      final key = aiMaskCacheKey(
        frameSignature: signature,
        kind: 'sam-embedding',
      );
      final cached = await lookupAiMaskEmbedding(request.cacheDir, key);
      if (cached != null) {
        return embedding = cached;
      }
      final computed = runSubjectEmbedding(frame.rgb, frame.width, frame.height);
      await storeAiMaskEmbedding(request.cacheDir, key, computed);
      return embedding = computed;
    }

    for (final req in request.requests) {
      final key = aiMaskCacheKey(
        frameSignature: signature,
        kind: req.type.name,
        prompt: req.promptKey,
      );
      final cached = await lookupAiMaskMap(request.cacheDir, key);
      if (cached != null) {
        maps[req.maskId] = cached;
        continue;
      }
      try {
        final map = switch (req.type) {
          MaskType.sky => runSkyMaskModel(frame.rgb, frame.width, frame.height),
          MaskType.foreground => runForegroundMaskModel(
            frame.rgb,
            frame.width,
            frame.height,
          ),
          MaskType.depth => runDepthMapModel(
            frame.rgb,
            frame.width,
            frame.height,
          ),
          MaskType.subject => runSubjectMaskModel(
            await embeddingFor(),
            req.subject,
            frame.width,
            frame.height,
          ),
          _ => throw ArgumentError('not an AI mask type: ${req.type}'),
        };
        maps[req.maskId] = map;
        await storeAiMaskMap(request.cacheDir, key, map);
      } catch (e) {
        failures[req.maskId] = '$e';
      }
    }
  } catch (e) {
    for (final req in request.requests) {
      failures[req.maskId] = '$e';
    }
  } finally {
    OnnxModel.releaseAll();
  }
  return AiMaskResolveResult(maps: maps, failures: failures);
}

class _WorkingFrame {
  const _WorkingFrame(this.rgb, this.width, this.height);

  final Uint8List rgb;
  final int width;
  final int height;
}

_WorkingFrame _toWorkingResolution(Uint8List rgb, int width, int height) {
  final longSide = width > height ? width : height;
  if (longSide <= aiMaskWorkingMaxDimension) {
    return _WorkingFrame(rgb, width, height);
  }
  final scale = aiMaskWorkingMaxDimension / longSide;
  final dw = (width * scale).round().clamp(1, aiMaskWorkingMaxDimension);
  final dh = (height * scale).round().clamp(1, aiMaskWorkingMaxDimension);
  return _WorkingFrame(resizeRgbForAiMask(rgb, width, height, dw, dh), dw, dh);
}
