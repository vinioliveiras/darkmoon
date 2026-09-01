import 'dart:typed_data';

import 'lab_color.dart';

/// DDColor colorization (item 37, 2026-09-01) — ports `ddcolor/pipeline.py`'s
/// `ColorizationPipeline.process()` exactly (see `onnx_runtime.dart`'s
/// `ddcolorModelSpec` doc for why): only the L (luminance) channel of the
/// *original*, full-resolution photo ever gets used for the final output —
/// the network only ever sees a downscaled 512x512 version, predicting just
/// the 2 chroma (a/b) channels, which get bilinearly upsampled back onto the
/// full-res L. This means output quality is not limited by the model's
/// fixed working resolution the way a denoise/sharpen pass would be — same
/// "process chroma cheaply, keep luma full-res" principle
/// `baseline_chroma.dart` already uses elsewhere in this codebase, just
/// with a neural net making the chroma decision instead of a blur.
///
/// [rgbBytes] is packed, row-major, 3 bytes/pixel (0-255) — the same
/// convention `render.dart`'s buffers use. [runModel] is
/// [ddcolorModelSpec]'s `OnnxModel.runToChannels(tile, 2)`, dependency-
/// injected the same way `ai_enhance.dart`'s model callbacks are, so this
/// function itself has no FFI/native dependency. Blocking (one 512x512
/// inference plus two whole-image resizes); callers must run this on a
/// background isolate.
///
/// [intensity] (0.0-1.0, default full strength) scales the predicted a/b
/// channels *before* upsampling — 0 leaves the L channel alone (the
/// original grayscale/desaturated photo, byte-identical modulo rounding),
/// 1.0 is the model's raw prediction. Exists specifically to counter the
/// model's own real tendency to oversaturate (found testing real photos,
/// 2026-09-01 — see `onnx_runtime.dart`'s [ddcolorModelSpec] doc) — unlike
/// a plain output-image saturation slider, scaling in Lab a/b space dials
/// back exactly the color the network invented without touching the L
/// channel's real detail at all.
Uint8List colorizeImage(
  Uint8List rgbBytes,
  int width,
  int height, {
  required Float32List Function(Float32List tile) runModel,
  int modelInputSize = 512,
  double intensity = 1.0,
}) {
  // Full-resolution L channel — never touches the network, so the final
  // image keeps every bit of the original's real detail/sharpness.
  final fullL = Float32List(width * height);
  for (var i = 0; i < width * height; i++) {
    final lab = rgbToLab(
      rgbBytes[i * 3] / 255.0,
      rgbBytes[i * 3 + 1] / 255.0,
      rgbBytes[i * 3 + 2] / 255.0,
    );
    fullL[i] = lab.l;
  }

  // Downscale to the model's fixed working resolution, then rebuild a
  // "grayscale as RGB" tensor from *that* resolution's own L channel —
  // matches pipeline.py exactly (it re-derives L from the resized image,
  // not from downsampling the full-res L computed above).
  final smallRgb = _bilinearResizeRgbBytes(
    rgbBytes,
    width,
    height,
    modelInputSize,
    modelInputSize,
  );
  final grayRgbTile = Float32List(modelInputSize * modelInputSize * 3);
  for (var i = 0; i < modelInputSize * modelInputSize; i++) {
    final lab = rgbToLab(
      smallRgb[i * 3] / 255.0,
      smallRgb[i * 3 + 1] / 255.0,
      smallRgb[i * 3 + 2] / 255.0,
    );
    // Lab(L, 0, 0) -> RGB: a neutral-gray pixel at that lightness, same
    // as pipeline.py's `cv2.cvtColor(img_gray_lab, cv2.COLOR_LAB2RGB)`.
    final gray = labToRgb(lab.l, 0.0, 0.0);
    grayRgbTile[i * 3] = gray.r.clamp(0.0, 1.0);
    grayRgbTile[i * 3 + 1] = gray.g.clamp(0.0, 1.0);
    grayRgbTile[i * 3 + 2] = gray.b.clamp(0.0, 1.0);
  }

  // (2, modelInputSize, modelInputSize) packed as
  // modelInputSize*modelInputSize*2, interleaved a,b per pixel (matches
  // OnnxModel's usual packed-tile convention, not planar CHW — that
  // conversion happens inside OnnxModel._runTile/_unpackChw already).
  final abSmall = runModel(grayRgbTile);

  // Upsample just the 2 chroma channels back onto the full-res L.
  final abFull = _bilinearResizeChannels(
    abSmall,
    modelInputSize,
    modelInputSize,
    width,
    height,
    2,
  );

  final amount = intensity.clamp(0.0, 1.0);
  final outBytes = Uint8List(width * height * 3);
  for (var i = 0; i < width * height; i++) {
    final rgb = labToRgb(
      fullL[i],
      abFull[i * 2] * amount,
      abFull[i * 2 + 1] * amount,
    );
    outBytes[i * 3] = (rgb.r * 255.0).clamp(0, 255).round();
    outBytes[i * 3 + 1] = (rgb.g * 255.0).clamp(0, 255).round();
    outBytes[i * 3 + 2] = (rgb.b * 255.0).clamp(0, 255).round();
  }
  return outBytes;
}

