import 'dart:typed_data';
import 'dart:ui' as ui;

import '../dehaze.dart' show estimateAtmosphericLight;
import 'gpu_pass.dart';

/// GPU port of `dehaze.dart`'s `applyDehaze` — see
/// `project_gpu_render_plan.md`'s Phase 5. The one hybrid CPU+GPU stage in
/// this render pipeline: atmospheric-light estimation needs a full-image
/// sort by dark-channel value (a genuinely global reduction, no fragment-
/// shader equivalent), so this reads back [source] once, runs
/// [estimateAtmosphericLight] on CPU (the exact same function
/// `applyDehaze` itself uses — extracted specifically so both paths share
/// one implementation), then does the rest (dark-channel min filter,
/// transmission map, final haze formula) entirely on GPU.
///
/// **Must run on the main isolate** — see `render_gpu.dart`'s doc comment.
Future<ui.Image> runDehazeGpu(
  ui.Image source,
  int width,
  int height,
  double amount,
) async {
  if (amount == 0) {
    return source;
  }
  final strength = amount / 100.0;

  final byteData = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
  final rgb = rgbaToRgb(byteData!.buffer.asUint8List());
  final norm = Float32List(rgb.length);
  for (var i = 0; i < rgb.length; i++) {
    norm[i] = rgb[i] / 255.0;
  }
  final atmosphericLight = estimateAtmosphericLight(norm, width, height);
  final atmR = atmosphericLight[0];
  final atmG = atmosphericLight[1];
  final atmB = atmosphericLight[2];

  final minChannel = await GpuPass.run(
    'shaders/dehaze_min_channel.frag',
    floats: [width.toDouble(), height.toDouble(), atmR, atmG, atmB],
    samplers: [source],
    outputWidth: width,
    outputHeight: height,
  );
  final normalizedDark = await runMinFilterGpu(minChannel, width, height, 15);
  final preTransmission = await GpuPass.run(
    'shaders/dehaze_pretransmission.frag',
    floats: [width.toDouble(), height.toDouble()],
    samplers: [normalizedDark],
    outputWidth: width,
    outputHeight: height,
  );
  final transmission = await runBoxBlurGpu(preTransmission, width, height, 20);

  return GpuPass.run(
    'shaders/dehaze_apply.frag',
    floats: [width.toDouble(), height.toDouble(), strength, atmR, atmG, atmB],
    samplers: [source, transmission],
    outputWidth: width,
    outputHeight: height,
  );
}
