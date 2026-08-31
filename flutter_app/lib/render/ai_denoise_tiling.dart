import 'dart:typed_data';

/// Splits a full-resolution image into overlapping tiles, runs each
/// through [processTile] (a synchronous call — callers on the isolate
/// boundary wrap this whole function, not each tile individually), and
/// stitches the results back into one seamless image via a weighted
/// overlap-add blend.
///
/// Works uniformly for same-resolution models ([scaleFactor] 1, e.g. the
/// NAFNet-SIDD denoiser) and upscalers ([scaleFactor] 2+, e.g. DIS)
/// — the returned buffer is `width*scaleFactor` x `height*scaleFactor`.
///
/// [image] is packed, row-major, [channels] floats/pixel, normalized to
/// [0,1] (the convention `lib/native/onnx_runtime.dart`'s models expect —
/// see `tool/onnx_denoise_smoke_test.dart`'s validation notes). [channels]
/// defaults to 3 (RGB, the NAFNet-SIDD/DIS convention); the
/// raw-domain PMRID denoiser (`pmrid_denoise.dart`) is the one caller that
/// passes 4 (packed RGGB Bayer planes) instead.
///
/// Every tile fed to [processTile] is exactly [inputTileSize] x
/// `inputTileSize` — both vendored models require a fixed tile size (one
/// because its export is dynamic but this picks a fixed size for
/// predictable tile counts, the other because its export is *traced* at a
/// fixed size and can't take anything else) — see `OnnxModelSpec`'s doc
/// comment. Tiles step across the image by `inputTileSize - overlap`, so
/// [overlap] input pixels of each tile's edge are shared with its
/// neighbor; the corresponding `overlap * scaleFactor` output pixels are
/// cross-faded linearly between the two tiles' independently-computed
/// results rather than left as a hard seam.
///
/// The image is edge-clamp padded up to a whole number of tile steps
/// first (same boundary convention `blur.dart`'s box-blur helpers already
/// use), and that padding is cropped back off the stitched result at the
/// end — callers never see it.
Float32List denoiseTiled(
  Float32List image,
  int width,
  int height, {
  required Float32List Function(Float32List tile) processTile,
  required int inputTileSize,
  required int scaleFactor,
  int overlap = 16,
  int channels = 3,
  void Function(int tileIndex, int totalTiles)? onProgress,
}) {
  if (overlap >= inputTileSize) {
    throw ArgumentError(
      'overlap ($overlap) must be smaller than inputTileSize ($inputTileSize)',
    );
  }
  final step = inputTileSize - overlap;
  final tilesX = width <= inputTileSize
      ? 1
      : 1 + ((width - inputTileSize) / step).ceil();
  final tilesY = height <= inputTileSize
      ? 1
      : 1 + ((height - inputTileSize) / step).ceil();
  final paddedWidth = (tilesX - 1) * step + inputTileSize;
  final paddedHeight = (tilesY - 1) * step + inputTileSize;

  final padded = _edgeClampPad(
    image,
    width,
    height,
    paddedWidth,
    paddedHeight,
    channels,
  );

  final outputTileSize = inputTileSize * scaleFactor;
  final outPaddedWidth = paddedWidth * scaleFactor;
  final outPaddedHeight = paddedHeight * scaleFactor;
  final accum = Float32List(outPaddedWidth * outPaddedHeight * channels);
  final weightSum = Float32List(outPaddedWidth * outPaddedHeight);

  // A 1D ramp (0->1->0 shaped, flat 1 in the middle) applied separably on
  // each axis — the product of the two axes' ramps gives every pixel in a
  // tile a weight that's 1 in its core and tapers to 0 across the overlap
  // band shared with a neighbor, so summing overlapping tiles' weighted
  // contributions and dividing by the summed weight is a smooth cross-fade
  // with no visible seam. `edgeIsBoundary` keeps the ramp flat (weight 1)
  // on any side that's the true image edge, not a shared overlap — there's
  // no neighboring tile there to blend against, tapering that side would
  // just darken/soften the actual image border for no reason.
  final totalTiles = tilesX * tilesY;
  var tileIndex = 0;
  for (var ty = 0; ty < tilesY; ty++) {
    final y0 = ty * step;
    for (var tx = 0; tx < tilesX; tx++) {
      final x0 = tx * step;
      final inputTile = _extractTile(
        padded,
        paddedWidth,
        x0,
        y0,
        inputTileSize,
        channels,
      );
      final outputTile = processTile(inputTile);
      if (outputTile.length != outputTileSize * outputTileSize * channels) {
        throw StateError(
          'processTile returned ${outputTile.length} floats, expected '
          '${outputTileSize * outputTileSize * channels} '
          '($outputTileSize x $outputTileSize x $channels)',
        );
      }
      final ramp = _tileWeightRamp(
        size: inputTileSize,
        overlap: overlap,
        scaleFactor: scaleFactor,
        hasLeftNeighbor: tx > 0,
        hasRightNeighbor: tx < tilesX - 1,
        hasTopNeighbor: ty > 0,
        hasBottomNeighbor: ty < tilesY - 1,
      );
      _accumulateTile(
        accum,
        weightSum,
        outPaddedWidth,
        outputTile,
        ramp,
        x0 * scaleFactor,
        y0 * scaleFactor,
        outputTileSize,
        channels,
      );
      tileIndex++;
      onProgress?.call(tileIndex, totalTiles);
    }
  }

  final stitched = Float32List(outPaddedWidth * outPaddedHeight * channels);
  for (var p = 0; p < outPaddedWidth * outPaddedHeight; p++) {
    final w = weightSum[p];
    if (w <= 0) {
      // Only possible if a caller passes an inconsistent tile grid — every
      // real pixel is covered by at least one tile by construction.
      continue;
    }
    final i = p * channels;
    for (var c = 0; c < channels; c++) {
      stitched[i + c] = accum[i + c] / w;
    }
  }

  if (paddedWidth == width && paddedHeight == height) {
    return stitched;
  }
  return _crop(
    stitched,
    outPaddedWidth,
    width * scaleFactor,
    height * scaleFactor,
    channels,
  );
}

