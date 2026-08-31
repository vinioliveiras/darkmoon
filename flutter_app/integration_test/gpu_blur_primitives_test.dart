// Phase 2 of the GPU render-pipeline plan: verifies each multi-pass blur
// primitive (box blur, min filter, downsample, upsample) matches its
// blur.dart CPU counterpart independently, on synthetic single-channel
// buffers, before any real effect (Phase 3+) is built on top of them.
//
// Run with: flutter test integration_test/gpu_blur_primitives_test.dart -d windows
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/render/blur.dart';
import 'package:darkmoon/render/gpu/gpu_pass.dart';

/// A single-channel value replicated into R/G/B, so the GPU shaders (which
/// always operate on all 3 RGB channels) can be compared against
/// blur.dart's single-channel CPU functions by just reading back R.
Uint8List _singleChannelAsRgb(Float32List channel) {
  final rgb = Uint8List(channel.length * 3);
  for (var p = 0; p < channel.length; p++) {
    final v = channel[p].clamp(0.0, 255.0).round();
    rgb[p * 3] = v;
    rgb[p * 3 + 1] = v;
    rgb[p * 3 + 2] = v;
  }
  return rgb;
}

/// Deterministic, non-trivial single-channel test pattern — a mix of a
/// smooth gradient and sharp checkerboard edges, so a wrong filter shows
/// up as a real diff (not lost in flat color) and both smooth- and edge-
/// heavy regions get exercised.
Float32List _syntheticChannel(int width, int height) {
  final out = Float32List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final gradient = (x * 255) ~/ width;
      final edge = ((x ~/ 9) + (y ~/ 7)) % 2 == 0 ? 40 : -40;
      out[y * width + x] = (gradient + edge).clamp(0, 255).toDouble();
    }
  }
  return out;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 80;
  const height = 60;
  final channel = _syntheticChannel(width, height);

  void expectClose(Uint8List gpu, Float32List cpu, String label) {
    var sumDiff = 0.0;
    var maxDiff = 0.0;
    for (var p = 0; p < cpu.length; p++) {
      final d = (gpu[p * 3] - cpu[p]).abs();
      sumDiff += d;
      if (d > maxDiff) maxDiff = d;
    }
    final meanDiff = sumDiff / cpu.length;
    // ignore: avoid_print
    print('[gpu_blur] $label: mean=$meanDiff max=$maxDiff');
    expect(
      meanDiff,
      lessThan(2.0),
      reason: '$label: mean diff $meanDiff vs CPU',
    );
    expect(maxDiff, lessThan(10.0), reason: '$label: max diff $maxDiff');
  }

  testWidgets('box blur (H then V) matches boxBlurMean', (tester) async {
    for (final radius in [1, 6, 25]) {
      final source = await decodeRgbImage(
        _singleChannelAsRgb(channel),
        width,
        height,
      );
      final h = await GpuPass.run(
        'shaders/box_blur_h.frag',
        floats: [width.toDouble(), height.toDouble(), radius.toDouble()],
        samplers: [source],
        outputWidth: width,
        outputHeight: height,
      );
      final v = await GpuPass.run(
        'shaders/box_blur_v.frag',
        floats: [width.toDouble(), height.toDouble(), radius.toDouble()],
        samplers: [h],
        outputWidth: width,
        outputHeight: height,
      );
      final byteData = await v.toByteData(format: ui.ImageByteFormat.rawRgba);
      final gpuRgb = rgbaToRgb(byteData!.buffer.asUint8List());
      final cpu = boxBlurMean(channel, width, height, radius);
      expectClose(gpuRgb, cpu, 'box blur r=$radius');
    }
  });

  testWidgets('min filter (H then V) matches minFilter', (tester) async {
    for (final size in [5, 15]) {
      final radius = ((size - 1) ~/ 2).toDouble();
      final source = await decodeRgbImage(
        _singleChannelAsRgb(channel),
        width,
        height,
      );
      final h = await GpuPass.run(
        'shaders/min_filter_h.frag',
        floats: [width.toDouble(), height.toDouble(), radius],
        samplers: [source],
        outputWidth: width,
        outputHeight: height,
      );
      final v = await GpuPass.run(
        'shaders/min_filter_v.frag',
        floats: [width.toDouble(), height.toDouble(), radius],
        samplers: [h],
        outputWidth: width,
        outputHeight: height,
      );
      final byteData = await v.toByteData(format: ui.ImageByteFormat.rawRgba);
      final gpuRgb = rgbaToRgb(byteData!.buffer.asUint8List());
      final cpu = minFilter(channel, width, height, size);
      expectClose(gpuRgb, cpu, 'min filter size=$size');
    }
  });

  testWidgets('downsample + bilinear upsample matches downsampleChannel + '
      'upsampleChannelBilinear', (tester) async {
    const factor = 4;
    final source = await decodeRgbImage(
      _singleChannelAsRgb(channel),
      width,
      height,
    );
    final small = await GpuPass.run(
      'shaders/downsample_box.frag',
      floats: [
        (width / factor).ceil().toDouble(),
        (height / factor).ceil().toDouble(),
        width.toDouble(),
        height.toDouble(),
        factor.toDouble(),
      ],
      samplers: [source],
      outputWidth: (width / factor).ceil(),
      outputHeight: (height / factor).ceil(),
    );
    final upsampled = await GpuPass.run(
      'shaders/upsample.frag',
      floats: [
        width.toDouble(),
        height.toDouble(),
        (width / factor).ceil().toDouble(),
        (height / factor).ceil().toDouble(),
        factor.toDouble(),
      ],
      samplers: [small],
      outputWidth: width,
      outputHeight: height,
    );
    final byteData = await upsampled.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final gpuRgb = rgbaToRgb(byteData!.buffer.asUint8List());

    final cpuSmall = downsampleChannel(channel, width, height, factor);
    final cpuUpsampled = upsampleChannelBilinear(
      cpuSmall.channel,
      cpuSmall.width,
      cpuSmall.height,
      factor,
      width,
      height,
    );
    expectClose(gpuRgb, cpuUpsampled, 'downsample+upsample f=$factor');
  });
}
