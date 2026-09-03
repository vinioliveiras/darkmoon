// Generates macos/Runner/Assets.xcassets/AppIcon.appiconset's PNGs from the
// app's source icon, replacing Flutter's default placeholder — the macOS
// counterpart to generate_windows_icon.dart.
//
// Contents.json in that folder is Xcode's, already lists exactly these
// filenames, and is not touched.
//
// SOURCE RESOLUTION IS A KNOWN LIMITATION. The original high-resolution
// artwork is not in the repo: generate_windows_icon.dart reads
// ../assets/icon.png, which no longer exists, and the largest surviving
// copy is the 256x256 frame inside the Windows .ico (byte-identical to
// docs/favicon.png). macOS asks for up to 1024x1024, so the 512 and 1024
// slots here are upscaled and will look soft on a Retina display. Drop the
// real artwork in at ../assets/icon.png and re-run this — it is preferred
// automatically — and every size becomes a downscale.
//
// Usage: dart run tool/generate_macos_icon.dart
import 'dart:io';

import 'package:image/image.dart' as img;

/// Every distinct pixel size Contents.json refers to, across its 1x and 2x
/// entries.
const _sizes = [16, 32, 64, 128, 256, 512, 1024];

const _outDir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';

void main() {
  const candidates = ['../assets/icon.png', '../docs/favicon.png'];
  final sourcePath = candidates.firstWhere(
    (p) => File(p).existsSync(),
    orElse: () => '',
  );
  if (sourcePath.isEmpty) {
    stderr.writeln('No source icon found. Tried: ${candidates.join(', ')}');
    exit(1);
  }

  final source = img.decodePng(File(sourcePath).readAsBytesSync());
  if (source == null) {
    stderr.writeln('Could not decode $sourcePath');
    exit(1);
  }
  stdout.writeln('source: $sourcePath (${source.width}x${source.height})');
  if (source.width < 1024) {
    stdout.writeln(
      'note: sizes above ${source.width}px are upscaled and will look soft — '
      'see this tool\'s doc comment',
    );
  }

  for (final size in _sizes) {
    final resized = img.copyResize(
      source,
      width: size,
      height: size,
      // Area-averaging is right for the downscales, which are most of
      // these; cubic keeps an upscale from going blocky.
      interpolation: size <= source.width
          ? img.Interpolation.average
          : img.Interpolation.cubic,
    );
    final out = File('$_outDir/app_icon_$size.png');
    out.writeAsBytesSync(img.encodePng(resized));
    final scaled = size <= source.width ? 'down' : 'UP';
    stdout.writeln('  app_icon_$size.png  ($scaled from ${source.width})');
  }
  stdout.writeln('done');
}
