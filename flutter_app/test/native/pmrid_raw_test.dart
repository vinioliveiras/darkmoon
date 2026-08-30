import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/native/pmrid_raw.dart';

/// Builds a minimal synthetic `filters` bitmask that's correct at exactly
/// the four (row,col) positions `bayerColorAt`/`rggbAlignmentOffset` ever
/// query (row,col each in {0,1}) — real camera `filters` values encode an
/// 8-row-repeating pattern with a lot of redundant bits for period-4
/// backward compatibility (see LibRaw's own `FC()` macro), but nothing in
/// this codebase ever reads past row/col 1, so a real camera's exact
/// 32-bit value isn't needed to test this logic correctly.
int _buildFilters(int c00, int c01, int c10, int c11) =>
    (c00 & 3) | ((c01 & 3) << 2) | ((c10 & 3) << 4) | ((c11 & 3) << 6);

// R=0, G=1, B=2, G2=3 — matches packBayerToRggb01's own channel order
// (R, G, G2, B), the same convention PMRID's reference bayer2rggb assumes.
final _rggb = _buildFilters(0, 1, 3, 2); // c00=R, c01=G, c10=G2, c11=B
final _bggr = _buildFilters(2, 1, 3, 0); // B top-left, R bottom-right
final _grbg = _buildFilters(1, 0, 2, 3); // R top-right
final _gbrg = _buildFilters(1, 2, 0, 3); // R bottom-left

void main() {
  group('bayerColorAt / rggbAlignmentOffset', () {
    test('RGGB: R already at (0,0), no offset needed', () {
      expect(bayerColorAt(_rggb, 0, 0), 0);
      expect(bayerColorAt(_rggb, 0, 1), 1);
      expect(bayerColorAt(_rggb, 1, 0), 3);
      expect(bayerColorAt(_rggb, 1, 1), 2);
      expect(rggbAlignmentOffset(_rggb), (row: 0, col: 0));
    });

    test('BGGR: R sits at (1,1)', () {
      expect(bayerColorAt(_bggr, 1, 1), 0);
      expect(rggbAlignmentOffset(_bggr), (row: 1, col: 1));
    });

    test('GRBG: R sits at (0,1)', () {
      expect(bayerColorAt(_grbg, 0, 1), 0);
      expect(rggbAlignmentOffset(_grbg), (row: 0, col: 1));
    });

    test('GBRG: R sits at (1,0)', () {
      expect(bayerColorAt(_gbrg, 1, 0), 0);
      expect(rggbAlignmentOffset(_gbrg), (row: 1, col: 0));
    });

    test('a pattern with no R channel throws', () {
      // All-green — not a real sensor, just an invalid input to guard.
      final noRed = _buildFilters(1, 1, 1, 1);
      expect(() => rggbAlignmentOffset(noRed), throwsArgumentError);
    });
  });

  group('packBayerToRggb01 / unpackRggbIntoBayer', () {
    test('RGGB round-trip recovers the original values exactly', () {
      // 4x4 Bayer buffer = a single 2x2 CFA tile repeated, chosen so every
      // channel gets a distinct, easily-verified value.
      const width = 4;
      const height = 4;
      final bayer = Uint16List.fromList([
        1000, 2000, 1000, 2000, //
        3000, 4000, 3000, 4000, //
        1000, 2000, 1000, 2000, //
        3000, 4000, 3000, 4000, //
      ]);
      const black = 0;
      final cblack = [0, 0, 0, 0];
      const white = 4095.0;

      final rggb = packBayerToRggb01(bayer, width, height, _rggb, black, cblack, white);

      // 2x2 output blocks, 4 floats/pixel (R, G, G2, B).
      expect(rggb.length, 2 * 2 * 4);
      // Every block is identical here (the source tiles the same 2x2
      // pattern), so just check the first block's four channels.
      expect(rggb[0], closeTo(1000 / white, 1e-6)); // R
      expect(rggb[1], closeTo(2000 / white, 1e-6)); // G
      expect(rggb[2], closeTo(3000 / white, 1e-6)); // G2
      expect(rggb[3], closeTo(4000 / white, 1e-6)); // B

      final restored = Uint16List(width * height);
      unpackRggbIntoBayer(rggb, 2, 2, restored, width, _rggb, black, cblack, white);
      for (var i = 0; i < bayer.length; i++) {
        expect(restored[i], bayer[i], reason: 'mismatch at index $i');
      }
    });

    test('black level is subtracted before normalizing, and restored on unpack', () {
      const width = 2;
      const height = 2;
      final bayer = Uint16List.fromList([1100, 1200, 1300, 1400]);
      const black = 1000;
      final cblack = [0, 0, 0, 0];
      const white = 5095.0; // black + 4095, matching a real 12-bit sensor

      final rggb = packBayerToRggb01(bayer, width, height, _rggb, black, cblack, white);
      expect(rggb[0], closeTo(100 / 4095.0, 1e-6));
      expect(rggb[1], closeTo(200 / 4095.0, 1e-6));
      expect(rggb[2], closeTo(300 / 4095.0, 1e-6));
      expect(rggb[3], closeTo(400 / 4095.0, 1e-6));

      final restored = Uint16List(width * height);
      unpackRggbIntoBayer(rggb, 1, 1, restored, width, _rggb, black, cblack, white);
      for (var i = 0; i < bayer.length; i++) {
        expect(restored[i], closeTo(bayer[i].toDouble(), 1));
      }
    });

    test('values below black clamp to 0, not negative', () {
      const width = 2;
      const height = 2;
      // Every value below the black level (a real, if unusual, case for
      // sensor read noise near the floor).
      final bayer = Uint16List.fromList([500, 500, 500, 500]);
      const black = 1000;
      final cblack = [0, 0, 0, 0];
      const white = 5095.0;

      final rggb = packBayerToRggb01(bayer, width, height, _rggb, black, cblack, white);
      for (final v in rggb) {
        expect(v, 0.0);
      }
    });

    test(
      'BGGR (not already RGGB-aligned) crops a 1-pixel edge and leaves it '
      'untouched by unpack',
      () {
        const width = 4;
        const height = 4;
        final bayer = Uint16List.fromList([
          100, 101, 102, 103, //
          104, 105, 106, 107, //
          108, 109, 110, 111, //
          112, 113, 114, 115, //
        ]);
        const black = 0;
        final cblack = [0, 0, 0, 0];
        const white = 255.0;

        final offset = rggbAlignmentOffset(_bggr);
        expect(offset, (row: 1, col: 1));
        final rggb = packBayerToRggb01(bayer, width, height, _bggr, black, cblack, white);
        // Output is 1 row/col smaller than a fully-aligned sensor would
        // give at this size (3x3 active area after the 1-row/1-col crop,
        // not 4x4) -> floor((4-1)/2) = 1 block per axis.
        final outW = (width - offset.col) ~/ 2;
        final outH = (height - offset.row) ~/ 2;
        expect(rggb.length, outW * outH * 4);

        // Start from a COPY of the original buffer (unpack only touches
        // the aligned window) and confirm the untouched edge (row 0, and
        // column 0) keeps its original values.
        final restored = Uint16List.fromList(bayer);
        unpackRggbIntoBayer(
          rggb,
          outW,
          outH,
          restored,
          width,
          _bggr,
          black,
          cblack,
          white,
        );
        for (var x = 0; x < width; x++) {
          expect(restored[x], bayer[x], reason: 'row 0 should be untouched');
        }
        for (var y = 0; y < height; y++) {
          expect(
            restored[y * width],
            bayer[y * width],
            reason: 'column 0 should be untouched',
          );
        }
      },
    );
  });
}
