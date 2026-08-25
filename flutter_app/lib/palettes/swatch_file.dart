import 'dart:math' as math;
import 'dart:typed_data';

import 'palette.dart';

/// Dispatches on [path]'s extension to [parseAse] or [parseAco]. Returns
/// null for an unrecognized extension (the caller's file picker already
/// restricts to these two, but this stays defensive for callers that
/// don't).
List<PaletteSwatch>? parseSwatchFile(String path, Uint8List bytes) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.ase')) {
    return parseAse(bytes);
  }
  if (lower.endsWith('.aco')) {
    return parseAco(bytes);
  }
  return null;
}

/// Parses an Adobe Swatch Exchange (.ase) file — what Adobe Color CC
/// (color.adobe.com) themes export as, and what "Save Swatches for
/// Exchange" produces in Illustrator/Photoshop/InDesign.
///
/// Best-effort: an individual color entry that doesn't parse as expected
/// is skipped rather than aborting the whole file, since one malformed
/// block shouldn't lose every other swatch alongside it.
List<PaletteSwatch> parseAse(Uint8List bytes) {
  if (bytes.length < 12 || String.fromCharCodes(bytes, 0, 4) != 'ASEF') {
    return const [];
  }
  final data = ByteData.sublistView(bytes);
  final numBlocks = data.getUint32(8);
  final swatches = <PaletteSwatch>[];
  var offset = 12;
  for (var i = 0; i < numBlocks && offset + 6 <= bytes.length; i++) {
    final blockType = data.getUint16(offset);
    final blockLength = data.getUint32(offset + 2);
    final blockStart = offset + 6;
    final blockEnd = blockStart + blockLength;
    if (blockLength < 0 || blockEnd > bytes.length) {
      break;
    }
    if (blockType == 0x0001) {
      final swatch = _parseAseColorEntry(data, bytes, blockStart, blockEnd);
      if (swatch != null) {
        swatches.add(swatch);
      }
    }
    // Group start (0xC001) and group end (0xC002) blocks are skipped over
    // rather than tracked — every color entry ends up in one flat list
    // regardless of which group it was nested in.
    offset = blockEnd;
  }
  return swatches;
}

PaletteSwatch? _parseAseColorEntry(
  ByteData data,
  Uint8List bytes,
  int start,
  int end,
) {
  try {
    var o = start;
    final nameLen = data.getUint16(o);
    o += 2;
    final name = _readUtf16Be(data, o, nameLen);
    o += nameLen * 2;
    final colorModel = String.fromCharCodes(bytes, o, o + 4);
    o += 4;
    final int rgb;
    switch (colorModel) {
      case 'RGB ':
        rgb = _packRgb(
          data.getFloat32(o),
          data.getFloat32(o + 4),
          data.getFloat32(o + 8),
        );
        break;
      case 'Gray':
        final v = data.getFloat32(o);
        rgb = _packRgb(v, v, v);
        break;
      case 'CMYK':
        final c = data.getFloat32(o);
        final m = data.getFloat32(o + 4);
        final y = data.getFloat32(o + 8);
        final k = data.getFloat32(o + 12);
        rgb = _cmykToRgb(c, m, y, k);
        break;
      case 'LAB ':
        // Adobe's ASE writers store L/a/b as plain floats already in their
        // natural ranges (L 0..100, a/b roughly -128..127) — unlike RGB's
        // floats, which are normalized to 0..1.
        rgb = _labToRgbPacked(
          data.getFloat32(o),
          data.getFloat32(o + 4),
          data.getFloat32(o + 8),
        );
        break;
      default:
        return null;
    }
    return PaletteSwatch(name: name.isEmpty ? _hex(rgb) : name, rgb: rgb);
  } catch (_) {
    return null;
  }
}

/// Parses an Adobe Color Swatch (.aco) file — Photoshop's native swatch
/// format (the ".aco" extension is literally short for "Adobe COlor").
///
/// A modern .aco file is a version-1 block (no names) immediately followed
/// by a version-2 block (same colors, with names) for backward
/// compatibility with older readers — when both are present, the named
/// version-2 block is preferred.
List<PaletteSwatch> parseAco(Uint8List bytes) {
  try {
    final data = ByteData.sublistView(bytes);
    final block1 = _parseAcoBlock(data, bytes, 0);
    if (block1 == null) {
      return const [];
    }
    if (block1.version == 2) {
      return block1.swatches;
    }
    final block2 = _parseAcoBlock(data, bytes, block1.end);
    if (block2 != null && block2.version == 2) {
      return block2.swatches;
    }
    return block1.swatches;
  } catch (_) {
    return const [];
  }
}

class _AcoBlock {
  const _AcoBlock(this.version, this.swatches, this.end);

  final int version;
  final List<PaletteSwatch> swatches;

  /// Byte offset just past this block — where a following block (if any)
  /// starts.
  final int end;
}