Float32List _edgeClampPad(
  Float32List image,
  int width,
  int height,
  int paddedWidth,
  int paddedHeight,
  int channels,
) {
  if (paddedWidth == width && paddedHeight == height) {
    return image;
  }
  final out = Float32List(paddedWidth * paddedHeight * channels);
  for (var y = 0; y < paddedHeight; y++) {
    final sy = y < height ? y : height - 1;
    for (var x = 0; x < paddedWidth; x++) {
      final sx = x < width ? x : width - 1;
      final si = (sy * width + sx) * channels;
      final di = (y * paddedWidth + x) * channels;
      for (var c = 0; c < channels; c++) {
        out[di + c] = image[si + c];
      }
    }
  }
  return out;
}

Float32List _extractTile(
  Float32List padded,
  int paddedWidth,
  int x0,
  int y0,
  int tileSize,
  int channels,
) {
  final tile = Float32List(tileSize * tileSize * channels);
  for (var y = 0; y < tileSize; y++) {
    final srcRowStart = ((y0 + y) * paddedWidth + x0) * channels;
    final dstRowStart = y * tileSize * channels;
    tile.setRange(
      dstRowStart,
      dstRowStart + tileSize * channels,
      padded,
      srcRowStart,
    );
  }
  return tile;
}

/// A `size*scaleFactor`-long 1D ramp: 1.0 across the core, linearly
/// tapering 0->1 over `overlap*scaleFactor` pixels at whichever ends have
/// a neighbor to blend with (flat 1.0 at any end that's a true image
/// boundary instead).
Float32List _axisRamp({
  required int size,
  required int overlap,
  required bool hasStartNeighbor,
  required bool hasEndNeighbor,
}) {
  final ramp = Float32List(size);
  for (var i = 0; i < size; i++) {
    var w = 1.0;
    if (hasStartNeighbor && i < overlap) {
      w = (i + 0.5) / overlap;
    }
    if (hasEndNeighbor && i >= size - overlap) {
      final fromEnd = size - 1 - i;
      w = w < (fromEnd + 0.5) / overlap ? w : (fromEnd + 0.5) / overlap;
    }
    ramp[i] = w.clamp(0.0, 1.0);
  }
  return ramp;
}

Float32List _tileWeightRamp({
  required int size,
  required int overlap,
  required int scaleFactor,
  required bool hasLeftNeighbor,
  required bool hasRightNeighbor,
  required bool hasTopNeighbor,
  required bool hasBottomNeighbor,
}) {
  final outSize = size * scaleFactor;
  final outOverlap = overlap * scaleFactor;
  final xRamp = _axisRamp(
    size: outSize,
    overlap: outOverlap,
    hasStartNeighbor: hasLeftNeighbor,
    hasEndNeighbor: hasRightNeighbor,
  );
  final yRamp = _axisRamp(
    size: outSize,
    overlap: outOverlap,
    hasStartNeighbor: hasTopNeighbor,
    hasEndNeighbor: hasBottomNeighbor,
  );
  final weight = Float32List(outSize * outSize);
  for (var y = 0; y < outSize; y++) {
    for (var x = 0; x < outSize; x++) {
      weight[y * outSize + x] = xRamp[x] * yRamp[y];
    }
  }
  return weight;
}

void _accumulateTile(
  Float32List accum,
  Float32List weightSum,
  int accumWidth,
  Float32List tile,
  Float32List weight,
  int dstX0,
  int dstY0,
  int tileSize,
  int channels,
) {
  for (var y = 0; y < tileSize; y++) {
    final dstY = dstY0 + y;
    for (var x = 0; x < tileSize; x++) {
      final dstX = dstX0 + x;
      final w = weight[y * tileSize + x];
      final dstP = dstY * accumWidth + dstX;
      final srcI = (y * tileSize + x) * channels;
      final dstI = dstP * channels;
      for (var c = 0; c < channels; c++) {
        accum[dstI + c] += tile[srcI + c] * w;
      }
      weightSum[dstP] += w;
    }
  }
}

Float32List _crop(
  Float32List src,
  int srcWidth,
  int outWidth,
  int outHeight,
  int channels,
) {
  final out = Float32List(outWidth * outHeight * channels);
  for (var y = 0; y < outHeight; y++) {
    final srcRowStart = (y * srcWidth) * channels;
    final dstRowStart = (y * outWidth) * channels;
    out.setRange(
      dstRowStart,
      dstRowStart + outWidth * channels,
      src,
      srcRowStart,
    );
  }
  return out;
}
