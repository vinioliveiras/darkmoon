import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:darkmoon/catalog/ai_enhance_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const photoPath = '/photos/a.raf';
  final modified = DateTime.utc(2026, 9, 3, 12, 0, 0);

  String key({
    bool denoise = true,
    bool upscale = false,
    bool colorize = false,
    int colorizeIntensityPercent = 0,
    int denoiseStrengthPercent = 100,
  }) => aiEnhanceCacheKeyForTest(
    photoPath,
    modified,
    1234,
    denoise: denoise,
    upscale: upscale,
    denoiseStrengthPercent: denoiseStrengthPercent,
    colorize: colorize,
    colorizeIntensityPercent: colorizeIntensityPercent,
  );

  group('AI Enhance cache key, colorize combination', () {
    // Colorize became a pass inside this pipeline on 2026-09-03. Folding
    // its inputs into the key unconditionally would have changed every
    // existing key and orphaned every cached result on disk — and each one
    // costs minutes of inference to rebuild. The tag only grows when
    // colorize actually ran.
    test('a colorize-free run keys the same with the option present', () {
      expect(key(), key(colorize: false, colorizeIntensityPercent: 0));
      expect(
        key(),
        key(colorize: false, colorizeIntensityPercent: 80),
        reason: 'the intensity must not leak into the key when colorize is off',
      );
    });

    test('the colorize-free key still matches the documented format', () {
      // Rebuilt here from the format the cache documents, independently of
      // _modeTag/_entryKey — so a refactor that quietly reorders or
      // reformats the tag (this change reordered its parameters) shows up
      // as a failure rather than as every user's Enhance cache silently
      // going cold.
      const modeTag = 'd1s100u0q0r0g0a50mdefault';
      final raw =
          '$photoPath|${modified.microsecondsSinceEpoch}|1234|'
          '$modeTag|v$aiEnhanceCacheVersion';
      expect(key(), sha1.convert(utf8.encode(raw)).toString());
    });

    test('turning colorize on is a distinct entry', () {
      expect(key(colorize: true, colorizeIntensityPercent: 100), isNot(key()));
    });

    test('each colorize intensity is its own entry', () {
      expect(
        key(colorize: true, colorizeIntensityPercent: 100),
        isNot(key(colorize: true, colorizeIntensityPercent: 60)),
      );
    });

    test('colorize does not collide across denoise settings', () {
      expect(
        key(colorize: true, colorizeIntensityPercent: 100),
        isNot(
          key(
            colorize: true,
            colorizeIntensityPercent: 100,
            denoiseStrengthPercent: 50,
          ),
        ),
      );
      expect(
        key(colorize: true, colorizeIntensityPercent: 100),
        isNot(
          key(colorize: true, colorizeIntensityPercent: 100, upscale: true),
        ),
      );
    });

    test('the same configuration keys stably', () {
      expect(
        key(colorize: true, colorizeIntensityPercent: 75, upscale: true),
        key(colorize: true, colorizeIntensityPercent: 75, upscale: true),
      );
    });
  });
}
