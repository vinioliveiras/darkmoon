// Loads and exercises the native layer, and reports what it found.
//
// This exists because darkmoon's macOS support has no machine to be tried
// on: GitHub's runners are the only Apple hardware it ever touches, and a
// GUI cannot be driven there. So it is verified the same way the Linux
// build originally was — direct FFI calls, which is what actually breaks
// when a platform is newly wired up: a wrong library name, an
// install_name that does not resolve from Contents/Frameworks, a missing
// execution provider.
//
// Runs on every platform, not just macOS — a regression in the Windows or
// Linux loaders is caught here too. Exits non-zero if a mandatory check
// fails.
//
// Usage: dart run tool/native_smoke_test.dart [sample-raw-file] [model.onnx]
//
// Given a model it creates a real session and runs a tile through it — see
// tool/make_test_onnx_model.py for the tiny stand-in CI uses, the real
// weights being gitignored.
import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/native/libraw.dart';
import 'package:darkmoon/native/onnx_runtime.dart';

var _failures = 0;

void _check(String what, void Function() body) {
  try {
    body();
    stdout.writeln('  OK    $what');
  } catch (e) {
    _failures++;
    stdout.writeln('  FAIL  $what\n          $e');
  }
}

void main(List<String> args) {
  stdout
    ..writeln('darkmoon native smoke test — ${Platform.operatingSystem}')
    ..writeln('executable: ${Platform.resolvedExecutable}')
    ..writeln();

  final sample = args.isNotEmpty && File(args.first).existsSync()
      ? args.first
      : null;

  stdout.writeln('LibRaw');
  // Loading the library is the thing under test. extractRawMetadata opens
  // it first and returns null for a file it cannot read, so a missing or
  // unresolvable dylib surfaces as a thrown error from
  // DynamicLibrary.open while a bad path merely returns null.
  _check('library loads', () {
    extractRawMetadata(sample ?? 'darkmoon-no-such-file.raw');
  });
  if (sample != null) {
    _check('decodes $sample', () {
      final decoded = decodeRawImage(sample, fastPreview: true);
      if (decoded == null) {
        throw StateError('decode returned null');
      }
      if (decoded.width <= 0 || decoded.height <= 0) {
        throw StateError(
          'nonsense dimensions '
          '${decoded.width}x${decoded.height}',
        );
      }
      stdout.writeln(
        '          ${decoded.width}x${decoded.height}, '
        '${decoded.rgbBytes.length} bytes',
      );
    });
  } else {
    stdout.writeln('  SKIP  decode (no sample file given)');
  }

  stdout
    ..writeln()
    ..writeln('ONNX Runtime');
  // Two outcomes both prove the runtime itself loaded. With the weights
  // present (a local checkout) a session is created and reports its
  // execution provider; without them (CI, where the ~1.2GB of .onnx is
  // gitignored) session creation throws an OrtException about the missing
  // file — which it can only do after the library is up. A failure to load
  // the library is a different error entirely, and fails this check.
  final modelArg = args.length > 1 && File(args[1]).existsSync()
      ? args[1]
      : null;
  _check('runtime loads', () {
    try {
      final spec = modelArg == null
          ? denoiseModelSpec
          : OnnxModelSpec.customDenoiseModel(modelArg);
      final model = OnnxModel.forSpec(spec);
      stdout.writeln(
        '          provider: ${model.provider.label} '
        '(gpu=${model.usingGpu})',
      );
      if (model.gpuError != null) {
        stdout.writeln('          gpu unavailable: ${model.gpuError}');
      }
      if (modelArg != null) {
        // A real inference, not just a session. The stand-in model is an
        // identity, so its output must come back equal to its input —
        // which also catches an execution provider that runs but returns
        // garbage, rather than only one that fails outright.
        // runTile validates against the spec's own tile size, so this
        // cannot pick a smaller one to be quick.
        final size = spec.inputTileSize;
        final tile = Float32List(size * size * 3);
        for (var i = 0; i < tile.length; i++) {
          tile[i] = (i % 255) / 255.0;
        }
        final result = model.runTile(tile);
        if (result.length != tile.length) {
          throw StateError(
            'expected ${tile.length} values, got ${result.length}',
          );
        }
        var worst = 0.0;
        for (var i = 0; i < tile.length; i++) {
          final d = (result[i] - tile[i]).abs();
          if (d > worst) worst = d;
        }
        if (worst > 1e-5) {
          throw StateError('identity model changed the data by $worst');
        }
        stdout.writeln(
          '          ran ${size}x$size through it, '
          'output matches input (max diff $worst)',
        );
      }
      OnnxModel.releaseAll();
    } on OrtException catch (e) {
      // Without a model there is nothing to load, and that is expected in
      // CI; with one, a failure is real.
      if (modelArg != null) rethrow;
      stdout.writeln(
        '          loaded; no session '
        '(expected without the model weights): ${e.message}',
      );
    }
  });

  stdout.writeln();
  if (_failures > 0) {
    stdout.writeln('$_failures check(s) failed.');
    exit(1);
  }
  stdout.writeln('All mandatory checks passed.');
}
