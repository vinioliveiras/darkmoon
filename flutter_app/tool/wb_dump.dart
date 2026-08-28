// Dumps everything LibRaw knows about a RAW file's white balance, plus
// what wbMultipliersToKelvinTint estimates. Compare the estimate against
// Lightroom's "As Shot" Temp/Tint to calibrate.
//
// Usage: dart run tool/wb_dump.dart <raw-file>
import 'dart:io';

import 'package:darkmoon/native/libraw.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/wb_dump.dart <raw-file>');
    exit(1);
  }
  // `dart run` doesn't put the built raw_r.dll on the search path the way
  // `flutter run` does — copy it next to the cwd if it isn't already here.
  const releaseDir = 'build/windows/x64/runner/Release';
  for (final dll in ['raw_r.dll', 'vcomp140.dll']) {
    if (File(dll).existsSync()) {
      continue;
    }
    final built = File('$releaseDir/$dll');
    if (built.existsSync()) {
      built.copySync(dll);
      stderr.writeln('(copied $dll from the Release build)');
    } else if (dll == 'raw_r.dll') {
      stderr.writeln(
        'raw_r.dll not found. Run `flutter build windows` first, or copy '
        'raw_r.dll into ${Directory.current.path}',
      );
      exit(1);
    }
  }
  // ignore: avoid_print
  print(dumpRawWhiteBalanceInfo(args[0]));
}
