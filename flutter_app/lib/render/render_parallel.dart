import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'render.dart';
import 'render_params.dart';

/// Below this many pixels, splitting into bands and spawning isolates
/// costs more (isolate startup, copying each band's data across) than it
/// saves — the live-drag preview buffer (usually well under a megapixel)
/// stays on the plain serial path in [renderRgb]; this only pays off for
/// the settled full-resolution render.
const int _parallelPixelThreshold = 1500000;

/// A band's real (non-halo) content must be at least this many rows, and
/// at least 3x its own halo — otherwise more bands just means more
/// halo-overlap redundancy without meaningfully more real parallel work
/// (in the extreme, a band shorter than its own halo would spend more
/// time on overlap than on rows it's actually responsible for).
const int _minBandContentHeight = 64;

/// The parallel counterpart to `renderRgb(...).call(applyLocalAdjustmentSteps)`
/// — same pixel-for-pixel result, computed by splitting the image into
/// independent horizontal bands (each padded with [localAdjustmentHaloPx]
/// extra rows so blur-based steps near a seam still see the right
/// neighboring pixels) and running [applyLocalAdjustmentSteps] on each in
/// its own isolate, concurrently. [applyGlobalAdjustmentSteps] (Dehaze
/// chief among them — see its doc comment) runs once afterward on the
/// complete, stitched-back-together buffer, same as the serial path.
///
/// Falls back to running both steps serially, on the whole image at once
/// (no bands, no isolates), below [_parallelPixelThreshold] or when the
/// machine/image can't usefully support more than one band — the same
/// result either way, just without paying isolate overhead where it
/// wouldn't be recovered.
Future<Uint8List> renderAdjustmentsParallel(
  int width,
  int height,
  Uint8List sourceRgb,
  RenderParams params, {
  List<String>? timings,
}) async {
  final sw = Stopwatch()..start();
  void mark(String stage) {
    timings?.add('$stage ${sw.elapsedMilliseconds}ms');
    sw.reset();
  }

  final buffer = Float32List(sourceRgb.length);
  for (var i = 0; i < sourceRgb.length; i++) {
    buffer[i] = sourceRgb[i].toDouble();
  }

  final pixelCount = width * height;
  final halo = localAdjustmentHaloPx(params);
  final bandCount = pixelCount < _parallelPixelThreshold
      ? 1
      : _pickBandCount(height, halo, Platform.numberOfProcessors);
  mark('setup (${Platform.numberOfProcessors} cpu, $bandCount bands)');

  if (bandCount <= 1) {
    applyLocalAdjustmentSteps(buffer, width, height, params);
    mark('local (serial)');
    applyGlobalAdjustmentSteps(buffer, width, height, params);
    mark('global (serial)');
    return _toUint8(buffer);
  }

  final bandHeight = (height / bandCount).ceil();
  final futures = <Future<Float32List>>[];
  final bandStarts = <int>[];
  final bandEnds = <int>[];
  for (var b = 0; b < bandCount; b++) {
    final y0 = b * bandHeight;
    final y1 = math.min(y0 + bandHeight, height);
    if (y0 >= y1) {
      break;
    }
    bandStarts.add(y0);
    bandEnds.add(y1);

    final paddedTop = math.max(y0 - halo, 0);
    final paddedBottom = math.min(y1 + halo, height);
    final paddedRowCount = paddedBottom - paddedTop;
    final trimTop = y0 - paddedTop;
    final trimBottom = trimTop + (y1 - y0);
    // A view into the parent buffer — Isolate.run copies whatever a
    // captured TypedData logically contains (respecting this view's own
    // offset/length, not the whole backing buffer it shares with every
    // other band) when it ships the closure to the new isolate, so this
    // doesn't need its own explicit intermediate copy first.
    final paddedSlice = Float32List.sublistView(
      buffer,
      paddedTop * width * 3,
      paddedBottom * width * 3,
    );
    futures.add(
      Isolate.run(() {
        applyLocalAdjustmentSteps(
          paddedSlice,
          width,
          paddedRowCount,
          params,
          rowOffset: paddedTop,
        );
        return Float32List.sublistView(
          paddedSlice,
          trimTop * width * 3,
          trimBottom * width * 3,
        );
      }),
    );
  }

  final results = await Future.wait(futures);
  for (var b = 0; b < results.length; b++) {
    buffer.setRange(
      bandStarts[b] * width * 3,
      bandEnds[b] * width * 3,
      results[b],
    );
  }
  mark('local ($bandCount bands)');

  // Exposure + Dehaze: whole-image is just an O(n) multiply when Dehaze is
  // off; band it (Dehaze's sigma-40 blur needs a halo) when it's on.
  final dehazeHalo = exposureDehazeHaloPx(params);
  if (dehazeHalo == 0 || bandCount <= 1) {
    applyExposureWhiteBalanceAndDehaze(buffer, width, height, params);
  } else {
    await _bandPass(
      width,
      height,
      buffer,
      bandCount,
      dehazeHalo,
      (slice, w, h, top) =>
          applyExposureWhiteBalanceAndDehaze(slice, w, h, params),
    );
  }
  mark('exposure+dehaze');

  // The point-op half — the pow()-heavy majority of a full-res render — in
  // bands, converting each band straight to bytes so there's no separate
  // full-image float->uint8 pass afterward.
  final ppHalo = globalPointOpsHaloPx(params);
  final Uint8List out;
  if (bandCount <= 1) {
    applyGlobalPointOps(buffer, width, height, params, fullHeight: height);
    out = _toUint8(buffer);
  } else {
    out = Uint8List(width * height * 3);
    final futures2 = <Future<({int y0, Uint8List data, List<String>? sub})>>[];
    final bandHeight = (height / bandCount).ceil();
    for (var b = 0; b < bandCount; b++) {
      final y0 = b * bandHeight;
      final y1 = math.min(y0 + bandHeight, height);
      if (y0 >= y1) {
        break;
      }
      final paddedTop = math.max(y0 - ppHalo, 0);
      final paddedBottom = math.min(y1 + ppHalo, height);
      final trimTop = y0 - paddedTop;
      final trimRows = y1 - y0;
      final paddedSlice = Float32List.sublistView(
        buffer,
        paddedTop * width * 3,
        paddedBottom * width * 3,
      );
      // Temporary diagnostic: only band 0 collects a per-stage breakdown
      // (representative sample — bands are near-equal in size) so the
      // "point-ops + bytes" total above can be narrowed down further; see
      // `_showExportTimings` in editor_screen.dart.
      final wantSubTimings = timings != null && b == 0;
      futures2.add(
        Isolate.run(() {
          final sub = wantSubTimings ? <String>[] : null;
          applyGlobalPointOps(
            paddedSlice,
            width,
            paddedBottom - paddedTop,
            params,
            rowOffset: paddedTop,
            fullHeight: height,
            subTimings: sub,
          );
          final byteSw = sub == null ? null : (Stopwatch()..start());
          final start = trimTop * width * 3;
          final bytes = Uint8List(trimRows * width * 3);
          for (var i = 0; i < bytes.length; i++) {
            bytes[i] = paddedSlice[start + i].clamp(0.0, 255.0).round();
          }
          if (byteSw != null) {
            sub!.add('bytes ${byteSw.elapsedMilliseconds}ms');
          }
          return (y0: y0, data: bytes, sub: sub);
        }),
      );
    }
    for (final r in await Future.wait(futures2)) {
      out.setRange(r.y0 * width * 3, r.y0 * width * 3 + r.data.length, r.data);
      if (r.sub != null) {
        timings!.add('  band0 breakdown: ${r.sub!.join(' · ')}');
      }
    }
  }
  mark('point-ops + bytes ($bandCount bands)');
  return out;
}

