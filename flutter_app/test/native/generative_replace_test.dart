import 'dart:convert';
import 'dart:typed_data';

import 'package:darkmoon/native/generative_replace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

Uint8List _png(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(10, 200, 30));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  test('the base URL is normalised', () {
    expect(
      normalizeGenerativeBaseUrl(' 127.0.0.1:8000/ '),
      'http://127.0.0.1:8000',
    );
    expect(
      normalizeGenerativeBaseUrl('https://gen.example//'),
      'https://gen.example',
    );
    expect(normalizeGenerativeBaseUrl(''), '');
  });

  test('a known source is painted with one request', () async {
    final patch = _png(12, 8);
    late Map<String, dynamic> sent;
    final client = MockClient((request) async {
      expect(request.url.path, '/inpaint');
      expect(request.headers['Authorization'], 'Bearer tok');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'x': 40, 'y': 30, 'color': base64Encode(patch)}),
        200,
      );
    });
    final result = await requestGenerativeReplace(
      baseUrl: 'http://srv:9',
      sourceId: 'abc',
      sourceJpeg: Uint8List.fromList([1, 2, 3]),
      maskPng: _png(4, 4),
      prompt: 'grass',
      token: 'tok',
      client: client,
    );
    expect(sent['source_id'], 'abc');
    expect(sent['prompt'], 'grass');
    expect(sent['negative_prompt'], generativeNegativePrompt);
    expect(sent['mask_image_base64'], base64Encode(_png(4, 4)));
    expect(result.x, 40);
    expect(result.y, 30);
    expect(result.width, 12);
    expect(result.height, 8);
    expect(result.png, patch);
  });

  test('a 404 uploads the source and asks again', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.url.path == '/inpaint' && calls.length == 1) {
        return http.Response('unknown source', 404);
      }
      if (request.url.path == '/upload_source') {
        expect(request.headers['content-type'], startsWith('multipart/'));
        return http.Response('ok', 200);
      }
      return http.Response(
        jsonEncode({'x': 0, 'y': 0, 'color': base64Encode(_png(2, 2))}),
        200,
      );
    });
    final result = await requestGenerativeReplace(
      baseUrl: 'srv:9',
      sourceId: 'abc',
      sourceJpeg: Uint8List.fromList([1, 2, 3]),
      maskPng: _png(2, 2),
      prompt: 'sky',
      client: client,
    );
    expect(calls, ['POST /inpaint', 'POST /upload_source', 'POST /inpaint']);
    expect(result.width, 2);
  });

  test('a refusal surfaces the server message', () async {
    final client = MockClient(
      (request) async => http.Response('model not loaded', 500),
    );
    expect(
      () => requestGenerativeReplace(
        baseUrl: 'http://srv',
        sourceId: 'abc',
        sourceJpeg: Uint8List(0),
        maskPng: _png(2, 2),
        prompt: 'x',
        client: client,
      ),
      throwsA(
        isA<GenerativeReplaceException>().having(
          (e) => e.message,
          'message',
          contains('model not loaded'),
        ),
      ),
    );
  });

  test('health answers false when nothing listens', () async {
    final client = MockClient((_) async => throw Exception('refused'));
    expect(
      await generativeServerReachable('http://srv', client: client),
      isFalse,
    );
    final up = MockClient((_) async => http.Response('ok', 200));
    expect(await generativeServerReachable('http://srv', client: up), isTrue);
  });
}
