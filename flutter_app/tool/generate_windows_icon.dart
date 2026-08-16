// Generates windows/runner/resources/app_icon.ico (multi-resolution: 16,
// 32, 48, 256px) from the app's source icon, replacing Flutter's default
// placeholder icon. Re-run this if ../../assets/icon.png changes.
//
// Usage: dart run tool/generate_windows_icon.dart
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const sourcePath = '../assets/icon.png';
  const outPath = 'windows/runner/resources/app_icon.ico';

  final bytes = File(sourcePath).readAsBytesSync();
  final source = img.decodePng(bytes);
  if (source == null) {
    stderr.writeln('Could not decode $sourcePath');
    exit(1);
  }

  const sizes = [16, 32, 48, 256];
  final images = [
    for (final size in sizes)
      img.copyResize(source, width: size, height: size, interpolation: img.Interpolation.average),
  ];

  final icoBytes = img.IcoEncoder().encodeImages(images);
  File(outPath).writeAsBytesSync(icoBytes);
  // ignore: avoid_print
  print('Wrote $outPath (${icoBytes.length} bytes, sizes: $sizes)');
}
