import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/cloud_denoise/cloud_denoise_provider.dart';
import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/render/ai_denoise.dart';
import 'package:darkmoon/widgets/ai_denoise_dialog.dart';

/// The default test surface (800x600) is shorter than the dialog's
/// Enhance tab now needs once the Amount slider and GPU warning are both
/// showing — same fix `widget_test.dart` already uses. Real app windows
/// are comfortably taller than this in practice; this is purely a test-
/// harness limitation, not a real content-fit problem.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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
      _useTallSurface(tester);
      await _openDialog(tester, initialLevel: AiDenoiseLevel.medium);

      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Enhance'), findsOneWidget);
      // Both tabs' content are mounted (IndexedStack doesn't lazily
      // build), so the Classic levels are findable without switching tabs.
      expect(find.text('Medium'), findsOneWidget);
    });

    testWidgets('opens on the Enhance tab when denoise was already active', (
      tester,
    ) async {
      _useTallSurface(tester);
      await _openDialog(tester, neuralDenoise: true);
      await tester.pumpAndSettle();

      expect(find.text('Denoise'), findsOneWidget);
    });

    testWidgets(
      'opens on the Enhance tab for a photo whose persisted state has '
      'upscale on, with the Upscale toggle and Sharpness slider shown',
      (tester) async {
        _useTallSurface(tester);
        await _openDialog(tester, neuralUpscale: true);
        await tester.pumpAndSettle();

        expect(find.text('Denoise'), findsOneWidget);
        expect(find.text('Upscale 2x'), findsOneWidget);
        // Sharpness slider only appears once Upscale is on — defaults to 0%.
        expect(find.text('Sharpness'), findsOneWidget);
        expect(find.text('0%'), findsOneWidget);
        expect(find.byType(Slider), findsOneWidget);
      },
    );

    testWidgets('Sharpness slider is hidden while Upscale is off', (
      tester,
    ) async {
      _useTallSurface(tester);
      await _openDialog(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enhance'));
      await tester.pumpAndSettle();

      expect(find.text('Sharpness'), findsNothing);
    });

    testWidgets(
      'turning Upscale on then dragging the Sharpness slider above 0 and '
      'applying resolves as NeuralEnhanceChoice(upscaleSharpnessAmount > 0)',
      (tester) async {
        _useTallSurface(tester);
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
        await tester.tap(find.text('Upscale 2x'));
        await tester.pumpAndSettle();
        // Only one Slider is visible here (Denoise, hence its own Amount
        // slider, is off) — drag it roughly to its midpoint.
        await tester.drag(find.byType(Slider), const Offset(200, 0));
        await tester.pumpAndSettle();
        // The Sharpness-active caption only shows once the amount is > 0 —
        // confirms the drag actually registered before Apply is tapped.
        expect(
          find.text(
            'Blends in a slower, more detail-synthesizing model — any '
            'amount above 0% costs ~3.5 minutes per 24MP photo instead of '
            'a few seconds, and can slightly alter (not just sharpen) '
            'very small text or detail.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();

        expect(result, isA<NeuralEnhanceChoice>());
        final choice = result as NeuralEnhanceChoice;
        expect(choice.upscale, isTrue);
        expect(choice.upscaleSharpnessAmount, greaterThan(0));
      },
    );

    testWidgets(
      'turning Restore detail on (without Denoise or Upscale) defaults '
      'its Amount slider to 50% and resolves as NeuralEnhanceChoice('
      'restoreDetail: true)',
      (tester) async {
        _useTallSurface(tester);
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
        await tester.tap(find.text('Restore detail'));
        await tester.pumpAndSettle();

        // Balanced default, per the toggle-always-has-an-amount convention
        // — unlike Sharpness (which defaults to 0%, a real cost cliff).
        expect(find.text('50%'), findsOneWidget);

        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();

        expect(result, isA<NeuralEnhanceChoice>());
        final choice = result as NeuralEnhanceChoice;
        expect(choice.restoreDetail, isTrue);
        expect(choice.restoreDetailAmount, 50);
        expect(choice.denoise, isFalse);
        expect(choice.upscale, isFalse);
        expect(choice.active, isTrue);
      },
    );

    testWidgets('picking a Classic level then applying resolves as '
        'ClassicDenoiseChoice', (tester) async {
      _useTallSurface(tester);
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
    });

    testWidgets('turning Denoise on from the Enhance tab resolves as '
        'NeuralEnhanceChoice(denoise: true), even though the dialog opened '
        'on Classic', (tester) async {
      _useTallSurface(tester);
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
      await tester.tap(find.text('Denoise'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result, isA<NeuralEnhanceChoice>());
      final choice = result as NeuralEnhanceChoice;
      expect(choice.denoise, isTrue);
      expect(choice.active, isTrue);
    });

    testWidgets('unchecking the only active Enhance toggle resolves as '
        'ClassicDenoiseChoice(null) — the same "nothing selected" state '
        'either tab collapses to', (tester) async {
      _useTallSurface(tester);
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
    });

    testWidgets(
      'Cloud AI tab shows the provider dropdown defaulted to Off, and no '
      'token field until a provider is picked',
      (tester) async {
        _useTallSurface(tester);
        await _openDialog(tester);

        await tester.tap(find.text('Cloud AI'));
        await tester.pumpAndSettle();

        expect(find.text('Off'), findsOneWidget);
        expect(find.text('API key'), findsNothing);
      },
    );

    testWidgets(
      'picking Topaz on the Cloud AI tab shows the token field and the '
      'always-on disclosure, but not the generative-risk warning (Topaz '
      'is the one non-generative provider)',
      (tester) async {
        _useTallSurface(tester);
        await _openDialog(tester);

        await tester.tap(find.text('Cloud AI'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Off'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Topaz Labs (Denoise)'));
        await tester.pumpAndSettle();

        expect(find.text('API key'), findsOneWidget);
        expect(
          find.textContaining('Stored only on this device'),
          findsOneWidget,
        );
        expect(
          find.textContaining('regenerates the image from a prompt'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'picking a generative provider (OpenAI) shows the generative-risk '
      'warning',
      (tester) async {
        _useTallSurface(tester);
        await _openDialog(tester);

        await tester.tap(find.text('Cloud AI'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Off'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OpenAI (gpt-image-1)'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('regenerates the image from a prompt'),
          findsOneWidget,
        );
      },
    );

    testWidgets('picking Topaz, entering an API key, and applying resolves as '
        'CloudDenoiseChoice — and switching to Cloud AI clears any Classic '
        'level (all three tabs are mutually exclusive)', (tester) async {
      _useTallSurface(tester);
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
                        initialLevel: AiDenoiseLevel.medium,
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

      await tester.tap(find.text('Cloud AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Topaz Labs (Denoise)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sk-test-token');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result, isA<CloudDenoiseChoice>());
      final choice = result as CloudDenoiseChoice;
      expect(choice.provider, CloudDenoiseProviderKind.topaz);
      expect(choice.apiKey, 'sk-test-token');
      expect(choice.active, isTrue);
    });

    testWidgets('cancel resolves with null (no choice)', (tester) async {
      _useTallSurface(tester);
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
