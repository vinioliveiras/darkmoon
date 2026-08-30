import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/render/ai_denoise.dart';
import 'package:darkmoon/widgets/ai_denoise_dialog.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  AiDenoiseLevel? initialLevel,
  bool neuralDenoise = false,
  bool neuralUpscale = false,
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
                  neuralDenoise: neuralDenoise,
                  neuralUpscale: neuralUpscale,
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
      // Both tabs' content are mounted (IndexedStack doesn't lazily
      // build), so the Classic levels are findable without switching tabs.
      expect(find.text('Medium'), findsOneWidget);
    });

    testWidgets('opens on the Enhance tab when either toggle was already '
        'active', (tester) async {
      await _openDialog(tester, neuralUpscale: true);
      await tester.pumpAndSettle();

      expect(find.text('Denoise'), findsOneWidget);
      expect(find.text('Upscale 2x'), findsOneWidget);
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
                          neuralDenoise: false,
                          neuralUpscale: false,
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
      'switching to Enhance and turning Upscale on resolves as '
      'NeuralEnhanceChoice(upscale: true), even though the dialog opened '
      'on Classic',
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
                          neuralDenoise: false,
                          neuralUpscale: false,
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
        await tester.tap(find.text('Upscale 2x'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();

        expect(result, isA<NeuralEnhanceChoice>());
        final choice = result as NeuralEnhanceChoice;
        expect(choice.denoise, isFalse);
        expect(choice.upscale, isTrue);
        expect(choice.active, isTrue);
      },
    );

    testWidgets(
      'checking both Denoise and Upscale resolves as '
      'NeuralEnhanceChoice(denoise: true, upscale: true)',
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
                          neuralDenoise: false,
                          neuralUpscale: false,
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
        await tester.tap(find.text('Denoise'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Upscale 2x'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();

        expect(result, isA<NeuralEnhanceChoice>());
        final choice = result as NeuralEnhanceChoice;
        expect(choice.denoise, isTrue);
        expect(choice.upscale, isTrue);
      },
    );

    testWidgets(
      'unchecking the only active Enhance toggle resolves as '
      'ClassicDenoiseChoice(null) — the same "nothing selected" state '
      'either tab collapses to',
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
                          neuralDenoise: true,
                          neuralUpscale: false,
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

        // Opens straight on the Enhance tab since a toggle was preselected.
        await tester.tap(find.text('Denoise'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();

        expect(result, isA<ClassicDenoiseChoice>());
        expect((result as ClassicDenoiseChoice).level, isNull);
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
                        neuralDenoise: false,
                        neuralUpscale: false,
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
