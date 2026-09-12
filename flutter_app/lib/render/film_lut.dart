// The "Film" stage: a 3D colour look-up table applied as the very last
// step of the global render, on both paths (render.dart's
// applyGlobalPointOps and render_gpu.dart's film_lut.frag).
//
// Why a LUT and not a ColorProfile (2026-09-12, measured with
// tool/film_clut_fit_probe.dart): a film look lives in the tone curve, in
// the neutrals and in colour-dependent crossovers, none of which the
// per-hue profile can represent — the best 24-bin fit recovered between
// 4% and 75% of eleven film looks, while a 33^3 resample of the real
// table stayed under dE 0.5 mean against the full one.
//
// One table is `size^3` RGB triplets, 8 bits each, red index fastest:
// `data[(r + g*size + b*size*size) * 3 + c]`. That is the .cube file
// order, the Hald CLUT pixel order, and the order the packed texture
// below lays its texels in, so the three sources share one buffer shape.
//
// The packed texture is a `size*size` x `size` image: blue slice `b` sits
// at x offset `b*size`, red runs along x inside the slice and green runs
// down y. Flutter fragment shaders only take 2D samplers, so this is what
// the GPU reads, and — deliberately — also what the bundled assets are
// stored as: the same PNG decodes straight into [data] and uploads
// straight into the shader with no conversion in between.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Entries per axis of every bundled film table (see
/// `tool/build_film_luts.dart`). Also the size a user-imported table is
/// resampled to before it reaches the GPU.
///
/// 33 is the industry's usual size (DaVinci, OBS, OCIO all default to
/// it). Measured on real film tables against the 144^3 originals: dE mean
/// 0.19-0.46, p95 at most 1.6 — invisible; 17^3 already reached p95 3.4 on
/// Superia 400.
const filmLutSize = 33;

/// The Film section's Amount default, in percent — the house rule for a
/// new toggle (see feedback_toggle_amount_default): 50%.
const defaultFilmAmount = 50.0;

class FilmLut {
  FilmLut({required this.size, required this.data, this.id = 0, this.name = ''})
    : assert(data.length == size * size * size * 3);

  /// Entries per axis.
  final int size;

  /// `size^3 * 3` bytes, see the file comment for the index order.
  final Uint8List data;

  /// The bundled film's manifest id; 0 for a table that is not bundled.
  final int id;

  final String name;

