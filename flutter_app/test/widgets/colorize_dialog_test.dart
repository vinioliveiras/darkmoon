import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/widgets/colorize_dialog.dart';

void main() {
  group('ColorizeDialog', () {
    testWidgets(
      'defaults the Intensity slider to 100% and applying resolves as '
      'ColorizeChoice(active: true)',
      (tester) async {
        ColorizeChoice? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showDialog<ColorizeChoice>(
                        context: context,
                        builder: (_) => const ColorizeDialog(active: false),
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

        expect(find.text('100%'), findsOneWidget);
        // Not active yet — no "Remove colorization" button.
        expect(find.text('Remove colorization'), findsNothing);

        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();

        expect(result, isA<ColorizeChoice>());
        expect(result!.active, isTrue);
        expect(result!.intensityPercent, 100);
      },
    );

    testWidgets(
      'dragging the Intensity slider down then applying resolves with '
      'the lower amount',
      (tester) async {
        ColorizeChoice? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showDialog<ColorizeChoice>(
                        context: context,
                        builder: (_) => const ColorizeDialog(active: false),
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

        await tester.drag(find.byType(Slider), const Offset(-200, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();

        expect(result!.active, isTrue);
        expect(result!.intensityPercent, lessThan(100));
      },
    );

    testWidgets(
      '"Remove colorization" resolves as ColorizeChoice(active: false)',
      (tester) async {
        ColorizeChoice? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showDialog<ColorizeChoice>(
                        context: context,
                        builder: (_) => const ColorizeDialog(
                          active: true,
                          intensityPercent: 80,
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

        expect(find.text('80%'), findsOneWidget);
        await tester.tap(find.text('Remove colorization'));
        await tester.pumpAndSettle();

        expect(result, isA<ColorizeChoice>());
        expect(result!.active, isFalse);
      },
    );
  });
}
