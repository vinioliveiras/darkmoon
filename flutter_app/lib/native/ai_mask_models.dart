import 'dart:math' as math;
import 'dart:typed_data';

import '../render/mask.dart';
import 'onnx_runtime.dart';

/// Long side every AI mask map is computed and cached at.
///
/// The models all resize their input down to a few hundred pixels anyway
/// (320 for the U-2-Nets, 518 for depth, 1024 for SAM), so inferring on a
/// 24 MP frame buys nothing but memory traffic — and SAM's decoder is the
/// hard limit: it resizes its output back to whatever size it is told the
/// image is, so pointing it at a 6000x4000 frame asks ONNX Runtime for a
/// 384 MB output tensor. `computeMaskAlpha` rescales the map to the
/// render's real dimensions, which is what every other mask type does with
/// its own normalized geometry anyway.
const int aiMaskWorkingMaxDimension = 1024;

/// ImageNet channel statistics — the normalization all three float-input
/// models here were trained with.
const List<double> _imagenetMean = [0.485, 0.456, 0.406];
const List<double> _imagenetStd = [0.229, 0.224, 0.225];

/// SAM's fixed input side; also the side its coordinate prompts are
/// expressed in.
const int _samInputSize = 1024;

/// Runs the sky segmentation model over a packed-RGB frame, returning the
/// probability that each pixel is sky.
///
/// Blocking — main-isolate calls will jank. Caller owns
/// [OnnxModel.releaseAll].
AiMaskMap runSkyMaskModel(Uint8List rgb, int width, int height) =>
    _runU2Net(skySegModelSpec, rgb, width, height);

/// Runs salient-object detection over a packed-RGB frame, returning how
/// strongly each pixel belongs to the subject rather than the background.
/// Same contract as [runSkyMaskModel].
AiMaskMap runForegroundMaskModel(Uint8List rgb, int width, int height) =>
    _runU2Net(foregroundSegModelSpec, rgb, width, height);

/// The two U-2-Net-architecture models are one function: same 320x320
/// letterboxed input, same ImageNet normalization, same seven outputs of
/// which only the first is the fused prediction, same min-max stretch of
/// that output into a 0..255 map. Only the weights differ.
AiMaskMap _runU2Net(
  OnnxModelSpec spec,
  Uint8List rgb,
  int width,
  int height,
) {
  final model = OnnxModel.forSpec(spec);
  const size = 320;
  final boxed = _letterbox(rgb, width, height, size);

  final outputs = model.runGraph({
    model.inputNames.first: OnnxTensorData.float32([1, 3, size, size], boxed.chw),
  }, [model.outputNames.first]);
  final raw = outputs[model.outputNames.first]!.floats!;

  // Stretched over the whole padded frame, matching the reference
  // implementation. The padding is a constant, so it can only widen the
  // range, never shift the relative ordering of real pixels.
  final stretched = _minMaxToBytes(raw, size * size);
  final cropped = _cropLetterbox(stretched, size, boxed);
  return AiMaskMap(
    width: width,
    height: height,
    data: _resizeGray(cropped, boxed.validWidth, boxed.validHeight, width, height),
  );
}

/// Estimates relative depth over a packed-RGB frame: 255 is the nearest
/// thing in the photo, 0 the farthest. Per-photo relative, never metric.
/// Same contract as [runSkyMaskModel].
AiMaskMap runDepthMapModel(Uint8List rgb, int width, int height) {
  final model = OnnxModel.forSpec(depthAnythingModelSpec);
  const size = 518;
  final boxed = _letterbox(rgb, width, height, size);

  final outputs = model.runGraph({
    model.inputNames.first: OnnxTensorData.float32([1, 3, size, size], boxed.chw),
  }, [model.outputNames.first]);
  // Rank-3 ([1, 518, 518]) rather than the rank-4 every other model here
  // returns — element count is the same, and the layout is the same rows.
  final raw = outputs[model.outputNames.first]!.floats!;

  // Unlike the segmentation models, the stretch here deliberately ignores
  // the padding: zero-padding normalizes to some arbitrary depth that is
  // frequently the frame's extreme, and letting it set an endpoint would
  // compress the real scene into part of the range and make the Near/Far
  // sliders mean different things on a 3:2 photo than on a square one.
  var min = double.infinity;
  var max = -double.infinity;
  for (var y = 0; y < boxed.validHeight; y++) {
    final row = (y + boxed.pasteY) * size + boxed.pasteX;
    for (var x = 0; x < boxed.validWidth; x++) {
      final v = raw[row + x];
      if (v < min) min = v;
      if (v > max) max = v;
    }
  }
  final range = max - min;
  final scale = range > 1e-6 ? 255.0 / range : 0.0;
  final cropped = Uint8List(boxed.validWidth * boxed.validHeight);
  for (var y = 0; y < boxed.validHeight; y++) {
    final srcRow = (y + boxed.pasteY) * size + boxed.pasteX;
    final dstRow = y * boxed.validWidth;
    for (var x = 0; x < boxed.validWidth; x++) {
      cropped[dstRow + x] = range > 1e-6
          ? ((raw[srcRow + x] - min) * scale).clamp(0.0, 255.0).toInt()
          : 0;
    }
  }
  return AiMaskMap(
    width: width,
    height: height,
    data: _resizeGray(cropped, boxed.validWidth, boxed.validHeight, width, height),
  );
}

