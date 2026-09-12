import 'dart:typed_data';

import 'package:darkmoon/render/ai_denoise.dart';
import 'package:darkmoon/render/color_grading.dart';
import 'package:darkmoon/render/color_mixer.dart';
import 'package:darkmoon/render/color_profile.dart';
import 'package:darkmoon/render/gpu/gpu_stage_cache.dart';
import 'package:darkmoon/render/grain.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:darkmoon/render/sharpen.dart';
import 'package:darkmoon/render/tone_curve.dart';
import 'package:darkmoon/render/vignette.dart';
import 'package:flutter_test/flutter_test.dart';

// Pins which RenderParams field invalidates which cache boundary. This is
// the whole correctness contract of GpuStageCache: a field consumed before
// a boundary that does not change its key would resume from a stale image.
// Every field RenderParams has is listed in exactly one of the three sets
// below; a new field that lands in none fails the coverage test at the
// bottom.

const _src = 0x1234abcd;
const _w = 640, _h = 480;

String _k1(RenderParams p) =>
    GpuStageCache.keyFor(GpuStageBoundary.afterAiDenoise, _src, _w, _h, p);
String _k2(RenderParams p) =>
    GpuStageCache.keyFor(GpuStageBoundary.afterDehaze, _src, _w, _h, p);

final _profile = ColorProfile(
  tone: List<double>.generate(33, (i) => i / 32 * 0.9),
  hueShift: List<double>.filled(24, 3),
  satMul: List<double>.filled(24, 1.1),
  lumMul: List<double>.filled(24, 1),
  id: 7,
);

final _profileSameIdOtherTone = ColorProfile(
  tone: List<double>.generate(33, (i) => i / 32),
  hueShift: List<double>.filled(24, 3),
  satMul: List<double>.filled(24, 1.1),
  lumMul: List<double>.filled(24, 1),
  id: 7,
);

/// Fields read before afterAiDenoise: a change must miss both boundaries.
final Map<String, RenderParams> _beforeAiDenoise = {
  'temperature': const RenderParams(temperature: 6200),
  'tint': const RenderParams(tint: 8),
  'asShotKelvin': const RenderParams(asShotKelvin: 4800),
  'asShotTint': const RenderParams(asShotTint: -3),
  'exposure': const RenderParams(exposure: 12),
  'aiDenoise': const RenderParams(
    aiDenoise: AiDenoiseParams(level: AiDenoiseLevel.medium),
  ),
  'renderScale': const RenderParams().withRenderScaleFor(4000, 3000),
};

/// Fields read between the two boundaries: a change keeps afterAiDenoise
/// and misses afterDehaze.
final Map<String, RenderParams> _betweenBoundaries = {
  'sharpen.amount': const RenderParams(sharpen: SharpenParams(amount: 70)),
  'sharpen.radius': const RenderParams(sharpen: SharpenParams(radius: 2.5)),
  'sharpen.detail': const RenderParams(sharpen: SharpenParams(detail: 60)),
  'sharpen.masking': const RenderParams(sharpen: SharpenParams(masking: 30)),
  'texture': const RenderParams(texture: 25),
  'clarity': const RenderParams(clarity: 25),
  'baseContrast': const RenderParams(baseContrast: 0),
  'colorProfileStrength': const RenderParams(colorProfileStrength: 0.4),
  'colorProfile': RenderParams(colorProfile: _profile),
  'dehaze': const RenderParams(dehaze: 30),
};

/// Fields read only after afterDehaze: a change hits both boundaries.
final Map<String, RenderParams> _afterDehaze = {
  'brightness': const RenderParams(brightness: 10),
  'contrast': const RenderParams(contrast: 20),
  'highlights': const RenderParams(highlights: -30),
  'shadows': const RenderParams(shadows: 30),
  'whites': const RenderParams(whites: 15),
  'blacks': const RenderParams(blacks: -15),
  'vibrance': const RenderParams(vibrance: 20),
  'saturationBoost': const RenderParams(saturationBoost: 0.5),
  'saturation': const RenderParams(saturation: 20),
  'curves': RenderParams(
    curves: PhotoCurves(
      tone: const [CurvePoint(0, 0), CurvePoint(0.5, 0.6), CurvePoint(1, 1)],
    ),
  ),
  'parametricCurve': const RenderParams(
    parametricCurve: ParametricCurve(shadows: 20),
  ),
  'colorMixer': const RenderParams(
    colorMixer: ColorMixerValues(red: ChannelAdjust(saturation: 20)),
  ),
  'colorGrading': const RenderParams(
    colorGrading: ColorGradingValues(
      shadows: GradeRange(hue: 200, saturation: 20),
    ),
  ),
  'vignette': const RenderParams(vignette: VignetteParams(amount: -30)),
  'grain': const RenderParams(grain: GrainParams(amount: 30)),
};

