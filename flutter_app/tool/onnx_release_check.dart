// Leak check for OnnxModel.releaseAll: loads a model session, releases it,
// and repeats, printing RSS at each step. If releaseAll ever stops actually
// freeing, the "released" numbers climb round over round.
//
// ddcolor_modelscope.onnx is the one to watch — its graph alone is ~934 MB,
// so the leak it used to cause per Colorize run is impossible to miss.
//
// Usage (from flutter_app/, against a built bundle so the DLLs and models
// resolve the same way they do in the app):
//
//   DARKMOON_NATIVE_DIR=<bundle> PATH=$PATH:<bundle> \
//     dart run tool/onnx_release_check.dart
//
// where <bundle> is e.g. build/windows/x64/runner/Release.
//
// Recorded on the machine this was written on (DirectML active):
//   baseline 272 MB; loaded ~1390 MB; released ~440 MB; flat over 4 rounds.
import 'dart:io';

import 'package:darkmoon/native/onnx_runtime.dart';

void main() {
  int mb(int bytes) => bytes ~/ (1024 * 1024);
  stdout.writeln('baseline RSS: ${mb(ProcessInfo.currentRss)} MB');
  for (var i = 1; i <= 4; i++) {
    final model = OnnxModel.forSpec(ddcolorModelSpec);
    stdout.writeln(
      'round $i: loaded (gpu=${model.usingGpu}) '
      'RSS=${mb(ProcessInfo.currentRss)} MB',
    );
    OnnxModel.releaseAll();
    stdout.writeln('round $i: released  RSS=${mb(ProcessInfo.currentRss)} MB');
  }
  // Releasing with nothing loaded must be a safe no-op, and safe twice.
  OnnxModel.releaseAll();
  OnnxModel.releaseAll();
  stdout.writeln('double release with empty cache: ok');
}
