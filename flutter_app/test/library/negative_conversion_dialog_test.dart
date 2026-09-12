import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/library/negative_conversion_dialog.dart';
import 'package:darkmoon/raw_files.dart';
import 'package:darkmoon/render/negative.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('converts every file with the dialog\'s parameters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = [
      RawFile('C:/roll/a.jpg', DateTime(2026)),
      RawFile('C:/roll/b.jpg', DateTime(2026)),
    ];
    final converted = <String>[];
    NegativeParams? used;
    NegativeConversionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<NegativeConversionResult>(
                    context: context,
                    builder: (_) => NegativeConversionDialog(
                      files: files,
                      // No preview: compute() cannot run under the
                      // test's fake clock, and the conversion path is
                      // what this checks.
                      previewJpegFor: (_) async => null,
                      convert: (file, params) async {
                        converted.add(file.path);
                        used = params;
                        if (file.path.endsWith('b.jpg')) {
                          throw StateError('nope');
                        }
                        return '${file.path}_Positive.tiff';
                      },
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Negative conversion'), findsOneWidget);
    expect(find.text('Red (cyan)'), findsOneWidget);
    expect(find.text('No preview for this photo yet.'), findsOneWidget);
    expect(find.text('Convert & save all (2)'), findsOneWidget);

    await tester.tap(find.text('Convert & save all (2)'));
    await tester.pumpAndSettle();

    expect(converted, ['C:/roll/a.jpg', 'C:/roll/b.jpg']);
    expect(used!.enabled, isTrue);
    expect(result!.written, ['C:/roll/a.jpg_Positive.tiff']);
    expect(result!.failed, ['C:/roll/b.jpg']);
  });
}