  /// The identity table: every colour maps to itself.
  factory FilmLut.identity(int size) {
    final data = Uint8List(size * size * size * 3);
    var k = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          data[k++] = (r * 255 / (size - 1)).round();
          data[k++] = (g * 255 / (size - 1)).round();
          data[k++] = (b * 255 / (size - 1)).round();
        }
      }
    }
    return FilmLut(size: size, data: data);
  }

  /// Reads the packed layout described in the file comment.
  factory FilmLut.fromPacked(img.Image image, {int id = 0, String name = ''}) {
    final size = image.height;
    if (image.width != size * size) {
      throw FormatException(
        'not a packed film LUT: ${image.width}x${image.height}',
      );
    }
    final data = Uint8List(size * size * size * 3);
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          final px = image.getPixel(b * size + r, g);
          final o = (r + g * size + b * size * size) * 3;
          data[o] = (px.rNormalized * 255).round();
          data[o + 1] = (px.gNormalized * 255).round();
          data[o + 2] = (px.bNormalized * 255).round();
        }
      }
    }
    return FilmLut(size: size, data: data, id: id, name: name);
  }

  /// Writes the packed layout — the shape both the assets and the GPU
  /// texture take.
  img.Image toPacked() {
    final image = img.Image(width: size * size, height: size);
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          final o = (r + g * size + b * size * size) * 3;
          image.setPixelRgb(b * size + r, g, data[o], data[o + 1], data[o + 2]);
        }
      }
    }
    return image;
  }

  /// RGBA bytes of [toPacked], row-major, for `decodeImageFromPixels`.
  Uint8List packedRgba() {
    final w = size * size;
    final out = Uint8List(w * size * 4);
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          final o = (r + g * size + b * size * size) * 3;
          final p = (g * w + b * size + r) * 4;
          out[p] = data[o];
          out[p + 1] = data[o + 1];
          out[p + 2] = data[o + 2];
          out[p + 3] = 255;
        }
      }
    }
    return out;
  }

  /// Reads a Hald CLUT image (RawTherapee / G'MIC): a square of `level^3`
  /// pixels a side holding a `level^2`-per-axis table in raster order.
  factory FilmLut.fromHald(img.Image image, {int id = 0, String name = ''}) {
    if (image.width != image.height) {
      throw FormatException(
        'not a Hald CLUT: ${image.width}x${image.height} is not square',
      );
    }
    final total = image.width * image.height;
    final size = math.pow(total, 1 / 3).round();
    if (size * size * size != total) {
      throw FormatException(
        'not a Hald CLUT: ${image.width}x${image.height} pixels is not '
        'a perfect cube',
      );
    }
    final data = Uint8List(total * 3);
    var k = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        data[k++] = (px.rNormalized * 255).round();
        data[k++] = (px.gNormalized * 255).round();
        data[k++] = (px.bNormalized * 255).round();
      }
    }
    return FilmLut(size: size, data: data, id: id, name: name);
  }

  /// Reads an Adobe/Resolve `.cube` file (3D only). Honours
  /// `LUT_3D_SIZE`, `DOMAIN_MIN`/`DOMAIN_MAX` and `TITLE`; ignores
  /// comments and blank lines.
  factory FilmLut.fromCube(String text, {int id = 0, String name = ''}) {
    var size = 0;
    var domainMin = const [0.0, 0.0, 0.0];
    var domainMax = const [1.0, 1.0, 1.0];
    var title = name;
    final values = <double>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      final key = parts.first.toUpperCase();
      if (key == 'LUT_3D_SIZE') {
        size = int.parse(parts[1]);
      } else if (key == 'LUT_1D_SIZE') {
        throw const FormatException('1D .cube tables are not supported');
      } else if (key == 'DOMAIN_MIN') {
        domainMin = [for (final p in parts.skip(1)) double.parse(p)];
      } else if (key == 'DOMAIN_MAX') {
        domainMax = [for (final p in parts.skip(1)) double.parse(p)];
      } else if (key == 'TITLE') {
        title = line.substring(5).trim().replaceAll('"', '');
      } else if (parts.length == 3) {
        final r = double.tryParse(parts[0]);
        final g = double.tryParse(parts[1]);
        final b = double.tryParse(parts[2]);
        if (r == null || g == null || b == null) continue;
        values
          ..add(r)
          ..add(g)
          ..add(b);
      }
    }
    if (size < 2) {
      throw const FormatException('LUT_3D_SIZE missing from .cube file');
    }
    if (values.length != size * size * size * 3) {
      throw FormatException(
        '.cube file has ${values.length ~/ 3} entries, expected '
        '${size * size * size}',
      );
    }
    final data = Uint8List(values.length);
    for (var i = 0; i < values.length; i++) {
      final lo = domainMin[i % 3], hi = domainMax[i % 3];
      final v = hi > lo ? (values[i] - lo) / (hi - lo) : values[i];
      data[i] = (v.clamp(0.0, 1.0) * 255).round();
    }
    return FilmLut(size: size, data: data, id: id, name: title);
  }

  /// Trilinear lookup of one colour, inputs and outputs 0..1.
  void lookup(double r, double g, double b, Float32List out, int o) {
    final n = size - 1;
    final fr = r.clamp(0.0, 1.0) * n;
    final fg = g.clamp(0.0, 1.0) * n;
    final fb = b.clamp(0.0, 1.0) * n;
    final r0 = fr.floor().clamp(0, n);
    final g0 = fg.floor().clamp(0, n);
    final b0 = fb.floor().clamp(0, n);
    final r1 = math.min(r0 + 1, n);
    final g1 = math.min(g0 + 1, n);
    final b1 = math.min(b0 + 1, n);
    final tr = fr - r0, tg = fg - g0, tb = fb - b0;
    final s = size, s2 = size * size;
    final i000 = (r0 + g0 * s + b0 * s2) * 3;
    final i100 = (r1 + g0 * s + b0 * s2) * 3;
    final i010 = (r0 + g1 * s + b0 * s2) * 3;
    final i110 = (r1 + g1 * s + b0 * s2) * 3;
    final i001 = (r0 + g0 * s + b1 * s2) * 3;
    final i101 = (r1 + g0 * s + b1 * s2) * 3;
    final i011 = (r0 + g1 * s + b1 * s2) * 3;
    final i111 = (r1 + g1 * s + b1 * s2) * 3;
    for (var c = 0; c < 3; c++) {
      final c00 = data[i000 + c] * (1 - tr) + data[i100 + c] * tr;
      final c10 = data[i010 + c] * (1 - tr) + data[i110 + c] * tr;
      final c01 = data[i001 + c] * (1 - tr) + data[i101 + c] * tr;
      final c11 = data[i011 + c] * (1 - tr) + data[i111 + c] * tr;
      final c0 = c00 * (1 - tg) + c10 * tg;
      final c1 = c01 * (1 - tg) + c11 * tg;
      out[o + c] = (c0 * (1 - tb) + c1 * tb) / 255.0;
    }
  }

  /// This table resampled to [newSize] entries per axis by trilinear
  /// interpolation — how a 144^3 Hald CLUT becomes a [filmLutSize] asset.
  FilmLut resampled(int newSize) {
    if (newSize == size) return this;
    final out = Uint8List(newSize * newSize * newSize * 3);
    final tmp = Float32List(3);
    var k = 0;
    for (var b = 0; b < newSize; b++) {
      for (var g = 0; g < newSize; g++) {
        for (var r = 0; r < newSize; r++) {
          lookup(
            r / (newSize - 1),
            g / (newSize - 1),
            b / (newSize - 1),
            tmp,
            0,
          );
          out[k++] = (tmp[0] * 255).round();
          out[k++] = (tmp[1] * 255).round();
          out[k++] = (tmp[2] * 255).round();
        }
      }
    }
    return FilmLut(size: newSize, data: out, id: id, name: name);
  }

  bool get isIdentity {
    var k = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          if ((data[k] - (r * 255 / (size - 1)).round()).abs() > 1 ||
              (data[k + 1] - (g * 255 / (size - 1)).round()).abs() > 1 ||
              (data[k + 2] - (b * 255 / (size - 1)).round()).abs() > 1) {
            return false;
          }
          k += 3;
        }
      }
    }
    return true;
  }
}

/// Applies [lut] to the packed RGB 0..255 [buffer] in place, blending the
/// result over the input by [amount] (0..1). The GPU counterpart is
/// `shaders/film_lut.frag`; keep the two identical.
void applyFilmLut(Float32List buffer, FilmLut lut, double amount) {
  final a = amount.clamp(0.0, 1.0);
  if (a <= 0) return;
  final out = Float32List(3);
  for (var i = 0; i < buffer.length; i += 3) {
    lut.lookup(
      buffer[i] / 255.0,
      buffer[i + 1] / 255.0,
      buffer[i + 2] / 255.0,
      out,
      0,
    );
    buffer[i] = buffer[i] + (out[0] * 255.0 - buffer[i]) * a;
    buffer[i + 1] = buffer[i + 1] + (out[1] * 255.0 - buffer[i + 1]) * a;
    buffer[i + 2] = buffer[i + 2] + (out[2] * 255.0 - buffer[i + 2]) * a;
  }
}