void main() {
  final base = const RenderParams();
  final base1 = _k1(base);
  final base2 = _k2(base);

  group('fields consumed before afterAiDenoise miss both boundaries', () {
    for (final entry in _beforeAiDenoise.entries) {
      test(entry.key, () {
        expect(_k1(entry.value), isNot(base1));
        expect(_k2(entry.value), isNot(base2));
      });
    }
  });

  group('fields consumed between the boundaries keep afterAiDenoise and '
      'miss afterDehaze', () {
    for (final entry in _betweenBoundaries.entries) {
      test(entry.key, () {
        expect(_k1(entry.value), base1);
        expect(_k2(entry.value), isNot(base2));
      });
    }
  });

  group('fields consumed after afterDehaze hit both boundaries', () {
    for (final entry in _afterDehaze.entries) {
      test(entry.key, () {
        expect(_k1(entry.value), base1);
        expect(_k2(entry.value), base2);
      });
    }
  });

  test('a profile edited under the same id is a different key', () {
    expect(
      _k2(RenderParams(colorProfile: _profile)),
      isNot(_k2(RenderParams(colorProfile: _profileSameIdOtherTone))),
    );
  });

  test('source and frame size are part of every key', () {
    final other = GpuStageCache.keyFor(
      GpuStageBoundary.afterDehaze,
      _src + 1,
      _w,
      _h,
      base,
    );
    expect(other, isNot(base2));
    final otherSize = GpuStageCache.keyFor(
      GpuStageBoundary.afterDehaze,
      _src,
      _w,
      _h + 1,
      base,
    );
    expect(otherSize, isNot(base2));
  });

  test('every RenderParams field is classified above', () {
    // RenderParams has no reflection; the field count is pinned by hand so
    // a new field trips this test and sends its author to gpu_stage_cache.
    const fieldsInRenderParams = 29;
    final classified =
        _beforeAiDenoise.length +
        _betweenBoundaries.length +
        _afterDehaze.length -
        3; // sharpen's four entries are one field
    expect(
      classified,
      fieldsInRenderParams,
      reason:
          'RenderParams gained or lost a field: classify it in this test '
          'and, if a GPU stage before Dehaze reads it, in GpuStageCache.keyFor',
    );
  });

  group('sourceFingerprint', () {
    test('is stable for equal content in a different buffer', () {
      final a = Uint8List.fromList(List.generate(3000, (i) => (i * 7) & 0xff));
      final b = Uint8List.fromList(a);
      expect(
        GpuStageCache.sourceFingerprint(a, 50, 20),
        GpuStageCache.sourceFingerprint(b, 50, 20),
      );
    });

    test('changes with content, size and dimensions', () {
      final a = Uint8List.fromList(List.generate(3000, (i) => (i * 7) & 0xff));
      final b = Uint8List.fromList(a)..[2999] = 0;
      final c = Uint8List.fromList(a)..[1] = 0;
      expect(
        GpuStageCache.sourceFingerprint(a, 50, 20),
        isNot(GpuStageCache.sourceFingerprint(b, 50, 20)),
      );
      expect(
        GpuStageCache.sourceFingerprint(a, 50, 20),
        isNot(GpuStageCache.sourceFingerprint(c, 50, 20)),
      );
      expect(
        GpuStageCache.sourceFingerprint(a, 50, 20),
        isNot(GpuStageCache.sourceFingerprint(a, 20, 50)),
      );
      final longer = Uint8List(3003)..setAll(0, a);
      expect(
        GpuStageCache.sourceFingerprint(a, 50, 20),
        isNot(GpuStageCache.sourceFingerprint(longer, 50, 20)),
      );
    });

    test('a large buffer is sampled, and its last bytes still count', () {
      final a = Uint8List(3 * 4000 * 3000);
      for (var i = 0; i < a.length; i += 97) {
        a[i] = i & 0xff;
      }
      final b = Uint8List.fromList(a)..[a.length - 1] = 200;
      expect(
        GpuStageCache.sourceFingerprint(a, 4000, 3000),
        isNot(GpuStageCache.sourceFingerprint(b, 4000, 3000)),
      );
    });
  });
}
