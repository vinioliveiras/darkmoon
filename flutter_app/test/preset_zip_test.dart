import 'dart:io';

import 'package:darkmoon/presets/preset.dart';
import 'package:darkmoon/presets/preset_zip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presets round-trip through a zip of xmp files', () async {
    final presets = [
      Preset(id: 'a', name: 'Warm Look', values: const {'Temperature': 6500}),
      Preset(id: 'b', name: 'Cool Look', values: const {'Temperature': 4800}),
    ];

    final dir = await Directory.systemTemp.createTemp('preset_zip_test');
    addTearDown(() => dir.delete(recursive: true));
    final zipPath = '${dir.path}/out.zip';
    await File(zipPath).writeAsBytes(presetsToZipBytes(presets));

    final decoded = await presetsFromZip(zipPath);
    expect(decoded.map((p) => p.name).toSet(), {'Warm Look', 'Cool Look'});
  });

  test('same-named presets get distinct entries in the zip', () async {
    final presets = [
      Preset(id: 'a', name: 'Look', values: const {'Exposure': 10}),
      Preset(id: 'b', name: 'Look', values: const {'Exposure': -10}),
    ];

    final dir = await Directory.systemTemp.createTemp('preset_zip_test');
    addTearDown(() => dir.delete(recursive: true));
    final zipPath = '${dir.path}/out.zip';
    await File(zipPath).writeAsBytes(presetsToZipBytes(presets));

    final decoded = await presetsFromZip(zipPath);
    expect(decoded.length, 2);
  });
}