_AcoBlock? _parseAcoBlock(ByteData data, Uint8List bytes, int start) {
  if (start + 4 > bytes.length) {
    return null;
  }
  var o = start;
  final version = data.getUint16(o);
  o += 2;
  if (version != 1 && version != 2) {
    return null;
  }
  final count = data.getUint16(o);
  o += 2;
  final swatches = <PaletteSwatch>[];
  for (var i = 0; i < count; i++) {
    if (o + 10 > bytes.length) {
      return null;
    }
    final colorSpace = data.getUint16(o);
    final w = data.getUint16(o + 2);
    final x = data.getUint16(o + 4);
    final y = data.getUint16(o + 6);
    final z = data.getUint16(o + 8);
    o += 10;
    var name = '';
    if (version == 2) {
      if (o + 4 > bytes.length) {
        return null;
      }
      final nameLen = data.getUint32(o);
      o += 4;
      if (o + nameLen * 2 > bytes.length) {
        return null;
      }
      name = _readUtf16Be(data, o, nameLen);
      o += nameLen * 2;
    }
    final rgb = _acoColorToRgb(colorSpace, w, x, y, z);
    swatches.add(
      PaletteSwatch(name: name.isEmpty ? _hex(rgb) : name, rgb: rgb),
    );
  }
  return _AcoBlock(version, swatches, o);
}

/// Converts one ACO color entry's raw 16-bit components to packed RGB,
/// per Adobe's per-`colorSpace` encoding. HSB/CMYK/Lab/Grayscale support
/// is best-effort (RGB — by far the common case for swatches actually
/// exported from Adobe Color CC — is exact).
int _acoColorToRgb(int colorSpace, int w, int x, int y, int z) {
  double u16(int v) => v / 65535.0;
  switch (colorSpace) {
    case 0: // RGB — each component 0..65535
      return _packRgb(u16(w), u16(x), u16(y));
    case 1: // HSB — hue 0..65535 -> 0..360deg, saturation/brightness 0..1
      return _packRgb3(_hsbToRgb(u16(w) * 360, u16(x), u16(y)));
    case 2: // CMYK — 0..65535, inverted (0 = full ink, 65535 = no ink)
      final c = 1 - u16(w), m = 1 - u16(x), ye = 1 - u16(y), k = 1 - u16(z);
      return _cmykToRgb(c, m, ye, k);
    case 7: // Lab — L 0..10000 -> 0..100, a/b 0..65535 -> roughly -128..127
      return _labToRgbPacked(w / 100.0, x / 256.0 - 128, y / 256.0 - 128);
    case 8: // Grayscale — 0..10000 -> 0..100%
      final gray = (w / 10000.0).clamp(0.0, 1.0);
      return _packRgb(gray, gray, gray);
    default:
      return _packRgb(u16(w), u16(x), u16(y));
  }
}

String _readUtf16Be(ByteData data, int offset, int codeUnitCount) {
  final units = List<int>.generate(
    codeUnitCount,
    (i) => data.getUint16(offset + i * 2),
  );
  // Adobe's swatch formats null-terminate the name; strip it rather than
  // rendering a stray character after the visible name.
  final trimmed = units.isNotEmpty && units.last == 0
      ? units.sublist(0, units.length - 1)
      : units;
  return String.fromCharCodes(trimmed).trim();
}

int _packRgb(double r, double g, double b) {
  int channel(double v) => (v.clamp(0.0, 1.0) * 255).round();
  return (channel(r) << 16) | (channel(g) << 8) | channel(b);
}

int _packRgb3(List<double> rgb) => _packRgb(rgb[0], rgb[1], rgb[2]);

int _cmykToRgb(double c, double m, double y, double k) =>
    _packRgb((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k));

List<double> _hsbToRgb(double h, double s, double v) {
  final c = v * s;
  final hh = (h % 360) / 60;
  final xComp = c * (1 - (hh % 2 - 1).abs());
  var r = 0.0, g = 0.0, b = 0.0;
  if (hh < 1) {
    r = c;
    g = xComp;
  } else if (hh < 2) {
    r = xComp;
    g = c;
  } else if (hh < 3) {
    g = c;
    b = xComp;
  } else if (hh < 4) {
    g = xComp;
    b = c;
  } else if (hh < 5) {
    r = xComp;
    b = c;
  } else {
    r = c;
    b = xComp;
  }
  final m = v - c;
  return [r + m, g + m, b + m];
}

/// CIE L*a*b* (D65 white point) to sRGB, packed as `0xRRGGBB`.
int _labToRgbPacked(double l, double a, double b) {
  double finv(double t) => t > 6.0 / 29.0
      ? t * t * t
      : 3 * (6.0 / 29.0) * (6.0 / 29.0) * (t - 4.0 / 29.0);
  final fy = (l + 16) / 116;
  final fx = fy + a / 500;
  final fz = fy - b / 200;
  const xn = 0.95047, yn = 1.0, zn = 1.08883;
  final x = xn * finv(fx);
  final y = yn * finv(fy);
  final z = zn * finv(fz);
  final rLin = 3.2406 * x - 1.5372 * y - 0.4986 * z;
  final gLin = -0.9689 * x + 1.8758 * y + 0.0415 * z;
  final bLin = 0.0557 * x - 0.2040 * y + 1.0570 * z;
  double gamma(double v) =>
      v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
  return _packRgb(gamma(rLin), gamma(gLin), gamma(bLin));
}

String _hex(int rgb) => '#${rgb.toRadixString(16).padLeft(6, '0')}';
