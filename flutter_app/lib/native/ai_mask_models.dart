import 'dart:math' as math;
import 'dart:typed_data';

import '../render/mask.dart';
import 'onnx_runtime.dart';

/// Long side every AI mask map is computed and cached at.
///
/// The models all resize their input down to a few hundred pixels anyway
/// (320 for the U-2-Nets, 518 for depth), so inferring on a 24 MP frame
/// buys nothing but memory traffic. `computeMaskAlpha` rescales the map to
/// the render's real dimensions, which is what every other mask type does
/// with its own normalized geometry anyway.
const int aiMaskWorkingMaxDimension = 1024;

/// ImageNet channel statistics — the normalization all three float-input
/// models here were trained with.
const List<double> _imagenetMean = [0.485, 0.456, 0.406];
const List<double> _imagenetStd = [0.229, 0.224, 0.225];

/// Stretches a frame's tonal range to fill 0..255 before any model sees
/// it — one scale for all three channels, taken from luma, so the range
/// opens up without shifting a hue (a per-channel stretch would
/// white-balance the photo as a side effect).
///
/// This exists because of what the models are shown. The frame they get is
/// the decoded source: LibRaw's output with lens correction and crop, and
/// none of the app's tone work, which lives downstream in the render. On a
/// RAW that image is flat and often dark, and every model here was trained
/// on ordinary photographs with a full tonal range — so it is being asked
/// about a kind of image it never saw.
///
/// Measured 2026-09-08 across three of the user's RAWs, against both the
/// untouched source and the neutral render as alternatives. Sky is the
/// clearest case: on a night street scene the sky map went from 12.2%
/// coverage with 8.7% of the map undecided (neither in nor out) to 13.2%
/// with 1.5% undecided, while the same photo through the neutral render
/// collapsed to 1.8%. On a hazy daylight RAW, sky went from 8.5%/7.9% to
/// 10.8%/2.8%. Foreground improved or held on all three. The neutral
/// render won one of those cases and lost another badly, and would have
/// tied every cached map to the user's own edits besides; this asks only
/// that the photo have a full range, which is the one thing every training
/// set had in common.
Uint8List autoLevelForAiMask(Uint8List rgb) {
  final histogram = List<int>.filled(256, 0);
  for (var i = 0; i < rgb.length; i += 3) {
    histogram[(rgb[i] * 299 + rgb[i + 1] * 587 + rgb[i + 2] * 114) ~/ 1000]++;
  }
  final total = rgb.length ~/ 3;
  // 1% clipped off each end, so a handful of blown highlights or a black
  // frame border can't decide the whole stretch. Floored at one pixel:
  // at zero the search below matches before consuming any bin at all and
  // reports black as the low end of every frame, which on a flat frame
  // turns a no-op into a full-contrast stretch of its own noise.
  final lowTarget = math.max(1, total ~/ 100);
  final highTarget = math.max(1, total - total ~/ 100);
  var low = 0;
  var high = 255;
  var seen = 0;
  for (var v = 0; v < 256; v++) {
    seen += histogram[v];
    if (seen >= lowTarget) {
      low = v;
      break;
    }
  }
  seen = 0;
  for (var v = 0; v < 256; v++) {
    seen += histogram[v];
    if (seen >= highTarget) {
      high = v;
      break;
    }
  }
  // So nearly flat that stretching would amplify noise into structure the
  // model would then confidently mis-segment. A frame that already fills
  // the range still gets its 1% tails clipped, which is the point of
  // percentiles rather than the plain min and max.
  if (high - low < 8) {
    return rgb;
  }
  final scale = 255.0 / (high - low);
  final out = Uint8List(rgb.length);
  for (var i = 0; i < rgb.length; i++) {
    out[i] = ((rgb[i] - low) * scale).clamp(0.0, 255.0).toInt();
  }
  return out;
}

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
  final raw = outputs[model.outputNames.first]!.floats;

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
  final raw = outputs[model.outputNames.first]!.floats;

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