/// Encodes a frame for [runSubjectMaskModel] — the slow half of Subject
/// detection, split out because it depends only on the photo, so
/// re-prompting a different part of the same photo reuses it (see
/// `ai_mask_cache.dart`).
///
/// Returns the raw 1x256x64x64 embedding. Same contract as
/// [runSkyMaskModel].
Float32List runSubjectEmbedding(Uint8List rgb, int width, int height) {
  final model = OnnxModel.forSpec(samEncoderModelSpec);
  final scale = _samInputSize / math.max(width, height);
  final scaledWidth = math.max(1, (width * scale).round());
  final scaledHeight = math.max(1, (height * scale).round());
  final resized = resizeRgbForAiMask(rgb, width, height, scaledWidth, scaledHeight);

  // Top-left aligned, zero-padded to the right and bottom — SAM's own
  // preprocessing, and what its coordinate prompts assume. Note the
  // tensor is uint8: this encoder does its own normalization internally.
  final chw = Uint8List(3 * _samInputSize * _samInputSize);
  const plane = _samInputSize * _samInputSize;
  for (var y = 0; y < scaledHeight; y++) {
    final srcRow = y * scaledWidth * 3;
    final dstRow = y * _samInputSize;
    for (var x = 0; x < scaledWidth; x++) {
      final src = srcRow + x * 3;
      final dst = dstRow + x;
      chw[dst] = resized[src];
      chw[plane + dst] = resized[src + 1];
      chw[2 * plane + dst] = resized[src + 2];
    }
  }

  final outputs = model.runGraph({
    model.inputNames.first: OnnxTensorData.uint8(
      [1, 3, _samInputSize, _samInputSize],
      chw,
    ),
  }, [model.outputNames.first]);
  return outputs[model.outputNames.first]!.floats!;
}

