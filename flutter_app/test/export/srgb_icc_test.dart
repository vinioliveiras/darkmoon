import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/export/srgb_icc.dart';
import 'package:flutter_test/flutter_test.dart';

// Parses the generated profile back the way a colour-management module
// would, so a byte-layout mistake fails here rather than as a viewer that
// quietly ignores the profile (or worse, misreads it).

String _sig(ByteData d, int at) =>
    String.fromCharCodes([for (var i = 0; i < 4; i++) d.getUint8(at + i)]);

double _s15(ByteData d, int at) => d.getInt32(at) / 65536.0;

void main() {
  final bytes = srgbIccProfile;
  final d = ByteData.sublistView(bytes);

  test('header: size, version, class, spaces, magic, PCS illuminant', () {
    expect(d.getUint32(0), bytes.length);
    expect(bytes.length % 4, 0);
    expect(d.getUint32(8) >> 24, 2, reason: 'major version 2');
    expect(_sig(d, 12), 'mntr');
    expect(_sig(d, 16), 'RGB ');
    expect(_sig(d, 20), 'XYZ ');
    expect(_sig(d, 36), 'acsp');
    expect(d.getUint32(64), 0, reason: 'perceptual intent');
    expect(_s15(d, 68), closeTo(0.9642, 1e-4));
    expect(_s15(d, 72), closeTo(1.0, 1e-4));
    expect(_s15(d, 76), closeTo(0.8249, 1e-4));
  });

  Map<String, (int, int)> tagTable() {
    final count = d.getUint32(128);
    final tags = <String, (int, int)>{};
    for (var i = 0; i < count; i++) {
      final at = 132 + i * 12;
      tags[_sig(d, at)] = (d.getUint32(at + 4), d.getUint32(at + 8));
    }
    return tags;
  }

  test('tag table names the nine tags a matrix/TRC profile needs, all '
      'inside the file and 4-byte aligned', () {
    final tags = tagTable();
    expect(tags.keys.toSet(), {
      'desc',
      'cprt',
      'wtpt',
      'rXYZ',
      'gXYZ',
      'bXYZ',
      'rTRC',
      'gTRC',
      'bTRC',
    });
    for (final entry in tags.entries) {
      final (offset, size) = entry.value;
      expect(offset % 4, 0, reason: '${entry.key} offset');
      expect(offset + size, lessThanOrEqualTo(bytes.length), reason: entry.key);
    }
  });

  test('primaries are the D50-adapted sRGB set and sum to the white point', () {
    final tags = tagTable();
    (double, double, double) xyz(String tag) {
      final (at, size) = tags[tag]!;
      expect(_sig(d, at), 'XYZ ');
      expect(size, 20);
      return (_s15(d, at + 8), _s15(d, at + 12), _s15(d, at + 16));
    }

    final r = xyz('rXYZ');
    final g = xyz('gXYZ');
    final b = xyz('bXYZ');
    final w = xyz('wtpt');
    expect(r.$1, closeTo(0.4361, 1e-3));
    expect(g.$2, closeTo(0.7169, 1e-3));
    expect(b.$3, closeTo(0.7141, 1e-3));
    expect(r.$1 + g.$1 + b.$1, closeTo(w.$1, 2e-3));
    expect(r.$2 + g.$2 + b.$2, closeTo(w.$2, 2e-3));
    expect(r.$3 + g.$3 + b.$3, closeTo(w.$3, 2e-3));
    expect(w.$2, closeTo(1.0, 1e-4));
  });

  test('the three TRCs share one curve that is the sRGB transfer function', () {
    final tags = tagTable();
    expect(tags['rTRC'], tags['gTRC']);
    expect(tags['gTRC'], tags['bTRC']);
    final (at, size) = tags['rTRC']!;
    expect(_sig(d, at), 'curv');
    final count = d.getUint32(at + 8);
    expect(count, 1024);
    expect(size, 12 + count * 2);
    var previous = -1;
    for (var i = 0; i < count; i++) {
      final v = d.getUint16(at + 12 + i * 2);
      expect(v, greaterThanOrEqualTo(previous), reason: 'monotone at $i');
      previous = v;
      final x = i / (count - 1);
      final expected =
          (x <= 0.04045 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4)) *
          65535.0;
      expect(v, closeTo(expected, 1.0), reason: 'sample $i');
    }
    expect(d.getUint16(at + 12), 0);
    expect(d.getUint16(at + 12 + (count - 1) * 2), 65535);
  });

  test('desc and cprt are readable text', () {
    final tags = tagTable();
    final (descAt, _) = tags['desc']!;
    expect(_sig(d, descAt), 'desc');
    final descLen = d.getUint32(descAt + 8);
    final desc = String.fromCharCodes(
      Uint8List.sublistView(bytes, descAt + 12, descAt + 12 + descLen - 1),
    );
    expect(desc, 'darkmoon sRGB');
    final (cprtAt, cprtSize) = tags['cprt']!;
    expect(_sig(d, cprtAt), 'text');
    expect(bytes[cprtAt + cprtSize - 1], 0, reason: 'null-terminated');
  });

  test('the profile is built once and is a few kilobytes', () {
    expect(identical(srgbIccProfile, srgbIccProfile), isTrue);
    expect(bytes.length, inInclusiveRange(2000, 4000));
  });
}
