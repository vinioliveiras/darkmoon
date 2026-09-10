import 'dart:math' as math;
import 'dart:typed_data';

/// An sRGB ICC profile, built here rather than shipped as a file.
///
/// Every pixel this app writes is sRGB, and a file with no profile is
/// *assumed* sRGB by nearly every viewer — but "assumed" is not "stated",
/// and colour-managed software (browsers on wide-gamut displays, print
/// pipelines, Lightroom's own import) treats a tagged file with more
/// confidence than an untagged one. The profile is a plain ICC v2
/// display-class matrix/TRC profile: the D50-adapted sRGB primaries, the
/// D50 white point, and the IEC 61966-2-1 transfer curve sampled at 1024
/// points. Generated on first use and cached; about 2.3 KB.
///
/// Written from the ICC.1:2001-04 (v2) specification, so nothing here is a
/// redistribution of anyone's profile file and no licence rides along.
final Uint8List srgbIccProfile = _buildSrgbProfile();

/// The name PNG's iCCP chunk and the like carry beside the bytes.
const String srgbIccProfileName = 'sRGB';

// D50-adapted sRGB primaries (Bradford), as every sRGB v2 profile carries
// them; they sum to the D50 white point below.
const _rXyz = (0.43607, 0.22249, 0.01392);
const _gXyz = (0.38515, 0.71687, 0.09708);
const _bXyz = (0.14307, 0.06061, 0.71410);
const _d50 = (0.96420, 1.00000, 0.82491);

const _trcSamples = 1024;

Uint8List _buildSrgbProfile() {
  final desc = _textDescription('darkmoon sRGB');
  final cprt = _text('No copyright, use freely');
  final wtpt = _xyz(_d50);
  final rXyz = _xyz(_rXyz);
  final gXyz = _xyz(_gXyz);
  final bXyz = _xyz(_bXyz);
  final trc = _curve();

  // Tag table: nine tags, the three TRCs sharing one data block (the
  // spec allows identical tags to point at the same data).
  final tags = <(String, Uint8List)>[
    ('desc', desc),
    ('cprt', cprt),
    ('wtpt', wtpt),
    ('rXYZ', rXyz),
    ('gXYZ', gXyz),
    ('bXYZ', bXyz),
    ('rTRC', trc),
    ('gTRC', trc),
    ('bTRC', trc),
  ];
  const headerSize = 128;
  final tableSize = 4 + tags.length * 12;
  var offset = headerSize + tableSize;
  final placed = <(String, int, Uint8List)>[];
  final offsets = <Uint8List, int>{};
  for (final (sig, data) in tags) {
    final existing = offsets[data];
    if (existing != null) {
      placed.add((sig, existing, data));
      continue;
    }
    offsets[data] = offset;
    placed.add((sig, offset, data));
    offset += _padded(data.length);
  }
  final total = offset;

  final out = ByteData(total);
  // ── Header ──
  out.setUint32(0, total);
  // 4: preferred CMM, none.
  out.setUint32(8, 0x02100000); // version 2.1
  _sig(out, 12, 'mntr');
  _sig(out, 16, 'RGB ');
  _sig(out, 20, 'XYZ ');
  // 24: creation dateTimeNumber (six uint16: Y M D h m s).
  out.setUint16(24, 2026);
  out.setUint16(26, 9);
  out.setUint16(28, 10);
  _sig(out, 36, 'acsp');
  // 40 platform, 44 flags, 48 manufacturer, 52 model, 56 attributes (8),
  // 64 rendering intent (0 = perceptual): all zero.
  _xyzNumber(out, 68, _d50); // PCS illuminant
  // 80 creator, 84 profile ID (16), 100 reserved (28): zero.

  // ── Tag table ──
  out.setUint32(headerSize, tags.length);
  var entry = headerSize + 4;
  for (final (sig, at, data) in placed) {
    _sig(out, entry, sig);
    out.setUint32(entry + 4, at);
    out.setUint32(entry + 8, data.length);
    entry += 12;
  }

  // ── Tag data ──
  final bytes = out.buffer.asUint8List();
  for (final (_, at, data) in placed) {
    bytes.setRange(at, at + data.length, data);
  }
  return bytes;
}

int _padded(int length) => (length + 3) & ~3;

void _sig(ByteData out, int at, String sig) {
  assert(sig.length == 4);
  for (var i = 0; i < 4; i++) {
    out.setUint8(at + i, sig.codeUnitAt(i));
  }
}

int _s15Fixed16(double v) => (v * 65536.0).round();

void _xyzNumber(ByteData out, int at, (double, double, double) xyz) {
  out.setInt32(at, _s15Fixed16(xyz.$1));
  out.setInt32(at + 4, _s15Fixed16(xyz.$2));
  out.setInt32(at + 8, _s15Fixed16(xyz.$3));
}

/// XYZType: signature, reserved, one XYZNumber.
Uint8List _xyz((double, double, double) xyz) {
  final out = ByteData(20);
  _sig(out, 0, 'XYZ ');
  _xyzNumber(out, 8, xyz);
  return out.buffer.asUint8List();
}

/// curveType with [_trcSamples] uint16 entries: the sRGB transfer function
/// (IEC 61966-2-1), encoded value in, linear light out.
Uint8List _curve() {
  final out = ByteData(12 + _trcSamples * 2);
  _sig(out, 0, 'curv');
  out.setUint32(8, _trcSamples);
  for (var i = 0; i < _trcSamples; i++) {
    final v = i / (_trcSamples - 1);
    final linear = v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    out.setUint16(12 + i * 2, (linear * 65535.0).round().clamp(0, 65535));
  }
  return out.buffer.asUint8List();
}

/// textDescriptionType (v2): ASCII with its null, then empty Unicode and
/// ScriptCode parts, the latter's fixed 67-byte field included.
Uint8List _textDescription(String text) {
  final ascii = text.codeUnits;
  final out = ByteData(8 + 4 + ascii.length + 1 + 4 + 4 + 2 + 1 + 67);
  _sig(out, 0, 'desc');
  out.setUint32(8, ascii.length + 1);
  for (var i = 0; i < ascii.length; i++) {
    out.setUint8(12 + i, ascii[i]);
  }
  // The null terminator, the Unicode language code and count, the
  // ScriptCode code and count, and the 67-byte ScriptCode field are all
  // zero already.
  return out.buffer.asUint8List();
}

/// textType: signature, reserved, ASCII with its null.
Uint8List _text(String text) {
  final ascii = text.codeUnits;
  final out = ByteData(8 + ascii.length + 1);
  _sig(out, 0, 'text');
  for (var i = 0; i < ascii.length; i++) {
    out.setUint8(8 + i, ascii[i]);
  }
  return out.buffer.asUint8List();
}
