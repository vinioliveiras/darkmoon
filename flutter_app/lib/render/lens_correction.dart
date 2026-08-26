import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../native/libraw.dart' show RawMetadata;
import 'crop_transform.dart' show GeometryResult;
import 'geometry.dart' show sampleBilinear, sampleBilinearChannel;

/// Lightroom's Lens Corrections panel's Profile tab (geometric distortion
/// + vignetting from a matched lens's calibration data) — kept entirely
/// separate from `vignette.dart`'s artistic Post-Crop Vignette, which the
/// user dials in by eye and has nothing to do with a specific lens's
/// measured optical characteristics. Mixing the two into one params class
/// or one "Vignette" slider would silently fight the user's artistic
/// vignette with an automatic one every time a photo's EXIF happens to
/// match a bundled profile.
class LensCorrectionParams {
  const LensCorrectionParams({
    this.enabled = false,
    this.manualProfileKeyHash,
    this.distortionAmount = 50,
    this.vignetteAmount = 50,
    this.chromaticAberrationAmount = 50,
  });

  final bool enabled;

  /// Hash of a manually-picked [LensProfile]'s [lensProfileKey], or null
  /// to auto-detect from the photo's EXIF (camera/lens metadata). Stored
  /// as a hash rather than the profile's actual maker/model string
  /// because every other per-photo edit value in this app lives in one
  /// flat `Map<String, double>` (`_paramValues` in editor_screen.dart)
  /// that rides through undo/redo history, catalog persistence, and
  /// photo-switching for free — adding a parallel `Map<String, String?>`
  /// just for this one field (like `_photoCurves`/`_photoMasks`) would
  /// mean touching every one of those call sites for a single string.
  /// A deterministic hash (see [lensProfileKeyHash]) rides the existing
  /// double-valued map instead; resolving it back to a [LensProfile] is
  /// an O(n) scan over the bundled database (a few thousand entries at
  /// most), cheap next to an actual render — see [resolveLensProfile].
  final double? manualProfileKeyHash;

  /// 0..100 — blends the distortion correction from full strength (100,
  /// matching the profile's calibration) down to no correction (0),
  /// mirroring Lightroom's own Distortion amount slider under the Profile
  /// checkbox. Defaults to 50 (half-strength) rather than 100 — a lens's
  /// bundled calibration is an approximation of THIS specific copy's real
  /// optics, so starting at full strength risks over-correcting; the user
  /// dials it up if the photo calls for it.
  final double distortionAmount;

  /// 0..100 — same blend, for the vignetting correction. Same half-
  /// strength default as [distortionAmount], for the same reason.
  final double vignetteAmount;

  /// 0..100 — same blend, for the TCA (red/blue channel) correction. Same
  /// half-strength default as [distortionAmount], for the same reason.
  final double chromaticAberrationAmount;

  bool get isIdentity => !enabled;

  LensCorrectionParams copyWith({
    bool? enabled,
    double? manualProfileKeyHash,
    bool clearManualProfile = false,
    double? distortionAmount,
    double? vignetteAmount,
    double? chromaticAberrationAmount,
  }) => LensCorrectionParams(
    enabled: enabled ?? this.enabled,
    manualProfileKeyHash: clearManualProfile
        ? null
        : (manualProfileKeyHash ?? this.manualProfileKeyHash),
    distortionAmount: distortionAmount ?? this.distortionAmount,
    vignetteAmount: vignetteAmount ?? this.vignetteAmount,
    chromaticAberrationAmount:
        chromaticAberrationAmount ?? this.chromaticAberrationAmount,
  );

  /// Builds params from the editor's flat `{sliderName: value}` map, same
  /// convention as [CropTransformParams]/every other adjustment.
  factory LensCorrectionParams.fromValues(Map<String, double> values) {
    const d = LensCorrectionParams();
    final hash = values['LensCorrectionProfileHash'];
    return LensCorrectionParams(
      enabled: (values['LensCorrectionEnabled'] ?? (d.enabled ? 1 : 0)) != 0,
      // 0.0 is the reserved "no manual override" sentinel (see
      // [lensProfileKeyHash], which never returns exactly 0), not a real
      // hash value that needs looking up.
      manualProfileKeyHash: (hash == null || hash == 0.0) ? null : hash,
      distortionAmount: values['LensCorrectionDistortionAmount'] ??
          d.distortionAmount,
      vignetteAmount:
          values['LensCorrectionVignetteAmount'] ?? d.vignetteAmount,
      chromaticAberrationAmount:
          values['LensCorrectionChromaticAberrationAmount'] ??
              d.chromaticAberrationAmount,
    );
  }

