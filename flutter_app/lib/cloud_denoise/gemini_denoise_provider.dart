import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloud_denoise_provider.dart';

/// Google's Gemini image-editing API (`gemini-3.1-flash-image` via the
/// `/v1beta/interactions` endpoint) steered toward denoising with a fixed
/// prompt — like OpenAI's provider, this is **generative** (see
/// [CloudDenoiseProviderKind.isGenerative]), not a purpose-built denoiser:
/// it regenerates the image from the prompt + input image, which carries
/// real risk of altering fine detail rather than just removing noise.
///
/// Response shape defensively checks two possible wrappings
/// (`interaction.output_image.data` and a bare `output_image.data`) since
/// this is a newer, less battle-tested endpoint than OpenAI's — if
/// Google's API shape has moved since this was written, the error message
/// below should make that obvious rather than failing silently.
class GeminiDenoiseProvider extends CloudDenoiseProvider {
  const GeminiDenoiseProvider();

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/interactions';
  static const _model = 'gemini-3.1-flash-image';

  static const _prompt =
      'Remove sensor noise and film grain from this photo. Preserve the '
      'exact composition, all details, colors, faces, and any visible text '
      'exactly as they are — do not add, remove, reinterpret, or stylize '
      'anything. Only reduce noise and grain.';

  @override
  CloudDenoiseProviderKind get kind => CloudDenoiseProviderKind.gemini;

  @override
  Future<Uint8List> denoise(
    Uint8List imageBytes,
    String apiKey, {
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('uploading');
    final body = jsonEncode({
      'model': _model,
      'input': [
        {
          'type': 'image',
          'mime_type': 'image/jpeg',
          'data': base64Encode(imageBytes),
        },
        {'type': 'text', 'text': _prompt},
      ],
    });

    onStage?.call('processing');
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'x-goog-api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudDenoiseException(httpErrorMessage('Gemini', response));
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final outputImage =
        (decoded['interaction'] as Map<String, dynamic>?)?['output_image']
            ?? decoded['output_image'];
    final data = (outputImage is Map) ? outputImage['data'] as String? : null;
    if (data == null) {
      throw const CloudDenoiseException(
        'Gemini response did not include image data at '
        'interaction.output_image.data — the API may have changed; check '
        'the response format against Gemini\'s current image-editing docs.',
      );
    }
    return base64Decode(data);
  }
}
