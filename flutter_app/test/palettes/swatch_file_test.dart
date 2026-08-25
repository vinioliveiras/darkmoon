import 'dart:typed_data';

import 'package:darkmoon/palettes/swatch_file.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal one-entry .ase file with a single RGB color block,
/// matching the real Adobe Swatch Exchange binary layout byte-for-byte
/// (signature/version/block-count header, then one 0x0001 color block).
Uint8List _buildAse({
  required String name,
  required double r,
  required double g,
  required double b,
}) {
  final nameUnits = [...name.codeUnits, 0]; // null-terminated, per spec
  final nameBytes = nameUnits.length * 2;
  // nameLen(2) + name + colorModel(4) + 3 floats(12) + colorType(2)
  final blockLength = 2 + nameBytes + 4 + 12 + 2;
  final totalLength = 12 + 6 + blockLength;
  final bytes = ByteData(totalLength);
  var o = 0;
  bytes.setUint8(o++, 0x41); // 'A'
  bytes.setUint8(o++, 0x53); // 'S'
  bytes.setUint8(o++, 0x45); // 'E'
  bytes.setUint8(o++, 0x46); // 'F'
  bytes.setUint16(o, 1);
  o += 2; // version major
  bytes.setUint16(o, 0);
  o += 2; // version minor
  bytes.setUint32(o, 1);
  o += 4; // numBlocks
  bytes.setUint16(o, 0x0001);
  o += 2; // block type: color entry
  bytes.setUint32(o, blockLength);
  o += 4;
  bytes.setUint16(o, nameUnits.length);
  o += 2;
  for (final unit in nameUnits) {
    bytes.setUint16(o, unit);
    o += 2;
  }
  for (final ch in 'RGB '.codeUnits) {
    bytes.setUint8(o++, ch);
  }
  bytes.setFloat32(o, r);
  o += 4;
  bytes.setFloat32(o, g);
  o += 4;
  bytes.setFloat32(o, b);
  o += 4;
  bytes.setUint16(o, 0);
  o += 2; // color type: global
  return bytes.buffer.asUint8List();
}

/// Builds a minimal one-entry, version-2 (named) .aco file with a single
/// RGB color entry.
Uint8List _buildAco({required String name, required int r, required int g, required int b}) {
  final nameUnits = [...name.codeUnits, 0];
  final totalLength = 4 + (10 * 1) + 4 + nameUnits.length * 2;
  final bytes = ByteData(totalLength);
  var o = 0;
  bytes.setUint16(o, 2);
  o += 2; // version 2
  bytes.setUint16(o, 1);
  o += 2; // count
  bytes.setUint16(o, 0);
  o += 2; // colorSpace: RGB
  bytes.setUint16(o, r);
  o += 2;
  bytes.setUint16(o, g);
  o += 2;
  bytes.setUint16(o, b);
  o += 2;
  bytes.setUint16(o, 0);
  o += 2; // unused 4th component
  bytes.setUint32(o, nameUnits.length);
  o += 4;
  for (final unit in nameUnits) {
    bytes.setUint16(o, unit);
    o += 2;
  }
  return bytes.buffer.asUint8List();
}

void main() {
  group('parseAse', () {
    test('reads a named RGB color entry', () {
      final bytes = _buildAse(name: 'Herb Green', r: 0.3, g: 0.6, b: 0.1);
      final swatches = parseAse(bytes);
      expect(swatches, hasLength(1));
      expect(swatches.single.name, 'Herb Green');
      expect(swatches.single.rgb, (77 << 16) | (153 << 8) | 26);
    });

    test('rejects a file with the wrong signature', () {
      final bytes = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
      expect(parseAse(bytes), isEmpty);
    });

    test('falls back to a hex name when the entry name is empty', () {
      final bytes = _buildAse(name: '', r: 1, g: 1, b: 1);
      final swatches = parseAse(bytes);
      expect(swatches.single.name, '#ffffff');
      expect(swatches.single.rgb, 0xffffff);
    });
  });

  group('parseAco', () {
    test('reads a named RGB color entry from a version-2 block', () {
      final bytes = _buildAco(name: 'Sky Blue', r: 20000, g: 40000, b: 65535);
      final swatches = parseAco(bytes);
      expect(swatches, hasLength(1));
      expect(swatches.single.name, 'Sky Blue');
      // 16-bit components scale down to 0..255 (65535 -> 255 exactly).
      expect(swatches.single.rgb & 0xFF, 255);
    });

    test('returns an empty list for truncated/invalid data', () {
      expect(parseAco(Uint8List.fromList([1, 2])), isEmpty);
    });
  });

  group('parseSwatchFile', () {
    test('dispatches on extension', () {
      final aseBytes = _buildAse(name: 'X', r: 1, g: 0, b: 0);
      expect(parseSwatchFile('/tmp/palette.ase', aseBytes), hasLength(1));
      expect(parseSwatchFile('/tmp/palette.ASE', aseBytes), hasLength(1));
      expect(parseSwatchFile('/tmp/palette.gpl', aseBytes), isNull);
    });
  });
}