  Map<String, double> toValues() => {
    'LensCorrectionEnabled': enabled ? 1 : 0,
    'LensCorrectionProfileHash': manualProfileKeyHash ?? 0.0,
    'LensCorrectionDistortionAmount': distortionAmount,
    'LensCorrectionVignetteAmount': vignetteAmount,
    'LensCorrectionChromaticAberrationAmount': chromaticAberrationAmount,
  };
}

/// One calibrated focal length's distortion coefficients — field meaning
/// depends on [LensProfile.distortionModel] ('a'/'b'/'c' for ptlens,
/// 'k1' for poly3, 'k1'/'k2' for poly5; unused fields are null).
class LensDistortionPoint {
  const LensDistortionPoint({
    required this.focal,
    this.a,
    this.b,
    this.c,
    this.k1,
    this.k2,
  });

  final double focal;
  final double? a;
  final double? b;
  final double? c;
  final double? k1;
  final double? k2;
}

/// One calibrated (focal, aperture) point's vignetting falloff
/// coefficients (the "pa" model — the only one Lensfun's DB actually
/// uses). [distance] (focus distance, meters) is read but not matched on:
/// the bundled DB rarely varies k1..k3 meaningfully across it for a given
/// focal/aperture, and RawMetadata carries no focus-distance field to
/// match against anyway.
class LensVignettingPoint {
  const LensVignettingPoint({
    required this.focal,
    required this.aperture,
    required this.distance,
    required this.k1,
    required this.k2,
    required this.k3,
  });

  final double focal;
  final double aperture;
  final double distance;
  final double k1;
  final double k2;
  final double k3;
}

/// One calibrated focal length's TCA (transverse chromatic aberration)
/// coefficients — red/blue channel radius-scale factors relative to green
/// (the untouched reference channel). [vr]/[vb] are the constant term;
/// Lensfun's 'linear' model only ever has these (the JSON conversion maps
/// its `kr`/`kb` fields into [vr]/[vb] directly, since both mean "multiply
/// the radius by this constant"), while 'poly3' adds [br]/[cr]/[bb]/[cb]
/// as the `r^2`/`r^4` polynomial terms — see [_tcaFactor].
class LensTcaPoint {
  const LensTcaPoint({
    required this.focal,
    required this.vr,
    required this.vb,
    this.br = 0,
    this.cr = 0,
    this.bb = 0,
    this.cb = 0,
  });

  final double focal;
  final double vr;
  final double vb;
  final double br;
  final double cr;
  final double bb;
  final double cb;
}

/// One lens's calibration data, parsed from the bundled
/// `assets/lens_profiles/lensfun_db.json` (itself converted from the
/// Lensfun project's CC BY-SA 3.0 database — see that folder's
/// LICENSE.txt). Deliberately drops everything the app's correction math
/// doesn't use (mount compatibility lists, camera bodies).
class LensProfile {
  const LensProfile({
    required this.maker,
    required this.model,
    required this.mount,
    required this.cropFactor,
    required this.distortionModel,
    required this.distortion,
    required this.vignettingModel,
    required this.vignetting,
    this.tcaModel,
    this.tca = const [],
  });

  final String maker;
  final String model;
  final String? mount;
  final double cropFactor;

  /// 'ptlens', 'poly3', 'poly5', or null if this lens has no distortion
  /// calibration at all (vignetting-only entries do occur).
  final String? distortionModel;
  final List<LensDistortionPoint> distortion;

  /// Always 'pa' when present — see [LensVignettingPoint]'s doc comment.
  final String? vignettingModel;
  final List<LensVignettingPoint> vignetting;

  /// 'linear' or 'poly3' — see [LensTcaPoint]'s doc comment. Null if this
  /// lens has no TCA calibration at all.
  final String? tcaModel;
  final List<LensTcaPoint> tca;

  /// Stable identity for this profile — `"maker|model"`. Used both as the
  /// manual-override picker's value and as [lensProfileKeyHash]'s input.
  String get key => lensProfileKey(maker, model);
}

