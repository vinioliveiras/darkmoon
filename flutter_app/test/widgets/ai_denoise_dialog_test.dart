import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/render/ai_denoise.dart';
import 'package:darkmoon/widgets/ai_denoise_dialog.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  AiDenoiseLevel? initialLevel,
  bool neuralEnhanceActive = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<AiDenoiseChoice>(
                context: context,
                builder: (_) => AiDenoiseDialog(
                  initialLevel: initialLevel,
                  neuralEnhanceActive: neuralEnhanceActive,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('AiDenoiseDialog', () {
    testWidgets('opens on the Classic tab by default, with the initial '
        'level preselected', (tester) async {
      await _openDialog(tester, initialLevel: AiDenoiseLevel.medium);

      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Enhance'), findsOneWidget);
      // Both tabs' content are mounted (TabBarView doesn't lazily build),
      // so the Classic levels are findable without switching tabs.
      expect(find.text('Medium'), findsOneWidget);
    });

    testWidgets('opens on the Enhance tab when it was already active', (
      tester,
    ) async {
      await _openDialog(tester, neuralEnhanceActive: true);
      await tester.pumpAndSettle();

      expect(find.text('Denoise + Upscale'), findsOneWidget);
    });

    testWidgets(
      'picking a Classic level then applying resolves as '
      'ClassicDenoiseChoice',
      (tester) async {
        AiDenoiseChoice? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showDialog<AiDenoiseChoice>(
                        context: context,
                        builder: (_) => const AiDenoiseDialog(
                          initialLevel: null,
                          neuralEnhanceActive: false,
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

        await tester.tap(find.text('Strong'));
        await tester.pump();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();

        expect(result, isA<ClassicDenoiseChoice>());
        expect((result as ClassicDenoiseChoice).level, AiDenoiseLevel.strong);
      },
    );

    testWidgets(
      'switching to Enhance and turning it on resolves as '
      'NeuralEnhanceChoice(true), even though the dialog opened on Classic',
      (tester) async {
        AiDenoiseChoice? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showDialog<AiDenoiseChoice>(
                        context: context,
                        builder: (_) => const AiDenoiseDialog(
                          initialLevel: AiDenoiseLevel.light,
                          neuralEnhanceActive: false,
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

        await tester.tap(find.text('Enhance'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Denoise + Upscale'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();

        expect(result, isA<NeuralEnhanceChoice>());
        expect((result as NeuralEnhanceChoice).active, isTrue);
      },
    );

    testWidgets('cancel resolves with null (no choice)', (tester) async {
      AiDenoiseChoice? result = const ClassicDenoiseChoice(
        AiDenoiseLevel.light,
      ); // seeded with a non-null sentinel so `null` below is meaningful
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<AiDenoiseChoice>(
                      context: context,
                      builder: (_) => const AiDenoiseDialog(
                        initialLevel: null,
                        neuralEnhanceActive: false,
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

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });
}
