import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:darkmoon/cloud_denoise/cloud_denoise_provider.dart';
import 'package:darkmoon/cloud_denoise/gemini_denoise_provider.dart';
import 'package:darkmoon/cloud_denoise/openai_denoise_provider.dart';
import 'package:darkmoon/cloud_denoise/topaz_denoise_provider.dart';

void main() {
  group('CloudDenoiseProviderKind.isGenerative', () {
    test('only Topaz has a dedicated, non-generative denoise model', () {
      expect(CloudDenoiseProviderKind.topaz.isGenerative, isFalse);
      expect(CloudDenoiseProviderKind.openai.isGenerative, isTrue);
      expect(CloudDenoiseProviderKind.gemini.isGenerative, isTrue);
    });
  });

  group('providerFor', () {
    test('resolves each kind to its matching concrete implementation', () {
      expect(
        providerFor(CloudDenoiseProviderKind.topaz),
        isA<TopazDenoiseProvider>(),
      );
      expect(
        providerFor(CloudDenoiseProviderKind.openai),
        isA<OpenAiDenoiseProvider>(),
      );
      expect(
        providerFor(CloudDenoiseProviderKind.gemini),
        isA<GeminiDenoiseProvider>(),
      );
      expect(
        providerFor(CloudDenoiseProviderKind.topaz).kind,
        CloudDenoiseProviderKind.topaz,
      );
    });
  });

  group('httpErrorMessage', () {
    test('includes the provider name and status code', () {
      final response = http.Response('bad request', 400);
      final message = httpErrorMessage('Topaz', response);
      expect(message, contains('Topaz'));
      expect(message, contains('400'));
      expect(message, contains('bad request'));
    });

    test('truncates a very long error body rather than dumping it whole', () {
      final longBody = 'x' * 1000;
      final response = http.Response(longBody, 500);
      final message = httpErrorMessage('OpenAI', response);
      expect(message.length, lessThan(longBody.length));
      expect(message, endsWith('…'));
    });
  });
}
