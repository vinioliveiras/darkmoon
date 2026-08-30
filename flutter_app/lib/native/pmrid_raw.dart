import 'dart:typed_data';

/// Pure Bayer-buffer math for the PMRID raw-domain denoiser
/// (`render/pmrid_denoise.dart`) — no FFI here, so it's directly
/// unit-testable; `libraw.dart`'s `decodeRawImageWithPmridDenoise` is the
/// only caller, and owns all the native pointer reads/writes around it.

/// LibRaw/dcraw's own `FC(row,col)` macro: which of R(0)/G(1)/B(2)/G2(3) a
/// given sensor position holds, decoded from the packed `filters` bitmask
/// LibRaw exposes for ordinary Bayer sensors (`lr.ref.idata.filters`) —
/// NOT valid for X-Trans (`filters == 9`) or Foveon (`filters == 0`)
/// sensors, which use entirely different CFA layouts; callers must check
/// for those sentinels before calling anything in this file.
int bayerColorAt(int filters, int row, int col) =>
    (filters >> ((((row << 1) & 14) + (col & 1)) << 1)) & 3;

/// The (row, col) offset in {0,1}x{0,1} at which the sensor's repeating
/// 2x2 CFA tile carries the R channel — i.e. how many rows/cols to skip
/// from a raw buffer's top-left corner so that packing 2x2 blocks starting
/// there lands on PMRID's assumed RGGB scan order (top-left=R,
/// top-right=G, bottom-left=G2, bottom-right=B) without a per-pixel color
/// lookup. Every standard Bayer CFA (RGGB/BGGR/GRBG/GBRG) has exactly one
/// such offset — a camera whose sensor isn't already RGGB-aligned (e.g.
/// BGGR) loses at most a 1-pixel edge strip, packed at its original
/// (un-denoised) value by [unpackRggbIntoBayer].
({int row, int col}) rggbAlignmentOffset(int filters) {
  for (var dr = 0; dr < 2; dr++) {
    for (var dc = 0; dc < 2; dc++) {
      if (bayerColorAt(filters, dr, dc) == 0) {
        return (row: dr, col: dc);
      }
    }
  }
  throw ArgumentError(
    'CFA pattern (filters=$filters) has no R channel in its 2x2 tile — '
    'not a standard Bayer sensor (X-Trans/Foveon aren\'t supported)',
  );
}

/// Per-color (R/G/B/G2, indexed by [bayerColorAt]'s return value) black
/// level: LibRaw's convention is a shared base ([blackBase], `color.black`)
/// plus a per-channel addition ([cblack], `color.cblack[0..3]`).
List<double> combinedBlackLevels(int blackBase, List<int> cblack) => [
  for (var c = 0; c < 4; c++) (blackBase + cblack[c]).toDouble(),
];

/// Normalizes a raw Bayer buffer to [0,1] (black-subtracted, divided by
/// `whiteLevel` minus the darkest channel's black level — a single shared
/// denominator, not a per-channel one, so every channel's [0,1] scale
/// stays directly comparable) and packs it into PMRID's 4-channel RGGB
/// layout in one pass.
///
/// [bayer] is raw sensor values, packed, row-major, 1 ushort/pixel,
/// [width] x [height] (both must be even — callers crop to even dims
/// first, same convention LibRaw's own `sizes.width`/`height` already
/// need for demosaic). Output is `((width - offset.col) ~/ 2)` x
/// `((height - offset.row) ~/ 2)`, 4 floats/pixel — see
/// [rggbAlignmentOffset] for why the output can be up to 1 row/col smaller
/// than `width/2 x height/2`.
Float32List packBayerToRggb01(
  Uint16List bayer,
  int width,
  int height,
  int filters,
  int blackBase,
  List<int> cblack,
  double whiteLevel,
) {
  final black = combinedBlackLevels(blackBase, cblack);
  final denom = whiteLevel - black.reduce((a, b) => a < b ? a : b);
  final offset = rggbAlignmentOffset(filters);
  final outW = (width - offset.col) ~/ 2;
  final outH = (height - offset.row) ~/ 2;
  final out = Float32List(outW * outH * 4);
  for (var by = 0; by < outH; by++) {
    final row = offset.row + by * 2;
    final rowBelow = row + 1;
    for (var bx = 0; bx < outW; bx++) {
      final col = offset.col + bx * 2;
      final o = (by * outW + bx) * 4;
      out[o] = ((bayer[row * width + col] - black[0]) / denom).clamp(0.0, 1.0);
      out[o + 1] = ((bayer[row * width + col + 1] - black[1]) / denom).clamp(0.0, 1.0);
      out[o + 2] = ((bayer[rowBelow * width + col] - black[3]) / denom).clamp(0.0, 1.0);
      out[o + 3] = ((bayer[rowBelow * width + col + 1] - black[2]) / denom).clamp(0.0, 1.0);
    }
  }
  return out;
}

/// Inverse of [packBayerToRggb01]: denormalizes PMRID's denoised RGGB
/// output and writes it back into [bayer] in place, at the same
/// [rggbAlignmentOffset]-shifted positions [packBayerToRggb01] read from.
/// Any pixel(s) outside that aligned window (the up-to-1-row/col edge
/// strip a non-RGGB-aligned CFA loses) are left untouched, keeping
/// whatever original sensor value [bayer] already held there.
void unpackRggbIntoBayer(
  Float32List rggb,
  int outW,
  int outH,
  Uint16List bayer,
  int width,
  int filters,
  int blackBase,
  List<int> cblack,
  double whiteLevel,
) {
  final black = combinedBlackLevels(blackBase, cblack);
  final denom = whiteLevel - black.reduce((a, b) => a < b ? a : b);
  final offset = rggbAlignmentOffset(filters);
  for (var by = 0; by < outH; by++) {
    final row = offset.row + by * 2;
    final rowBelow = row + 1;
    for (var bx = 0; bx < outW; bx++) {
      final col = offset.col + bx * 2;
      final o = (by * outW + bx) * 4;
      bayer[row * width + col] = _toRawValue(rggb[o], denom, black[0]);
      bayer[row * width + col + 1] = _toRawValue(rggb[o + 1], denom, black[1]);
      bayer[rowBelow * width + col] = _toRawValue(rggb[o + 2], denom, black[3]);
      bayer[rowBelow * width + col + 1] = _toRawValue(rggb[o + 3], denom, black[2]);
    }
  }
}

int _toRawValue(double normalized01, double denom, double black) =>
    (normalized01 * denom + black).round().clamp(0, 65535);
