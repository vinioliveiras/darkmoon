import 'package:darkmoon/export/export_format.dart';
import 'package:darkmoon/export/frame.dart';
import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/library/frame_image_dialog.dart';
import 'package:darkmoon/raw_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saves every file with the dialog\'s choice', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = [
      RawFile('C:/roll/a.jpg', DateTime(2026)),
      RawFile('C:/roll/b.jpg', DateTime(2026)),
    ];
    final saved = <String>[];
    FrameImageChoice? used;
    FrameImageResult? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<FrameImageResult>(
                    context: context,
                    builder: (_) => FrameImageDialog(
                      files: files,
                      // No preview: compute() cannot run under the
                      // test's fake clock, and the save path is what
                      // this checks.
                      previewJpegFor: (_) async => null,
                      save: (file, choice) async {
                        saved.add(file.path);
                        used = choice;
                        if (file.path.endsWith('b.jpg')) {
                          throw StateError('nope');
                        }
                        return '${file.path}_Framed.png';
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

    expect(find.text('Frame image'), findsOneWidget);
    expect(find.text('Spacing'), findsOneWidget);
    expect(find.text('No preview for this photo yet.'), findsOneWidget);
    expect(find.text('Save all framed (2)'), findsOneWidget);

    await tester.tap(find.text('3:2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portrait'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('frame-bg-000000')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PNG'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('frame-hex')), '102030');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save all framed (2)'));
    await tester.pumpAndSettle();

    expect(saved, ['C:/roll/a.jpg', 'C:/roll/b.jpg']);
    expect(used!.frame.aspect, FrameAspect.ratio3x2);
    expect(used!.frame.portrait, isTrue);
    expect(used!.frame.ratio, closeTo(2 / 3, 1e-9));
    expect(used!.frame.paddingPercent, 15);
    expect(used!.frame.background, 0xFF102030);
    expect(used!.format, ExportFormat.png);
    expect(used!.longEdge, isNull);
    expect(result!.written, ['C:/roll/a.jpg_Framed.png']);
    expect(result!.failed, ['C:/roll/b.jpg']);
  });
}