/// Turns an embedding from [runSubjectEmbedding] plus the user's box (or
/// click) into a subject mask at [width] x [height].
///
/// Runs the decoder twice. The first pass answers the user's prompt; the
/// second re-asks it with four prompts derived from that answer — the most
/// interior point of the mask as a positive, the most interior point of
/// the *background inside the mask's bounding box* as a negative, and the
/// box corners — plus the first mask as a prior. That second pass is what
/// stops a click on a shirt from selecting only the shirt, and it is why
/// the mask input is weighted by a Gaussian centred on the mask's deepest
/// point rather than passed through flat: the prior should be confident in
/// the middle and non-committal at the edges the second pass exists to
/// move.
///
/// Same contract as [runSkyMaskModel].
AiMaskMap runSubjectMaskModel(
  Float32List embedding,
  SubjectGeometry geometry,
  int width,
  int height,
) {
  final model = OnnxModel.forSpec(samDecoderModelSpec);
  final names = model.inputNames;
  if (names.length != 6) {
    throw StateError(
      'SAM decoder expected 6 inputs, got ${names.length}: $names',
    );
  }
  final scale = _samInputSize / math.max(width, height);

  // The prompt, in the encoder's 1024-space. Point prompts carry label 1
  // ("include this"); a box is its two corners with labels 2 and 3
  // ("top-left corner", "bottom-right corner") — SAM's own encoding.
  var coords = <double>[];
  var labels = <double>[];
  if (geometry.isPoint) {
    coords = [geometry.startX * width * scale, geometry.startY * height * scale];
    labels = [1];
  } else {
    final x1 = math.min(geometry.startX, geometry.endX) * width * scale;
    final y1 = math.min(geometry.startY, geometry.endY) * height * scale;
    final x2 = math.max(geometry.startX, geometry.endX) * width * scale;
    final y2 = math.max(geometry.startY, geometry.endY) * height * scale;
    coords = [x1, y1, x2, y2];
    labels = [2, 3];
  }

  var maskInput = Float32List(256 * 256);
  var hasMaskInput = 0.0;
  late Uint8List binaryMask;

  for (var pass = 0; pass < 2; pass++) {
    final pointCount = labels.length;
    final outputs = model.runGraph({
      names[0]: OnnxTensorData.float32([1, 256, 64, 64], embedding),
      names[1]: OnnxTensorData.float32(
        [1, pointCount, 2],
        Float32List.fromList(coords),
      ),
      names[2]: OnnxTensorData.float32(
        [1, pointCount],
        Float32List.fromList(labels),
      ),
      names[3]: OnnxTensorData.float32([1, 1, 256, 256], maskInput),
      names[4]: OnnxTensorData.float32([1], Float32List.fromList([hasMaskInput])),
      names[5]: OnnxTensorData.float32(
        [2],
        Float32List.fromList([height.toDouble(), width.toDouble()]),
      ),
    }, [model.outputNames.first]);

    // [1, masks, height, width] — the decoder returns several candidate
    // masks ranked by its own confidence; the first is the one it ranks
    // highest.
    final logits = outputs[model.outputNames.first]!.floats!;
    final area = width * height;
    binaryMask = Uint8List(area);
    var maskArea = 0;
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    for (var i = 0; i < area; i++) {
      if (logits[i] > 0) {
        binaryMask[i] = 1;
        maskArea++;
        final x = i % width;
        final y = i ~/ width;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    // Nothing selected: a second pass has no answer to refine and would
    // only feed the decoder an empty prior.
    if (pass == 1 || maskArea == 0) {
      break;
    }

    final inside = _distanceTransform(binaryMask, width, height, inside: true);
    var deepest = 0.0;
    var deepestIndex = 0;
    for (var i = 0; i < area; i++) {
      if (inside[i] > deepest) {
        deepest = inside[i];
        deepestIndex = i;
      }
    }

    // The strongest negative prompt available: the point *inside the
    // mask's own bounding box* that is farthest from the mask. Outside the
    // box it would just be some irrelevant corner of the photo.
    final outside = _distanceTransform(binaryMask, width, height, inside: false);
    var farthest = 0.0;
    var farthestIndex = 0;
    for (var y = minY; y <= maxY; y++) {
      final row = y * width;
      for (var x = minX; x <= maxX; x++) {
        final v = outside[row + x];
        if (v > farthest) {
          farthest = v;
          farthestIndex = row + x;
        }
      }
    }

    coords = [
      (deepestIndex % width) * scale,
      (deepestIndex ~/ width) * scale,
      (farthestIndex % width) * scale,
      (farthestIndex ~/ width) * scale,
      minX * scale,
      minY * scale,
      maxX * scale,
      maxY * scale,
    ];
    labels = [1, 0, 2, 3];

    // The prior: the mask as strong logits, faded out by a Gaussian on
    // distance-from-deepest-point so the decoder is told "certain here,
    // make up your own mind near the edges".
    final variance = math.max(maskArea / 4.0, 1.0);
    final weighted = Float32List(area);
    final logitMask = Float32List(area);
    for (var i = 0; i < area; i++) {
      logitMask[i] = binaryMask[i] == 1 ? 15.0 : -15.0;
      if (binaryMask[i] == 1) {
        final diff = inside[i] - deepest;
        weighted[i] = math.exp(-(diff * diff) / variance);
      }
    }
    final smallLogits = _resizeFloat(logitMask, width, height, 256, 256);
    final smallWeights = _resizeFloat(weighted, width, height, 256, 256);
    maskInput = Float32List(256 * 256);
    for (var i = 0; i < maskInput.length; i++) {
      final w = smallWeights[i] <= 0 ? 1.0 : smallWeights[i];
      maskInput[i] = smallLogits[i] * w;
    }
    hasMaskInput = 1.0;
  }

  final data = Uint8List(width * height);
  for (var i = 0; i < data.length; i++) {
    data[i] = binaryMask[i] == 1 ? 255 : 0;
  }
  // The decoder's output is a hard yes/no per pixel; a couple of pixels of
  // blur is what keeps the mask's edge from aliasing into a staircase once
  // an adjustment is applied through it.
  return AiMaskMap(
    width: width,
    height: height,
    data: _blurGray(data, width, height, 2),
  );
}

/// A frame resized to fit inside [size] x [size] with its aspect ratio
/// intact, centred, and normalized into a CHW float tensor.
class _Letterboxed {
  _Letterboxed({
    required this.chw,
    required this.validWidth,
    required this.validHeight,
    required this.pasteX,
    required this.pasteY,
  });

  final Float32List chw;
  final int validWidth;
  final int validHeight;
  final int pasteX;
  final int pasteY;
}

_Letterboxed _letterbox(Uint8List rgb, int width, int height, int size) {
  final ratio = math.min(size / width, size / height);
  final validWidth = math.max(1, math.min(size, (width * ratio).round()));
  final validHeight = math.max(1, math.min(size, (height * ratio).round()));
  final resized = resizeRgbForAiMask(rgb, width, height, validWidth, validHeight);
  final pasteX = (size - validWidth) ~/ 2;
  final pasteY = (size - validHeight) ~/ 2;

  final chw = Float32List(3 * size * size);
  final plane = size * size;
  for (var y = 0; y < validHeight; y++) {
    final srcRow = y * validWidth * 3;
    final dstRow = (y + pasteY) * size + pasteX;
    for (var x = 0; x < validWidth; x++) {
      final src = srcRow + x * 3;
      final dst = dstRow + x;
      for (var c = 0; c < 3; c++) {
        chw[c * plane + dst] =
            (resized[src + c] / 255.0 - _imagenetMean[c]) / _imagenetStd[c];
      }
    }
  }
  return _Letterboxed(
    chw: chw,
    validWidth: validWidth,
    validHeight: validHeight,
    pasteX: pasteX,
    pasteY: pasteY,
  );
}

/// Stretches [values] to fill 0..255. A model output is unnormalized
/// per-photo, so a fixed scale would render one photo's confident mask and
/// another's as a faint smear.
Uint8List _minMaxToBytes(Float32List values, int count) {
  var min = double.infinity;
  var max = -double.infinity;
  for (var i = 0; i < count; i++) {
    final v = values[i];
    if (v < min) min = v;
    if (v > max) max = v;
  }
  final range = max - min;
  final scale = range > 1e-6 ? 255.0 / range : 0.0;
  final out = Uint8List(count);
  if (range <= 1e-6) {
    return out;
  }
  for (var i = 0; i < count; i++) {
    out[i] = ((values[i] - min) * scale).clamp(0.0, 255.0).toInt();
  }
  return out;
}

Uint8List _cropLetterbox(Uint8List padded, int size, _Letterboxed box) {
  final out = Uint8List(box.validWidth * box.validHeight);
  for (var y = 0; y < box.validHeight; y++) {
    final srcRow = (y + box.pasteY) * size + box.pasteX;
    final dstRow = y * box.validWidth;
    for (var x = 0; x < box.validWidth; x++) {
      out[dstRow + x] = padded[srcRow + x];
    }
  }
  return out;
}

/// Packed-RGB resize, also used by `ai_mask_resolver.dart` to bring a
/// frame down to [aiMaskWorkingMaxDimension] before any model sees it.
/// Area-average when shrinking — which is the direction
/// everything here goes, and often by 10x or more, where plain bilinear
/// reads two of every twenty pixels and turns fine detail into noise —
/// bilinear when growing.
Uint8List resizeRgbForAiMask(Uint8List src, int sw, int sh, int dw, int dh) {
  if (sw == dw && sh == dh) {
    return src;
  }
  final out = Uint8List(dw * dh * 3);
  if (dw <= sw && dh <= sh) {
    final xScale = sw / dw;
    final yScale = sh / dh;
    for (var y = 0; y < dh; y++) {
      final y0 = (y * yScale).floor();
      final y1 = math.max(y0 + 1, ((y + 1) * yScale).ceil()).clamp(0, sh);
      for (var x = 0; x < dw; x++) {
        final x0 = (x * xScale).floor();
        final x1 = math.max(x0 + 1, ((x + 1) * xScale).ceil()).clamp(0, sw);
        var r = 0, g = 0, b = 0, n = 0;
        for (var sy = y0; sy < y1; sy++) {
          var idx = (sy * sw + x0) * 3;
          for (var sx = x0; sx < x1; sx++) {
            r += src[idx];
            g += src[idx + 1];
            b += src[idx + 2];
            idx += 3;
            n++;
          }
        }
        final dst = (y * dw + x) * 3;
        out[dst] = r ~/ n;
        out[dst + 1] = g ~/ n;
        out[dst + 2] = b ~/ n;
      }
    }
    return out;
  }
  final xScale = sw / dw;
  final yScale = sh / dh;
  for (var y = 0; y < dh; y++) {
    final sy = ((y + 0.5) * yScale - 0.5).clamp(0.0, sh - 1.0);
    final y0 = sy.floor();
    final y1 = math.min(y0 + 1, sh - 1);
    final wy = sy - y0;
    for (var x = 0; x < dw; x++) {
      final sx = ((x + 0.5) * xScale - 0.5).clamp(0.0, sw - 1.0);
      final x0 = sx.floor();
      final x1 = math.min(x0 + 1, sw - 1);
      final wx = sx - x0;
      final dst = (y * dw + x) * 3;
      for (var c = 0; c < 3; c++) {
        final top =
            src[(y0 * sw + x0) * 3 + c] * (1 - wx) +
            src[(y0 * sw + x1) * 3 + c] * wx;
        final bottom =
            src[(y1 * sw + x0) * 3 + c] * (1 - wx) +
            src[(y1 * sw + x1) * 3 + c] * wx;
        out[dst + c] = (top * (1 - wy) + bottom * wy).round().clamp(0, 255);
      }
    }
  }
  return out;
}

/// [_resizeRgb] for a single-channel map.
Uint8List _resizeGray(Uint8List src, int sw, int sh, int dw, int dh) {
  if (sw == dw && sh == dh) {
    return src;
  }
  final out = Uint8List(dw * dh);
  if (dw <= sw && dh <= sh) {
    final xScale = sw / dw;
    final yScale = sh / dh;
    for (var y = 0; y < dh; y++) {
      final y0 = (y * yScale).floor();
      final y1 = math.max(y0 + 1, ((y + 1) * yScale).ceil()).clamp(0, sh);
      for (var x = 0; x < dw; x++) {
        final x0 = (x * xScale).floor();
        final x1 = math.max(x0 + 1, ((x + 1) * xScale).ceil()).clamp(0, sw);
        var sum = 0, n = 0;
        for (var sy = y0; sy < y1; sy++) {
          final row = sy * sw;
          for (var sx = x0; sx < x1; sx++) {
            sum += src[row + sx];
            n++;
          }
        }
        out[y * dw + x] = sum ~/ n;
      }
    }
    return out;
  }
  final xScale = sw / dw;
  final yScale = sh / dh;
  for (var y = 0; y < dh; y++) {
    final sy = ((y + 0.5) * yScale - 0.5).clamp(0.0, sh - 1.0);
    final y0 = sy.floor();
    final y1 = math.min(y0 + 1, sh - 1);
    final wy = sy - y0;
    for (var x = 0; x < dw; x++) {
      final sx = ((x + 0.5) * xScale - 0.5).clamp(0.0, sw - 1.0);
      final x0 = sx.floor();
      final x1 = math.min(x0 + 1, sw - 1);
      final wx = sx - x0;
      final top = src[y0 * sw + x0] * (1 - wx) + src[y0 * sw + x1] * wx;
      final bottom = src[y1 * sw + x0] * (1 - wx) + src[y1 * sw + x1] * wx;
      out[y * dw + x] = (top * (1 - wy) + bottom * wy).round().clamp(0, 255);
    }
  }
  return out;
}

/// Bilinear resize of a float map — used only to shrink the decoder's own
/// full-size output down to the 256x256 prior it takes back, where the
/// values are logits and weights rather than pixels.
Float32List _resizeFloat(Float32List src, int sw, int sh, int dw, int dh) {
  final out = Float32List(dw * dh);
  final xScale = sw / dw;
  final yScale = sh / dh;
  for (var y = 0; y < dh; y++) {
    final sy = ((y + 0.5) * yScale - 0.5).clamp(0.0, sh - 1.0);
    final y0 = sy.floor();
    final y1 = math.min(y0 + 1, sh - 1);
    final wy = sy - y0;
    for (var x = 0; x < dw; x++) {
      final sx = ((x + 0.5) * xScale - 0.5).clamp(0.0, sw - 1.0);
      final x0 = sx.floor();
      final x1 = math.min(x0 + 1, sw - 1);
      final wx = sx - x0;
      final top = src[y0 * sw + x0] * (1 - wx) + src[y0 * sw + x1] * wx;
      final bottom = src[y1 * sw + x0] * (1 - wx) + src[y1 * sw + x1] * wx;
      out[y * dw + x] = top * (1 - wy) + bottom * wy;
    }
  }
  return out;
}

/// Exact Euclidean distance transform, Felzenszwalb & Huttenlocher's
/// two-pass algorithm: for every pixel, the distance to the nearest pixel
/// on the *other* side of [mask].
///
/// With [inside] true it measures how deep inside the mask each masked
/// pixel is (its deepest point is the most reliable place to put a
/// positive prompt); with [inside] false it measures the same for the
/// background. Exact rather than the usual chamfer approximation because
/// it costs one linear pass per axis either way.
Float32List _distanceTransform(
  Uint8List mask,
  int width,
  int height, {
  required bool inside,
}) {
  const far = 1e10;
  final f = Float32List(width * height);
  for (var i = 0; i < f.length; i++) {
    final on = mask[i] == 1;
    f[i] = (inside ? on : !on) ? far : 0.0;
  }

  final maxDim = math.max(width, height);
  final v = Int32List(maxDim);
  final z = Float32List(maxDim + 1);
  final d = Float32List(maxDim);
  final row = Float32List(maxDim);

  for (var y = 0; y < height; y++) {
    final start = y * width;
    for (var x = 0; x < width; x++) {
      row[x] = f[start + x];
    }
    _distanceTransform1d(row, width, v, z, d);
    for (var x = 0; x < width; x++) {
      f[start + x] = row[x];
    }
  }
  for (var x = 0; x < width; x++) {
    for (var y = 0; y < height; y++) {
      row[y] = f[y * width + x];
    }
    _distanceTransform1d(row, height, v, z, d);
    for (var y = 0; y < height; y++) {
      f[y * width + x] = row[y];
    }
  }
  for (var i = 0; i < f.length; i++) {
    f[i] = math.sqrt(f[i]);
  }
  return f;
}

/// One axis of [_distanceTransform]: the lower envelope of the parabolas
/// rooted at each sample, walked in a single pass.
void _distanceTransform1d(
  Float32List f,
  int n,
  Int32List v,
  Float32List z,
  Float32List d,
) {
  if (n == 0) {
    return;
  }
  var k = 0;
  v[0] = 0;
  z[0] = -double.infinity;
  z[1] = double.infinity;
  for (var q = 1; q < n; q++) {
    var s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * (q - v[k]));
    while (s <= z[k]) {
      if (k == 0) {
        break;
      }
      k--;
      s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * (q - v[k]));
    }
    k++;
    v[k] = q;
    z[k] = s;
    z[k + 1] = double.infinity;
  }
  k = 0;
  for (var q = 0; q < n; q++) {
    while (z[k + 1] < q) {
      k++;
    }
    final diff = (q - v[k]).toDouble();
    d[q] = diff * diff + f[v[k]];
  }
  for (var q = 0; q < n; q++) {
    f[q] = d[q];
  }
}