/// `cv2.resize`'s default (`INTER_LINEAR`) half-pixel-center sampling —
/// `(dst + 0.5) * (srcSize/dstSize) - 0.5` — reproduced exactly rather
/// than using a different bilinear convention, so this matches the
/// reference Python pipeline's output, not just "a reasonable resize".
double _srcCoord(int dst, int dstSize, int srcSize) {
  final c = (dst + 0.5) * (srcSize / dstSize) - 0.5;
  return c < 0.0 ? 0.0 : c;
}

Uint8List _bilinearResizeRgbBytes(
  Uint8List src,
  int srcW,
  int srcH,
  int dstW,
  int dstH,
) {
  final out = Uint8List(dstW * dstH * 3);
  for (var dy = 0; dy < dstH; dy++) {
    final sy = _srcCoord(dy, dstH, srcH);
    final y0 = sy.floor().clamp(0, srcH - 1);
    final y1 = (y0 + 1).clamp(0, srcH - 1);
    final fy = sy - y0;
    for (var dx = 0; dx < dstW; dx++) {
      final sx = _srcCoord(dx, dstW, srcW);
      final x0 = sx.floor().clamp(0, srcW - 1);
      final x1 = (x0 + 1).clamp(0, srcW - 1);
      final fx = sx - x0;
      final di = (dy * dstW + dx) * 3;
      for (var c = 0; c < 3; c++) {
        final v00 = src[(y0 * srcW + x0) * 3 + c];
        final v01 = src[(y0 * srcW + x1) * 3 + c];
        final v10 = src[(y1 * srcW + x0) * 3 + c];
        final v11 = src[(y1 * srcW + x1) * 3 + c];
        final top = v00 + (v01 - v00) * fx;
        final bottom = v10 + (v11 - v10) * fx;
        out[di + c] = (top + (bottom - top) * fy).round().clamp(0, 255);
      }
    }
  }
  return out;
}

Float32List _bilinearResizeChannels(
  Float32List src,
  int srcW,
  int srcH,
  int dstW,
  int dstH,
  int channels,
) {
  final out = Float32List(dstW * dstH * channels);
  for (var dy = 0; dy < dstH; dy++) {
    final sy = _srcCoord(dy, dstH, srcH);
    final y0 = sy.floor().clamp(0, srcH - 1);
    final y1 = (y0 + 1).clamp(0, srcH - 1);
    final fy = sy - y0;
    for (var dx = 0; dx < dstW; dx++) {
      final sx = _srcCoord(dx, dstW, srcW);
      final x0 = sx.floor().clamp(0, srcW - 1);
      final x1 = (x0 + 1).clamp(0, srcW - 1);
      final fx = sx - x0;
      final di = (dy * dstW + dx) * channels;
      for (var c = 0; c < channels; c++) {
        final v00 = src[(y0 * srcW + x0) * channels + c];
        final v01 = src[(y0 * srcW + x1) * channels + c];
        final v10 = src[(y1 * srcW + x0) * channels + c];
        final v11 = src[(y1 * srcW + x1) * channels + c];
        final top = v00 + (v01 - v00) * fx;
        final bottom = v10 + (v11 - v10) * fx;
        out[di + c] = top + (bottom - top) * fy;
      }
    }
  }
  return out;
}
