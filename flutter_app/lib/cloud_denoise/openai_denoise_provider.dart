import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloud_denoise_provider.dart';

/// OpenAI's image-editing endpoint (`gpt-image-1` via `/v1/images/edits`)
/// steered toward denoising with a fixed prompt — this is a **generative**
/// model (see [CloudDenoiseProviderKind.isGenerative]), not a purpose-built
/// denoiser like Topaz: it regenerates the image from the prompt + input,
/// which carries real risk of altering fine detail (faces, text, texture)
/// rather than just removing noise. The prompt is intentionally fixed, not
/// user-editable — this feature is "denoise via a paid cloud model," not a
/// general AI photo-editing prompt box.
class OpenAiDenoiseProvider extends CloudDenoiseProvider {
  const OpenAiDenoiseProvider();

  static const _endpoint = 'https://api.openai.com/v1/images/edits';

  static const _prompt =
      'Remove sensor noise and film grain from this photo. Preserve the '
      'exact composition, all details, colors, faces, and any visible text '
      'exactly as they are — do not add, remove, reinterpret, or stylize '
      'anything. Only reduce noise and grain.';

  @override
  CloudDenoiseProviderKind get kind => CloudDenoiseProviderKind.openai;

  @override
  Future<Uint8List> denoise(
    Uint8List imageBytes,
    String apiKey, {
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('uploading');
    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = 'gpt-image-1'
      ..fields['prompt'] = _prompt
      ..fields['n'] = '1'
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'photo.jpg',
        ),
      );

    onStage?.call('processing');
    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudDenoiseException(httpErrorMessage('OpenAI', response));
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = (decoded['data'] as List?)?.cast<Map<String, dynamic>>();
    final first = (data != null && data.isNotEmpty) ? data.first : null;

    final b64 = first?['b64_json'] as String?;
    if (b64 != null) {
      return base64Decode(b64);
    }

    final url = first?['url'] as String?;
    if (url != null) {
      onStage?.call('downloading');
      final imageResponse = await http.get(Uri.parse(url));
      if (imageResponse.statusCode >= 200 && imageResponse.statusCode < 300) {
        return imageResponse.bodyBytes;
      }
    }

    throw const CloudDenoiseException(
      'OpenAI response did not include an image (no b64_json or url field) '
      '— the API may have changed; check the response format against '
      'OpenAI\'s current /v1/images/edits documentation.',
    );
  }
}