/// Separable box blur, run three times — the standard cheap stand-in for a
/// Gaussian, and indistinguishable from one at the two-pixel radius this
/// is used at.
Uint8List _blurGray(Uint8List src, int width, int height, int radius) {
  if (radius <= 0) {
    return src;
  }
  var current = src;
  for (var pass = 0; pass < 3; pass++) {
    current = _boxBlurAxis(current, width, height, radius, horizontal: true);
    current = _boxBlurAxis(current, width, height, radius, horizontal: false);
  }
  return current;
}

Uint8List _boxBlurAxis(
  Uint8List src,
  int width,
  int height,
  int radius, {
  required bool horizontal,
}) {
  final out = Uint8List(width * height);
  final outer = horizontal ? height : width;
  final inner = horizontal ? width : height;
  for (var o = 0; o < outer; o++) {
    for (var i = 0; i < inner; i++) {
      var sum = 0;
      var n = 0;
      for (var k = -radius; k <= radius; k++) {
        final s = (i + k).clamp(0, inner - 1);
        sum += horizontal ? src[o * width + s] : src[s * width + o];
        n++;
      }
      final value = sum ~/ n;
      if (horizontal) {
        out[o * width + i] = value;
      } else {
        out[i * width + o] = value;
      }
    }
  }
  return out;
}
