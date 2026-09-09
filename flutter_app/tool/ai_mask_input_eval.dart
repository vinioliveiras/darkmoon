// Answers one question the smoke test cannot: are the mask models better
// off looking at the decoded RAW (what the app feeds them today) or at the
// tone-mapped render (what the user actually sees)?
//
// It matters because the two are not close on a RAW. The decoded source is
// flat and often dark -- the app's own base exposure, base contrast and
// color profile are applied downstream of it -- while every one of these
// models was trained on ordinary, already-tone-mapped photographs. A model
// shown an image unlike anything in its training set fails quietly, with a
// weak or smeared map rather than an error.
//
// Usage:
//   set DARKMOON_NATIVE_DIR=windows/native
//   dart run tool/ai_mask_input_eval.dart <photo> [more photos...]
import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/native/ai_mask_models.dart';
import 'package:darkmoon/native/edit_source.dart';
import 'package:darkmoon/native/onnx_runtime.dart';
import 'package:darkmoon/render/mask.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:image/image.dart' as img;

void log(String message) {
  // ignore: avoid_print
  print(message);
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/ai_mask_input_eval.dart <photo>...');
    exit(2);
  }
  final outDir = Directory('build/ai_mask_input')..createSync(recursive: true);
  try {
    for (final path in args) {
      _evaluate(path, outDir);
    }
  } finally {
    OnnxModel.releaseAll();
  }
  log('\nWrote maps to ${outDir.path}');
}

void _evaluate(String path, Directory outDir) {
  final name = path.split(RegExp(r'[\\/]')).last;
  log('\n${'=' * 68}\n$name');

  final sources = decodeEditSources(path);
  if (sources == null) {
    log('  could not decode');
    return;
  }
  final source = sources.preview;
  log('  decoded ${source.width}x${source.height}'
      '  baseExposure=${sources.baseExposureStops?.toStringAsFixed(2) ?? "-"}');

  // Exactly what the resolver feeds the models today.
  final raw = _toWorking(source.rgbBytes, source.width, source.height);

  // What the user sees on opening the photo: the global layer at its
  // defaults, which is where base exposure, base contrast and the color
  // profile live. No sliders touched -- this is the neutral render, not
  // somebody's edit.
  final rendered = renderRgb(
    source.width,
    source.height,
    source.rgbBytes,
    RenderParams.fromValues(
      const {},
      baseExposureStops: sources.baseExposureStops ?? 0,
    ),
  );
  final toned = _toWorking(rendered, source.width, source.height);

  log('  mean luma  raw=${_meanLuma(raw.rgb).toStringAsFixed(1)}'
      '  rendered=${_meanLuma(toned.rgb).toStringAsFixed(1)}');

  // Both inputs written out too: a map is impossible to judge without the
  // photo it came from, and the two inputs are the thing under comparison.
  _writeRgb(raw, outDir, '${_stem(name)}-input-raw');
  _writeRgb(toned, outDir, '${_stem(name)}-input-rendered');

  // Third candidate: the decoded source with its tonal range simply
  // stretched to fill 0..255. Neither of the other two is reliably better
  // -- the render rescues a flat, hazy RAW and ruins an already-dark night
  // shot by darkening it further -- and both tie the models to a moving
  // target (the render changes with every edit). This one asks only that
  // the image look like a photograph with a full range, which is the one
  // thing every training set here had in common.
  final levelled = _Frame(
    autoLevelForAiMask(raw.rgb),
    raw.width,
    raw.height,
  );
  _writeRgb(levelled, outDir, '${_stem(name)}-input-levelled');
  log('  mean luma  levelled=${_meanLuma(levelled.rgb).toStringAsFixed(1)}');

  for (final variant in [
    ('raw', raw),
    ('rendered', toned),
    ('levelled', levelled),
  ]) {
    final label = variant.$1;
    final frame = variant.$2;
    _report('$name sky/$label', () => runSkyMaskModel(frame.rgb, frame.width, frame.height),
        outDir, '${_stem(name)}-sky-$label');
    _report(
      '$name foreground/$label',
      () => runForegroundMaskModel(frame.rgb, frame.width, frame.height),
      outDir,
      '${_stem(name)}-foreground-$label',
    );
    _report(
      '$name subject/$label',
      () => runSubjectMaskModel(
        runSubjectEmbedding(frame.rgb, frame.width, frame.height),
        const SubjectGeometry(
          startX: 0.5,
          startY: 0.5,
          endX: 0.5,
          endY: 0.5,
        ),
        frame.width,
        frame.height,
      ),
      outDir,
      '${_stem(name)}-subject-$label',
    );
  }
}

String _stem(String name) =>
    name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;

void _report(
  String label,
  AiMaskMap Function() body,
  Directory outDir,
  String fileStem,
) {
  final AiMaskMap map;
  try {
    map = body();
  } catch (e) {
    log('  $label: FAILED $e');
    return;
  }
  var covered = 0;
  var sum = 0;
  // How much of the map sits in the mushy middle rather than committing to
  // in or out. A confident segmentation is nearly binary; a model shown an
  // image unlike its training data hedges, and that shows up here long
  // before it shows up in the coverage number.
  var undecided = 0;
  for (final v in map.data) {
    sum += v;
    if (v > 127) covered++;
    if (v > 40 && v < 215) undecided++;
  }
  final n = map.data.length;
  log('  ${label.padRight(34)} '
      'coverage=${(100 * covered / n).toStringAsFixed(1)}% '
      'mean=${(sum / n).toStringAsFixed(1)} '
      'undecided=${(100 * undecided / n).toStringAsFixed(1)}%');

  final image = img.Image(width: map.width, height: map.height, numChannels: 1);
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      image.setPixelR(x, y, map.data[y * map.width + x]);
    }
  }
  File('${outDir.path}/$fileStem.png').writeAsBytesSync(img.encodePng(image));
}

class _Frame {
  const _Frame(this.rgb, this.width, this.height);

  final Uint8List rgb;
  final int width;
  final int height;
}

_Frame _toWorking(Uint8List rgb, int width, int height) {
  final longSide = width > height ? width : height;
  if (longSide <= aiMaskWorkingMaxDimension) {
    return _Frame(rgb, width, height);
  }
  final scale = aiMaskWorkingMaxDimension / longSide;
  final dw = (width * scale).round();
  final dh = (height * scale).round();
  return _Frame(resizeRgbForAiMask(rgb, width, height, dw, dh), dw, dh);
}

void _writeRgb(_Frame frame, Directory outDir, String fileStem) {
  final image = img.Image(
    width: frame.width,
    height: frame.height,
    numChannels: 3,
  );
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final i = (y * frame.width + x) * 3;
      image.setPixelRgb(x, y, frame.rgb[i], frame.rgb[i + 1], frame.rgb[i + 2]);
    }
  }
  File('${outDir.path}/$fileStem.png').writeAsBytesSync(img.encodePng(image));
}

double _meanLuma(Uint8List rgb) {
  var sum = 0;
  for (var i = 0; i < rgb.length; i += 3) {
    sum += (rgb[i] * 299 + rgb[i + 1] * 587 + rgb[i + 2] * 114) ~/ 1000;
  }
  return sum / (rgb.length / 3);
}