/// Runs [op] (which mutates its slice in place) on [buffer] split into
/// [bandCount] horizontal bands, each padded with [halo] extra rows top
/// and bottom, then writes the trimmed (non-overlap) result back.
Future<void> _bandPass(
  int width,
  int height,
  Float32List buffer,
  int bandCount,
  int halo,
  void Function(Float32List slice, int w, int h, int rowOffset) op,
) async {
  final bandHeight = (height / bandCount).ceil();
  final futures = <Future<({int y0, int y1, Float32List data})>>[];
  for (var b = 0; b < bandCount; b++) {
    final y0 = b * bandHeight;
    final y1 = math.min(y0 + bandHeight, height);
    if (y0 >= y1) {
      break;
    }
    final paddedTop = math.max(y0 - halo, 0);
    final paddedBottom = math.min(y1 + halo, height);
    final trimTop = y0 - paddedTop;
    final trimBottom = trimTop + (y1 - y0);
    final paddedSlice = Float32List.sublistView(
      buffer,
      paddedTop * width * 3,
      paddedBottom * width * 3,
    );
    futures.add(
      Isolate.run(() {
        op(paddedSlice, width, paddedBottom - paddedTop, paddedTop);
        return (
          y0: y0,
          y1: y1,
          data: Float32List.sublistView(
            paddedSlice,
            trimTop * width * 3,
            trimBottom * width * 3,
          ),
        );
      }),
    );
  }
  for (final r in await Future.wait(futures)) {
    buffer.setRange(r.y0 * width * 3, r.y1 * width * 3, r.data);
  }
}

int _pickBandCount(int height, int halo, int cores) {
  if (cores < 2) {
    return 1;
  }
  final minContentPerBand = math.max(_minBandContentHeight, halo * 3);
  final maxUsefulBands = height ~/ minContentPerBand;
  if (maxUsefulBands < 1) {
    return 1;
  }
  return math.min(cores, maxUsefulBands);
}

Uint8List _toUint8(Float32List buffer) {
  final out = Uint8List(buffer.length);
  for (var i = 0; i < buffer.length; i++) {
    out[i] = buffer[i].clamp(0.0, 255.0).round();
  }
  return out;
}
