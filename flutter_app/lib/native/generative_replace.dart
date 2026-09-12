// Generative Replace (2026-09-12): the Remove panel's fourth fill, painted
// by a server for a prompt instead of by the local model.
//
// The protocol is Solstice's inpainting middleware (`ai_connector.rs`),
// so the same ComfyUI-backed server people already run for it works
// here unchanged:
//
// - `POST {base}/inpaint` with JSON `{source_id, prompt, negative_prompt,
//   mask_image_base64, seed}` answers `{x, y, color}` — the painted patch
//   as a base64 PNG and where its top-left sits on the source image.
// - A 404 means the server has never seen this source: `POST
//   {base}/upload_source` (multipart: `source_id`, `file` as JPEG) and
//   ask again. The id is the path plus the file's modification time, so
//   an edited file re-uploads and an unchanged one does not.
// - `GET {base}/health` says whether anything is listening.
//
// Only the request/response shape lives here; what to send (the live
// source, the removal's mask) and what to do with the patch (a
// generative [Removal]) is the editor's.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// What the server painted: [png] covers [width] x [height] pixels of
/// the uploaded source starting at ([x], [y]).
class GenerativePatch {
  const GenerativePatch({
    required this.png,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final Uint8List png;
  final int x;
  final int y;
  final int width;
  final int height;
}

class GenerativeReplaceException implements Exception {
  const GenerativeReplaceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The negative prompt Solstice sends with every request.
const generativeNegativePrompt = 'blur, low quality, distortion, watermark';

/// Solstice's source id: the path and the file's modification time,
/// hashed — the same photo uploads once, an edited file uploads again.
String generativeSourceId(String path) {
  DateTime? modified;
  try {
    modified = File(path).lastModifiedSync();
  } catch (_) {
    modified = null;
  }
  final stamp = modified?.millisecondsSinceEpoch ?? 0;
  return sha1.convert(utf8.encode('$path|$stamp')).toString();
}

/// Trims the address the user typed into a base URL without a trailing
/// slash, adding the scheme when it is missing.
String normalizeGenerativeBaseUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return url;
  if (!url.contains('://')) url = 'http://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// True when something answers at [baseUrl]'s `/health`.
Future<bool> generativeServerReachable(
  String baseUrl, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final response = await c
        .get(Uri.parse('${normalizeGenerativeBaseUrl(baseUrl)}/health'))
        .timeout(const Duration(seconds: 5));
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (_) {
    return false;
  } finally {
    if (client == null) c.close();
  }
}

/// Asks the server at [baseUrl] to paint [prompt] into the white area of
/// [maskPng] on the source [sourceJpeg] (uploaded on demand under
/// [sourceId]). Throws [GenerativeReplaceException] with the server's
/// own message when it refuses.
Future<GenerativePatch> requestGenerativeReplace({
  required String baseUrl,
  required String sourceId,
  required Uint8List sourceJpeg,
  required Uint8List maskPng,
  required String prompt,
  String? token,
  int seed = 0,
  http.Client? client,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final base = normalizeGenerativeBaseUrl(baseUrl);
  if (base.isEmpty) {
    throw const GenerativeReplaceException('no server address');
  }
  final c = client ?? http.Client();
  try {
    final headers = {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final body = jsonEncode({
      'source_id': sourceId,
      'prompt': prompt,
      'negative_prompt': generativeNegativePrompt,
      'mask_image_base64': base64Encode(maskPng),
      'seed': seed,
    });
    final inpaint = Uri.parse('$base/inpaint');
    var response = await c
        .post(inpaint, headers: headers, body: body)
        .timeout(timeout);
    if (response.statusCode == 404) {
      final upload = http.MultipartRequest(
        'POST',
        Uri.parse('$base/upload_source'),
      );
      if (token != null && token.isNotEmpty) {
        upload.headers['Authorization'] = 'Bearer $token';
      }
      upload.fields['source_id'] = sourceId;
      upload.files.add(
        http.MultipartFile.fromBytes(
          'file',
          sourceJpeg,
          filename: 'source.jpg',
        ),
      );
      final uploaded = await http.Response.fromStream(
        await c.send(upload).timeout(timeout),
      );
      if (uploaded.statusCode < 200 || uploaded.statusCode >= 300) {
        throw GenerativeReplaceException(
          'upload failed: ${_serverMessage(uploaded)}',
        );
      }
      response = await c
          .post(inpaint, headers: headers, body: body)
          .timeout(timeout);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GenerativeReplaceException(_serverMessage(response));
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const GenerativeReplaceException('unreadable reply');
    }
    final color = json['color'];
    if (color is! String) {
      throw const GenerativeReplaceException('reply carries no patch');
    }
    final png = base64Decode(color);
    final decoded = img.decodeImage(png);
    if (decoded == null) {
      throw const GenerativeReplaceException('patch is not an image');
    }
    return GenerativePatch(
      png: png,
      x: (json['x'] as num?)?.toInt() ?? 0,
      y: (json['y'] as num?)?.toInt() ?? 0,
      width: decoded.width,
      height: decoded.height,
    );
  } finally {
    if (client == null) c.close();
  }
}

String _serverMessage(http.Response response) {
  final text = response.body.trim();
  final short = text.length > 200 ? '${text.substring(0, 200)}…' : text;
  return 'HTTP ${response.statusCode}${short.isEmpty ? '' : ': $short'}';
}

/// The live source as the JPEG the server keeps — run through `compute`,
/// the encode of a preview-sized frame is a few hundred milliseconds.
Uint8List encodeRgbAsJpeg(({Uint8List rgb, int width, int height}) args) {
  final image = img.Image.fromBytes(
    width: args.width,
    height: args.height,
    bytes: args.rgb.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}
