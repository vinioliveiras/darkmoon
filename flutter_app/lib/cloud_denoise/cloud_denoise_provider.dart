import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gemini_denoise_provider.dart';
import 'openai_denoise_provider.dart';
import 'topaz_denoise_provider.dart';

/// A cloud AI denoise provider the user can pick in the AI Denoise dialog's
/// "Cloud AI" tab, paid for with their own API key — a fundamentally
/// different category from the on-device NAFNet-SIDD/PMRID pipelines
/// (`ai_enhance.dart`/`pmrid_denoise.dart`): those run locally, for free,
/// deterministically; these upload the photo to a third party and cost
/// real money per call, so every implementation here must be aggressively
/// cached (`cloud_denoise_cache.dart`) and never called silently.
enum CloudDenoiseProviderKind {
  topaz,
  openai,
  gemini;

  /// True for a provider that regenerates the image through a generative/
  /// diffusion model rather than a purpose-built denoise model — real risk
  /// of altering photo content (faces, text, fine texture), not just
  /// removing noise. Only [topaz] ships a dedicated, non-generative
  /// denoise endpoint; [openai] and [gemini] are general image-editing
  /// APIs steered toward denoising with a fixed prompt (see each
  /// provider's own `_prompt`), which is a materially different risk
  /// profile the dialog UI warns about.
  bool get isGenerative => this != CloudDenoiseProviderKind.topaz;
}

/// Thrown by a [CloudDenoiseProvider] on any failure — network error, bad
/// key, provider-side error response, or an unexpected response shape.
/// [message] is written to be shown directly to the user (English; not
/// wired through l10n since it embeds provider-specific technical detail
/// that wouldn't translate meaningfully).
class CloudDenoiseException implements Exception {
  const CloudDenoiseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One provider's cloud denoise call — implementations
/// (`topaz_denoise_provider.dart`/`openai_denoise_provider.dart`/
/// `gemini_denoise_provider.dart`) each do their own HTTP request/response
/// marshaling; this file only declares the shared shape callers use.
abstract class CloudDenoiseProvider {
  const CloudDenoiseProvider();

  CloudDenoiseProviderKind get kind;

  /// Sends [imageBytes] (a JPEG-encoded render — see
  /// `cloud_denoise_job.dart` for why JPEG, not PNG) to the provider using
  /// [apiKey], returning the denoised result's raw bytes (decodable by
  /// `package:image`). [onStage] reports coarse progress ('uploading',
  /// 'processing', 'downloading') for the loading overlay — providers that
  /// don't have a distinct stage (a single synchronous call) may skip
  /// stages they don't have.
  ///
  /// Async I/O only (HTTP requests) — deliberately NOT run on a separate
  /// isolate the way the ONNX pipelines are, since there's no blocking FFI
  /// call here for an isolate boundary to protect the UI thread from.
  Future<Uint8List> denoise(
    Uint8List imageBytes,
    String apiKey, {
    void Function(String stage)? onStage,
  });
}

/// Resolves [kind] to its concrete implementation.
CloudDenoiseProvider providerFor(CloudDenoiseProviderKind kind) =>
    switch (kind) {
      CloudDenoiseProviderKind.topaz => const TopazDenoiseProvider(),
      CloudDenoiseProviderKind.openai => const OpenAiDenoiseProvider(),
      CloudDenoiseProviderKind.gemini => const GeminiDenoiseProvider(),
    };

/// A short, UI-safe error message from an HTTP error response — the full
/// body can be large (an HTML error page, a verbose JSON error object), so
/// this truncates rather than dumping it wholesale into a dialog/SnackBar.
String httpErrorMessage(String providerName, http.Response response) {
  var body = response.body.trim();
  if (body.length > 300) {
    body = '${body.substring(0, 300)}…';
  }
  return '$providerName error ${response.statusCode}: $body';
}