String lensProfileKey(String maker, String model) => '$maker|$model';

/// Deterministic (FNV-1a, 32-bit) hash of [key] — deliberately NOT Dart's
/// built-in `String.hashCode`, which is explicitly documented as
/// unstable across app runs/versions (hash randomization). A value
/// persisted today via [LensCorrectionParams.manualProfileKeyHash] must
/// still resolve to the same profile after the user restarts the app.
/// Never returns 0 (bumped to 1 in the one-in-four-billion case it would)
/// since 0 is [LensCorrectionParams]'s reserved "no override" sentinel.
double lensProfileKeyHash(String key) {
  const fnvPrime = 0x01000193;
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(key)) {
    hash = (hash ^ byte) & 0xFFFFFFFF;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return (hash == 0 ? 1 : hash).toDouble();
}


/// Loads and caches assets/lens_profiles/lensfun_db.json.
class LensProfileDatabase {
  LensProfileDatabase._();

  static List<LensProfile>? _cached;
  static Future<List<LensProfile>>? _loading;

  static Future<List<LensProfile>> load() {
    final cached = _cached;
    if (cached != null) {
      return Future.value(cached);
    }
    return _loading ??= _loadFromAsset().then((profiles) {
      _cached = profiles;
      return profiles;
    });
  }

  static Future<List<LensProfile>> _loadFromAsset() async {
    final raw = await rootBundle.loadString(
      'assets/lens_profiles/lensfun_db.json',
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final lenses = decoded['lenses'] as List;
    return [
      for (final entry in lenses)
        _decodeLensProfile(entry as Map<String, dynamic>),
    ];
  }

  static LensProfile _decodeLensProfile(Map<String, dynamic> raw) {
    double? d(dynamic v) => (v as num?)?.toDouble();
    return LensProfile(
      maker: raw['maker'] as String,
      model: raw['model'] as String,
      mount: raw['mount'] as String?,
      cropFactor: d(raw['cropFactor']) ?? 1.0,
      distortionModel: raw['distortionModel'] as String?,
      distortion: [
        for (final e in (raw['distortion'] as List? ?? const []))
          LensDistortionPoint(
            focal: d((e as Map<String, dynamic>)['focal']) ?? 0,
            a: d(e['a']),
            b: d(e['b']),
            c: d(e['c']),
            k1: d(e['k1']),
            k2: d(e['k2']),
          ),
      ],
      vignettingModel: raw['vignettingModel'] as String?,
      vignetting: [
        for (final e in (raw['vignetting'] as List? ?? const []))
          LensVignettingPoint(
            focal: d((e as Map<String, dynamic>)['focal']) ?? 0,
            aperture: d(e['aperture']) ?? 0,
            distance: d(e['distance']) ?? 0,
            k1: d(e['k1']) ?? 0,
            k2: d(e['k2']) ?? 0,
            k3: d(e['k3']) ?? 0,
          ),
      ],
      tcaModel: raw['tcaModel'] as String?,
      tca: [
        for (final e in (raw['tca'] as List? ?? const []))
          LensTcaPoint(
            focal: d((e as Map<String, dynamic>)['focal']) ?? 0,
            // 'linear' calibration points only ever carry kr/kb (the JSON's
            // name for a constant-only radius scale) instead of vr/vb --
            // both mean the same thing here, so fold them into one field
            // rather than branching correction math on tcaModel.
            vr: d(e['vr']) ?? d(e['kr']) ?? 1.0,
            vb: d(e['vb']) ?? d(e['kb']) ?? 1.0,
            br: d(e['br']) ?? 0,
            cr: d(e['cr']) ?? 0,
            bb: d(e['bb']) ?? 0,
            cb: d(e['cb']) ?? 0,
          ),
      ],
    );
  }
}


/// Lowercases, collapses whitespace, and strips punctuation/common noise
/// words cameras pad lens names with (marketing suffixes that vary
/// between how a camera body's firmware reports a lens and how Lensfun's
/// contributors named the same lens in the DB) — used by [matchLensProfile]
/// so e.g. "EF24-70mm f/2.8L II USM" lines up with a DB entry spelled
/// "Canon EF 24-70mm f/2.8L II USM".
String _normalizeLensText(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll(RegExp(r'[(),/]'), ' ');
  t = t.replaceAll('-', ' ');
  const noiseWords = [
    'lens',
    'usm',
    'stm',
    'is',
    'ii',
    'iii',
    'iv',
    'af',
    'af-s',
    'af-p',
    'mf',
    'ed',
    'vr',
    'os',
    'dc',
    'di',
    'g',
    'fe',
  ];
  final tokens = t
      .split(RegExp(r'\s+'))
      .where((tok) => tok.isNotEmpty && !noiseWords.contains(tok));
  return tokens.join(' ');
}

/// Token-overlap similarity (0..1) between two already-[_normalizeLensText]d
/// strings — the fraction of [needle]'s tokens that also appear in
/// [haystack], weighted slightly toward longer (more specific) tokens so
/// e.g. a shared focal-length token like "24-70mm" counts for more than a
/// shared single-letter token.
double _tokenOverlapScore(String needle, String haystack) {
  final needleTokens = needle.split(' ').where((t) => t.isNotEmpty).toList();
  if (needleTokens.isEmpty) {
    return 0;
  }
  final haystackTokens = haystack.split(' ').toSet();
  var matched = 0.0;
  var total = 0.0;
  for (final tok in needleTokens) {
    final weight = tok.length.toDouble();
    total += weight;
    if (haystackTokens.contains(tok)) {
      matched += weight;
    }
  }
  return total == 0 ? 0 : matched / total;
}

/// Minimum [_tokenOverlapScore] for a fuzzy match to be trusted at all —
/// below this, "no profile found" is a more honest answer than guessing
/// at a wrong lens's correction data (which could make the photo look
/// worse, not better).
const double _fuzzyMatchThreshold = 0.5;

/// Finds the best-matching [LensProfile] for [metadata]'s free-text
/// `lensModel` (as reported by LibRaw/EXIF), or null if nothing in
/// [profiles] scores above [_fuzzyMatchThreshold]. Exact matches (a DB
/// entry's normalized "maker model" exactly containing the normalized
/// lens string) short-circuit; everything else falls back to
/// token-overlap scoring — mirrors darktable/RawTherapee's own "exact
/// match first, fuzzy fallback" approach, without replicating their full
/// matching logic.
LensProfile? matchLensProfile(
  List<LensProfile> profiles,
  RawMetadata metadata,
) {
  final lensText = _normalizeLensText(metadata.lensModel);
  if (lensText.isEmpty) {
    return null;
  }
  final makerText = _normalizeLensText(metadata.cameraMake);

  LensProfile? best;
  var bestScore = 0.0;
  for (final profile in profiles) {
    final profileMaker = _normalizeLensText(profile.maker);
    final profileText =
        _normalizeLensText('${profile.maker} ${profile.model}');
    if (profileText.contains(lensText) || lensText.contains(profileText)) {
      return profile;
    }
    var score = _tokenOverlapScore(lensText, profileText);
    // A lens maker that doesn't even share a token with the camera body's
    // maker (e.g. matching a "Nikon" lens profile against a Canon-mount
    // photo) is almost certainly a false positive from generic tokens
    // like a shared focal length — third-party lenses (Sigma/Tamron/
    // Tokina) name their own maker in `lensModel`, so this only
    // penalizes genuine cross-mount mismatches, not third-party glass.
    if (makerText.isNotEmpty &&
        !lensText.contains(profileMaker) &&
        !profileMaker.contains(makerText) &&
        _tokenOverlapScore(makerText, profileText) == 0) {
      score *= 0.5;
    }
    if (score > bestScore) {
      bestScore = score;
      best = profile;
    }
  }
  return bestScore >= _fuzzyMatchThreshold ? best : null;
}

/// Matches a fixed-lens camera's own body name against the profile
/// database, for cameras where [matchLensProfile] can never find anything
/// because LibRaw reports an empty `lensModel` — there's no interchangeable
/// lens to name (e.g. the Fujifilm X100 series). Lensfun still ships
/// calibration data for these: it's keyed on the camera body itself, named
/// like `"X100V & compatibles"` — the "& compatibles" wording is Lensfun's
/// own way of saying later, optically-identical bodies (the X100VI reuses
/// the X100V's lens) should reuse the same entry. Only profiles actually
/// using that naming convention (a literal "&" in [LensProfile.model]) are
/// considered, since ordinary interchangeable-lens entries don't use it and
/// would otherwise risk a false match against an unrelated lens name that
/// happens to share a prefix with a camera model.
LensProfile? matchLensProfileByCameraModel(
  List<LensProfile> profiles,
  RawMetadata metadata,
) {
  final bodyText = _normalizeLensText(metadata.cameraModel);
  if (bodyText.isEmpty) {
    return null;
  }
  final makerText = _normalizeLensText(metadata.cameraMake);

  LensProfile? best;
  var bestScore = 0.0;
  for (final profile in profiles) {
    if (!profile.model.contains('&')) {
      continue;
    }
    final profileMaker = _normalizeLensText(profile.maker);
    // A fixed-lens profile is always maker-specific -- there's no
    // third-party equivalent of a camera's own built-in optics, so (unlike
    // matchLensProfile's lens-text matching) a maker mismatch here is
    // always disqualifying rather than just a score penalty.
    if (makerText.isNotEmpty &&
        !profileMaker.contains(makerText) &&
        !makerText.contains(profileMaker)) {
      continue;
    }
    final profileModel = _normalizeLensText(profile.model);
    final profileCore = profileModel.split('&').first.trim();
    if (profileCore.isEmpty) {
      continue;
    }
    double score = 0;
    if (profileCore == bodyText) {
      score = 1.0;
    } else if (bodyText.startsWith(profileCore) ||
        profileCore.startsWith(bodyText)) {
      // Shared-prefix match (e.g. camera model "x100vi" vs a profile core
      // of "x100v") scored by how much of the longer string the shared
      // prefix covers, so "x100v"/"x100vi" scores high while a much
      // shorter accidental prefix wouldn't clear the threshold below.
      final shorter = math.min(profileCore.length, bodyText.length);
      final longer = math.max(profileCore.length, bodyText.length);
      score = shorter / longer;
    }
    if (score > bestScore) {
      bestScore = score;
      best = profile;
    }
  }
  return bestScore >= _fuzzyMatchThreshold ? best : null;
}

/// Resolves which [LensProfile] a render should use: a manual override
/// (looked up by [LensCorrectionParams.manualProfileKeyHash]) takes
/// priority when set, else [matchLensProfile] against [metadata]'s
/// `lensModel`, else (for fixed-lens cameras that report no separate lens
/// name at all) [matchLensProfileByCameraModel] against the camera body's
/// own make+model, else null (no correction available/applicable).
LensProfile? resolveLensProfile(
  List<LensProfile> profiles,
  RawMetadata? metadata,
  double? manualProfileKeyHash,
) {
  if (manualProfileKeyHash != null) {
    for (final profile in profiles) {
      if (lensProfileKeyHash(profile.key) == manualProfileKeyHash) {
        return profile;
      }
    }
    // A stale hash (profile removed from a later DB regeneration) falls
    // through to auto-detect rather than silently applying no correction
    // at all.
  }
  if (metadata == null) {
    return null;
  }
  if (metadata.lensModel.isNotEmpty) {
    final match = matchLensProfile(profiles, metadata);
    if (match != null) {
      return match;
    }
  }
  return matchLensProfileByCameraModel(profiles, metadata);
}


/// Linearly interpolates (or clamps to the nearest end) [profile]'s
/// distortion calibration points to [focalLengthMm] — a zoom lens is
/// calibrated at a handful of focal lengths, but a photo can be shot at
/// any focal length in between, so the coefficients themselves are
/// interpolated the same way Lensfun's own consumers do rather than
/// snapping to the single nearest calibration point.
LensDistortionPoint? _distortionAt(LensProfile profile, double focalLengthMm) {
  final points = profile.distortion;
  if (points.isEmpty) {
    return null;
  }
  if (points.length == 1 || focalLengthMm <= 0) {
    return points.first;
  }
  final sorted = [...points]..sort((a, b) => a.focal.compareTo(b.focal));
  if (focalLengthMm <= sorted.first.focal) {
    return sorted.first;
  }
  if (focalLengthMm >= sorted.last.focal) {
    return sorted.last;
  }
  for (var i = 0; i < sorted.length - 1; i++) {
    final lo = sorted[i];
    final hi = sorted[i + 1];
    if (focalLengthMm >= lo.focal && focalLengthMm <= hi.focal) {
      final t = (focalLengthMm - lo.focal) / (hi.focal - lo.focal);
      double? lerp(double? a, double? b) =>
          (a == null || b == null) ? null : a + (b - a) * t;
      return LensDistortionPoint(
        focal: focalLengthMm,
        a: lerp(lo.a, hi.a),
        b: lerp(lo.b, hi.b),
        c: lerp(lo.c, hi.c),
        k1: lerp(lo.k1, hi.k1),
        k2: lerp(lo.k2, hi.k2),
      );
    }
  }
  return sorted.last;
}

/// `Rd/Ru` at normalized radius [ru] for [point] under [model] — see
/// [applyLensDistortionCorrection]'s doc comment for why this is a direct
/// evaluation (no Newton iteration needed).
double _distortionFactor(String model, LensDistortionPoint point, double ru) {
  switch (model) {
    case 'ptlens':
      final a = point.a ?? 0;
      final b = point.b ?? 0;
      final c = point.c ?? 0;
      return ((a * ru + b) * ru + c) * ru + 1.0;
    case 'poly5':
      final k1 = point.k1 ?? 0;
      final k2 = point.k2 ?? 0;
      final ru2 = ru * ru;
      return 1.0 + k1 * ru2 + k2 * ru2 * ru2;
    case 'poly3':
    default:
      final k1 = point.k1 ?? 0;
      return 1.0 + k1 * ru * ru;
  }
}

/// Undistorts [sourceRgb] against [profile]'s calibration at
/// [focalLengthMm], blended by [amount01] (0 = untouched, 1 = full
/// correction, matching Lightroom's Distortion amount slider). Output
/// keeps the source's own width/height — unlike `applyCropTransform`,
/// this never changes the canvas size; it just resamples within it,
/// leaving stretched-edge padding (via [sampleBilinear]'s clamp) exactly
/// where a strong correction pulls source content from outside the
/// original frame, the same tradeoff Crop/Transform makes.
///
/// Lensfun's polynomial models describe how a REAL lens maps an ideal
/// (rectilinear) ray position `Ru` to where it actually lands on the
/// sensor, `Rd = Ru * poly(Ru)`. Reconstructing the ideal image is then a
/// direct backward-mapping resample: for each OUTPUT (corrected) pixel at
/// normalized radius `Ru`, the color that belongs there is whatever the
/// sensor captured at `Rd = Ru * poly(Ru)` — no inversion/iteration
/// needed, since `Ru` is already known (it's the output pixel's own
/// position) and the polynomial gives `Rd` directly. (Iterative solving
/// is only needed for the opposite direction — simulating what a lens
/// *would* do to an already-ideal image — which this app never does.)
/// Verified against typical barrel distortion (negative poly3 k1): this
/// direction samples the source *closer to center* than the output
/// pixel, i.e. stretches the compressed periphery back outward, which is
/// the correction a barrel-distorted photo actually needs.
///
/// TCA (chromatic aberration) correction is a separate pass —
/// [applyLensChromaticAberrationCorrection] — rather than fused into this
/// one: it needs this same resample done independently per-channel (red
/// and blue each get their own radius scaling; green stays untouched as
/// the reference channel), and keeping it as its own pass mirrors how
/// vignetting is already a separate step after this one, instead of
/// tripling this function's branching for a correction most photos barely
/// need.
GeometryResult applyLensDistortionCorrection(
  Uint8List sourceRgb,
  int width,
  int height,
  LensProfile profile,
  double focalLengthMm,
  double amount01,
) {
  final model = profile.distortionModel;
  final point = model == null ? null : _distortionAt(profile, focalLengthMm);
  if (model == null || point == null || amount01 <= 0) {
    return GeometryResult(width: width, height: height, rgbBytes: sourceRgb);
  }
  final clampedAmount = amount01.clamp(0.0, 1.0);
  final cx = width / 2.0;
  final cy = height / 2.0;
  final halfDiagonal = math.sqrt(cx * cx + cy * cy);
  final out = Uint8List(sourceRgb.length);

  for (var y = 0; y < height; y++) {
    final dy = y - cy;
    for (var x = 0; x < width; x++) {
      final dx = x - cx;
      final ru = math.sqrt(dx * dx + dy * dy) / halfDiagonal;
      double sampleX = x.toDouble();
      double sampleY = y.toDouble();
      if (ru > 1e-9) {
        final factor = _distortionFactor(model, point, ru);
        // amount01 blends the *radius factor* toward 1 (identity), not
        // the sampled pixel toward the source pixel — blending the
        // factor keeps the correction geometrically consistent at every
        // radius instead of just cross-fading two images.
        final blended = 1.0 + (factor - 1.0) * clampedAmount;
        sampleX = cx + dx * blended;
        sampleY = cy + dy * blended;
      }
      sampleBilinear(
        sourceRgb,
        width,
        height,
        sampleX,
        sampleY,
        out,
        (y * width + x) * 3,
      );
    }
  }
  return GeometryResult(width: width, height: height, rgbBytes: out);
}

/// Picks the single closest calibration point to (focalLengthMm,
/// apertureFNumber) by normalized combined distance — vignetting isn't
/// interpolated the way distortion is (Lensfun's own DB has a much
/// coarser, irregular (focal, aperture) grid for it, e.g. only a couple
/// of apertures per focal length, so a 2D interpolation would mostly be
/// extrapolating rather than genuinely interpolating).
LensVignettingPoint? _nearestVignettingPoint(
  LensProfile profile,
  double focalLengthMm,
  double apertureFNumber,
) {
  if (profile.vignetting.isEmpty) {
    return null;
  }
  LensVignettingPoint? best;
  var bestDist = double.infinity;
  for (final point in profile.vignetting) {
    final focalDiff = focalLengthMm <= 0
        ? 0.0
        : (point.focal - focalLengthMm) / math.max(focalLengthMm, 1.0);
    final apertureDiff = apertureFNumber <= 0
        ? 0.0
        : (point.aperture - apertureFNumber) / math.max(apertureFNumber, 1.0);
    final dist = focalDiff * focalDiff + apertureDiff * apertureDiff;
    if (dist < bestDist) {
      bestDist = dist;
      best = point;
    }
  }
  return best;
}

/// Brightens [rgbBuffer]'s corners to compensate for [profile]'s
/// measured lens vignetting at (focalLengthMm, apertureFNumber), blended
/// by [amount01]. In place, packed 8-bit RGB — same shape/convention as
/// the rest of the pre-tone pipeline this runs alongside in
/// `render_job.dart` (see that file for why lens correction sits there
/// rather than inside `render.dart`'s per-mask-reapplied point-ops).
void applyLensVignetteCorrection(
  Uint8List rgbBuffer,
  int width,
  int height,
  LensProfile profile,
  double focalLengthMm,
  double apertureFNumber,
  double amount01,
) {
  final point = _nearestVignettingPoint(
    profile,
    focalLengthMm,
    apertureFNumber,
  );
  if (point == null || amount01 <= 0) {
    return;
  }
  final clampedAmount = amount01.clamp(0.0, 1.0);
  final cx = width / 2.0;
  final cy = height / 2.0;
  final halfDiagonal = math.sqrt(cx * cx + cy * cy);

  for (var y = 0; y < height; y++) {
    final dy = y - cy;
    for (var x = 0; x < width; x++) {
      final dx = x - cx;
      final r = math.sqrt(dx * dx + dy * dy) / halfDiagonal;
      final r2 = r * r;
      // Lensfun's "pa" model: falloff = 1 + k1*r^2 + k2*r^4 + k3*r^6,
      // always <= 1 toward the corners for real vignetting (k1 negative)
      // — dividing by it (multiplying by its reciprocal) brightens them
      // back up.
      final falloff =
          1.0 + point.k1 * r2 + point.k2 * r2 * r2 + point.k3 * r2 * r2 * r2;
      if (falloff <= 0) {
        continue;
      }
      final invFalloff = 1.0 / falloff;
      final blended = 1.0 + (invFalloff - 1.0) * clampedAmount;
      if (blended == 1.0) {
        continue;
      }
      final i = (y * width + x) * 3;
      rgbBuffer[i] = (rgbBuffer[i] * blended).round().clamp(0, 255);
      rgbBuffer[i + 1] = (rgbBuffer[i + 1] * blended).round().clamp(0, 255);
      rgbBuffer[i + 2] = (rgbBuffer[i + 2] * blended).round().clamp(0, 255);
    }
  }
}

/// Linearly interpolates (or clamps to the nearest end) [profile]'s TCA
/// calibration points to [focalLengthMm] — same reasoning as
/// [_distortionAt].
LensTcaPoint? _tcaAt(LensProfile profile, double focalLengthMm) {
  final points = profile.tca;
  if (points.isEmpty) {
    return null;
  }
  if (points.length == 1 || focalLengthMm <= 0) {
    return points.first;
  }
  final sorted = [...points]..sort((a, b) => a.focal.compareTo(b.focal));
  if (focalLengthMm <= sorted.first.focal) {
    return sorted.first;
  }
  if (focalLengthMm >= sorted.last.focal) {
    return sorted.last;
  }
  for (var i = 0; i < sorted.length - 1; i++) {
    final lo = sorted[i];
    final hi = sorted[i + 1];
    if (focalLengthMm >= lo.focal && focalLengthMm <= hi.focal) {
      final t = (focalLengthMm - lo.focal) / (hi.focal - lo.focal);
      double lerp(double a, double b) => a + (b - a) * t;
      return LensTcaPoint(
        focal: focalLengthMm,
        vr: lerp(lo.vr, hi.vr),
        vb: lerp(lo.vb, hi.vb),
        br: lerp(lo.br, hi.br),
        cr: lerp(lo.cr, hi.cr),
        bb: lerp(lo.bb, hi.bb),
        cb: lerp(lo.cb, hi.cb),
      );
    }
  }
  return sorted.last;
}

/// Red or blue channel's radius-scale factor at normalized radius [ru] —
/// Lensfun's TCA poly3 model is `v + b*ru^2 + c*ru^4` (mirrors the
/// distortion poly5 model's shape); a 'linear' calibration point has
/// [b]/[c] fixed at 0 by [LensProfileDatabase._decodeLensProfile], so this
/// same expression correctly reduces to the constant-only `v` for those
/// without needing a separate branch on [LensProfile.tcaModel].
double _tcaFactor(double v, double b, double c, double ru) {
  final ru2 = ru * ru;
  return v + b * ru2 + c * ru2 * ru2;
}

/// Corrects transverse chromatic aberration in [sourceRgb] against
/// [profile]'s calibration at [focalLengthMm], blended by [amount01] — same
/// shape/conventions as [applyLensDistortionCorrection] (backward-mapping
/// resample, output keeps the source's own width/height), except the
/// resample runs independently per-channel: red and blue each get their
/// own [_tcaFactor]-scaled radius while green is copied through unchanged,
/// since green is Lensfun's untouched reference channel (the lens focuses
/// red/blue at a slightly different magnification than green, not the
/// other way around).
GeometryResult applyLensChromaticAberrationCorrection(
  Uint8List sourceRgb,
  int width,
  int height,
  LensProfile profile,
  double focalLengthMm,
  double amount01,
) {
  final point = _tcaAt(profile, focalLengthMm);
  if (point == null || amount01 <= 0) {
    return GeometryResult(width: width, height: height, rgbBytes: sourceRgb);
  }
  final clampedAmount = amount01.clamp(0.0, 1.0);
  final cx = width / 2.0;
  final cy = height / 2.0;
  final halfDiagonal = math.sqrt(cx * cx + cy * cy);
  final out = Uint8List(sourceRgb.length);

  for (var y = 0; y < height; y++) {
    final dy = y - cy;
    for (var x = 0; x < width; x++) {
      final dx = x - cx;
      final i = (y * width + x) * 3;
      out[i + 1] = sourceRgb[i + 1];
      final ru = math.sqrt(dx * dx + dy * dy) / halfDiagonal;
      if (ru <= 1e-9) {
        out[i] = sourceRgb[i];
        out[i + 2] = sourceRgb[i + 2];
        continue;
      }
      final factorR = _tcaFactor(point.vr, point.br, point.cr, ru);
      final factorB = _tcaFactor(point.vb, point.bb, point.cb, ru);
      final blendedR = 1.0 + (factorR - 1.0) * clampedAmount;
      final blendedB = 1.0 + (factorB - 1.0) * clampedAmount;
      out[i] = sampleBilinearChannel(
        sourceRgb,
        width,
        height,
        cx + dx * blendedR,
        cy + dy * blendedR,
        0,
      ).round().clamp(0, 255);
      out[i + 2] = sampleBilinearChannel(
        sourceRgb,
        width,
        height,
        cx + dx * blendedB,
        cy + dy * blendedB,
        2,
      ).round().clamp(0, 255);
    }
  }
  return GeometryResult(width: width, height: height, rgbBytes: out);
}
