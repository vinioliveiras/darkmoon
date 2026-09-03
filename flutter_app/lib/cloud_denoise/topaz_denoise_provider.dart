import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloud_denoise_provider.dart';

/// Topaz Labs' Image API (developer.topazlabs.com) — the one provider here
/// with a purpose-built, non-generative denoise model (not a diffusion
/// model steered by a prompt), so [CloudDenoiseProviderKind.isGenerative]
/// is false for this one: it removes noise/grain without regenerating
/// photo content. Async job API: submit -> poll `/status` every 2s (their
/// own documented interval) -> `/download` once `status == "Completed"`.
class TopazDenoiseProvider extends CloudDenoiseProvider {
  const TopazDenoiseProvider();

  static const _baseUrl = 'https://api.topazlabs.com/image/v1';

  /// Generous but finite — a stuck/abandoned job shouldn't hang the UI
  /// forever. 150 * 2s = 5 minutes, well past any real denoise job's
  /// expected completion time.
  static const _maxPollAttempts = 150;

  @override
  CloudDenoiseProviderKind get kind => CloudDenoiseProviderKind.topaz;

  @override
  Future<Uint8List> denoise(
    Uint8List imageBytes,
    String apiKey, {
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('uploading');
    final submitRequest =
        http.MultipartRequest('POST', Uri.parse('$_baseUrl/denoise/async'))
          ..headers['X-API-Key'] = apiKey
          ..fields['model'] = 'Normal'
          ..fields['output_format'] = 'png'
          ..files.add(
            http.MultipartFile.fromBytes(
              'image',
              imageBytes,
              filename: 'photo.jpg',
            ),
          );
    final submitResponse = await http.Response.fromStream(
      await submitRequest.send(),
    );
    if (submitResponse.statusCode < 200 || submitResponse.statusCode >= 300) {
      throw CloudDenoiseException(httpErrorMessage('Topaz', submitResponse));
    }
    final processId =
        (jsonDecode(submitResponse.body) as Map<String, dynamic>)['process_id']
            as String?;
    if (processId == null) {
      throw const CloudDenoiseException(
        'Topaz did not return a process id — cannot check job status.',
      );
    }

    onStage?.call('processing');
    for (var attempt = 0; ; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final statusResponse = await http.get(
        Uri.parse('$_baseUrl/status/$processId'),
        headers: {'X-API-Key': apiKey},
      );
      if (statusResponse.statusCode < 200 || statusResponse.statusCode >= 300) {
        throw CloudDenoiseException(httpErrorMessage('Topaz', statusResponse));
      }
      final status =
          (jsonDecode(statusResponse.body) as Map<String, dynamic>)['status']
              as String?;
      if (status == 'Completed') {
        break;
      }
      if (status == 'Failed' || status == 'Cancelled') {
        throw CloudDenoiseException('Topaz job $status.');
      }
      if (attempt >= _maxPollAttempts) {
        throw const CloudDenoiseException(
          'Topaz job timed out (still processing after 5 minutes).',
        );
      }
    }

    onStage?.call('downloading');
    final downloadResponse = await http.get(
      Uri.parse('$_baseUrl/download/$processId'),
      headers: {'X-API-Key': apiKey},
    );
    if (downloadResponse.statusCode < 200 ||
        downloadResponse.statusCode >= 300) {
      throw CloudDenoiseException(httpErrorMessage('Topaz', downloadResponse));
    }
    final downloadUrl =
        (jsonDecode(downloadResponse.body) as Map<String, dynamic>)['url']
            as String?;
    if (downloadUrl == null) {
      throw const CloudDenoiseException(
        'Topaz did not return a download URL for the finished job.',
      );
    }
    final imageResponse = await http.get(Uri.parse(downloadUrl));
    if (imageResponse.statusCode < 200 || imageResponse.statusCode >= 300) {
      throw const CloudDenoiseException(
        'Failed to download the denoised image from Topaz.',
      );
    }
    return imageResponse.bodyBytes;
  }
}
