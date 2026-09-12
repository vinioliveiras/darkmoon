import 'package:darkmoon/export/frame.dart';
import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/widgets/export_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ExportOptions?> open(
    WidgetTester tester,
    Future<void> Function(WidgetTester) drive,
  ) async {
    ExportOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<ExportOptions>(
                    context: context,
                    builder: (_) => const ExportOptionsDialog(
                      nativeWidth: 6000,
                      nativeHeight: 4000,
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
    await drive(tester);
    await tester.ensureVisible(find.text('Export').last);
    await tester.tap(find.text('Export').last);
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('the frame is off unless switched on', (tester) async {
    final options = await open(tester, (_) async {});
    expect(options, isNotNull);
    expect(options!.frame, isNull);
  });

  testWidgets('switching the frame on exports the chosen border', (
    tester,
  ) async {
    final options = await open(tester, (tester) async {
      await tester.ensureVisible(find.text('Frame'));
      await tester.tap(find.text('Frame'));
      await tester.pumpAndSettle();
      expect(find.text('Border'), findsOneWidget);
      await tester.ensureVisible(find.text('1:1'));
      await tester.tap(find.text('1:1'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('frame-bg-ff000000')));
      await tester.tap(find.byKey(const Key('frame-bg-ff000000')));
      await tester.pumpAndSettle();
    });
    final frame = options!.frame;
    expect(frame, isNotNull);
    expect(frame!.paddingPercent, FrameOptions.defaultPaddingPercent);
    expect(frame.aspect, FrameAspect.square);
    expect(frame.background, 0xFF000000);
    // Rapid export (the default) keeps the frame too.
    expect(options.scalePercent, isNotNull);
  });
}
