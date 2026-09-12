import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/render/film_lut_library.dart';
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

    testWidgets('picking a film look resolves with its id', (tester) async {
      ColorizeChoice? result;
      const films = [
        FilmLutEntry(
          id: 2,
          file: 'film_02.png',
          name: 'Portra 400',
          brand: 'Kodak',
          kind: 'negative',
        ),
        FilmLutEntry(
          id: 7,
          file: 'film_07.png',
          name: 'Velvia 50',
          brand: 'Fuji',
          kind: 'slide',
        ),
      ];
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
                      builder: (_) =>
                          const ColorizeDialog(active: false, films: films),
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

      expect(find.text('Film look'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kodak Portra 400'));
      await tester.pumpAndSettle();
      expect(find.text('Kodak Portra 400'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result, isA<ColorizeChoice>());
      expect(result!.active, isTrue);
      expect(result!.filmId, 2);
    });
  });
}
