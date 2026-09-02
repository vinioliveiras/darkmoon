/// ============================================================================
///  CALIBRATION FILE — the "how much" behind every slider
/// ============================================================================
///
/// This is the one place that holds the numbers controlling **the strength
/// and shape** of every adjustment in the app. The scale you see on screen
/// (e.g. Exposure -5..+5, Contrast -100..+100) does NOT change — what changes
/// is how hard that value actually pushes the image.
///
/// HOW TO USE THIS
///   1. Edit a number below.
///   2. Run the build:  flutter run -d windows     (or build windows --release)
///   3. Open a photo, move the matching slider, and compare (e.g. against
///      Meridian at the same value).
///   4. Don't like it? Go back to the "default:" noted in the comment.
///
/// GENERAL RULE
///   • Every comment says which way to move it ("↑ higher = stronger" etc.).
///   • Start with small steps (e.g. 0.42 → 0.50, not 0.42 → 2.0).
///   • Changing a value here affects EVERY photo and EVERY preset.
///
/// CPU vs GPU
///   These values apply to the CPU render (the app's default, and what you
///   test against). The GPU render (Settings → advanced option, off by
///   default) still uses fixed numbers baked into the `.frag` shaders; when a
///   value also exists in a shader, the comment marks it with  [also on GPU:
///   file.frag]  so you can match the two by hand if you use GPU.
///
/// Deliberately no Flutter imports: the render functions run in isolates and
/// read these constants directly, without needing anything passed in.
library;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  GLOBAL — Amount slider                                                   ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// Blanket damping applied to EVERY slider deviation and every curve point
/// before it reaches the renderer — the actual mechanism behind the "Amount"
/// slider under the preset list (`_globalEditAmountKey` in editor_screen.dart,
/// `_withGlobalEditAmountApplied`/`_effectiveCurves`). Amount's own UI value
/// (0-200, default 100) is multiplied by this constant to get the real blend
/// fraction — so the *default* Amount (100%) no longer means "apply every
/// slider/preset value exactly as authored," it means "apply it at this
/// fraction of that." Amount's max (200%) caps out at fraction 0.6 — the UI
/// deliberately doesn't go high enough to reach full/un-dampened strength
/// (fraction 1.0, which would need Amount ≈ 333%) since that's the exact
/// literal-authored-value look this constant exists to move away from.
///
/// Exists because, after individually calibrating one effect at a time
/// (Vibrance/Saturation/Dehaze/Mixer — see their own `cal*Strength`
/// constants above), the pattern kept repeating: nearly everything looked
/// "too strong" at its literal authored value, and consistently looked right
/// once manually damped to roughly the same fraction (empirically, ~30%,
/// found via the Amount slider itself on "Filmatic Fuji 4" against a real
/// photo). Rather than keep hunting for the next individually-uncalibrated
/// slider, this bakes that empirical fraction in globally, on top of
/// (not instead of) the per-effect constants already tuned — those still
/// matter for relative balance between effects, this just scales the whole
/// result down to the range that's looked right every time so far.
///   ↑ higher = default Amount (100%) renders closer to the literal authored
///     values
///   ↓ lower  = default Amount (100%) renders gentler
/// default: 0.3   (original/unset: 1.0 — Amount was a 1:1 pass-through)
const double calGlobalAmountCompression = 0.3;

/// Per-slider override of [calGlobalAmountCompression] — a slider key
/// present here (matching its `_SliderSpec` name in `editor_screen.dart`,
/// e.g. `'Exposure'`) uses this fraction instead of the global one; every
/// other slider still falls back to [calGlobalAmountCompression]
/// automatically. Exists because the global damping fraction was tuned
/// against the general "everything looks too strong at its literal value"
/// pattern, but not every slider necessarily fits that pattern — Exposure
/// is kept at 1.0 (no damping at all) per explicit request (2026-09-02):
/// unlike Vibrance/Saturation/Dehaze/Mixer, a damped Exposure read as too
/// weak, not "correctly gentled." Add more entries here the same way if a
/// future slider needs its own answer instead of the global one — no code
/// change needed beyond this map, [_withGlobalEditAmountApplied] already
/// reads through it for every key.
const Map<String, double> calGlobalAmountCompressionOverrides = {
  'Exposure': 1.0,
  'Contrast': 0.5,
  // Real bug found 2026-09-02: dragging the "Color Profile Contrast"
  // slider (ColorProfileAmount) barely changed the render even across
  // its full range, because it fell back to the global 0.3 fraction like
  // every other slider — moving it from its default (30) to its max (60)
  // only ever actually applied 30 + (60-30)*0.3 = 39, not 60. Undamped
  // for the same reason Exposure/Contrast are: it's the one slider this
  // whole 30% rule was never meant to touch that quietly, since it's
  // itself a stand-in for a fixed baked-in curve, not a "how much of a
  // preset's edit" knob.
  'ColorProfileAmount': 1.0,
};

// Temperature/Tint deliberately have NO entry here, not even 1.0: they
// aren't in this map's lookup at all — `_withGlobalEditAmountApplied`
// excludes them from the whole scaling loop entirely (they're not
// naturally 0-centered deltas the way Exposure/Contrast are), so they
// already always render at their exact stored value regardless of
// Amount. An override entry for them would be dead code, never read.

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  WHITE BALANCE (Temperature / Tint)                                       ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// Strength of the **Tint** slider — how hard a Tint of ±100 pushes toward
/// green vs. magenta.
///   ↑ higher = more aggressive Tint (green/magenta shows up faster)
///   ↓ lower  = gentler Tint
/// default: 0.35   (the old model used 0.25; raised toward Meridian)
const double calWbTintStrength = 0.35;

/// Working-space gamma the WB gains are applied in.
/// This is technical — only change it if you know why. Changing it throws
/// off Temperature relative to "As Shot" (the per-photo neutral point).
/// default: 2.2
const double calWbWorkingGamma = 2.2;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  WHITE BALANCE — "As Shot" estimator (colorimetry)                        ║
// ╚══════════════════════════════════════════════════════════════════════════╝
//
// We don't have Adobe's camera profile ("Adobe Color" = ForwardMatrix +
// HueSatMap + tone curve — closed data). What we do have: the decode uses
// the color matrix embedded in the camera itself (`use_camera_matrix`), and
// "As Shot" (the Kelvin/Tint shown at 0 edits) is ESTIMATED via colorimetry
// (Bradford adaptation + Ohno projection onto the locus).
//
// These 3 values were fit by least squares against Meridian on 4 real
// X100VI files (matches within ~2% Kelvin / ~3.5 tint). If you use a
// different camera and "As Shot" is skewing green/magenta or cool/warm vs.
// Meridian, re-tune here (note the reference photos you used).

/// Fixed Δuv (green/magenta) added before converting to Tint — our reference
/// white locus sits ~0.0065 uv too green compared to Meridian's.
///   ↑ higher = "As Shot" skews more toward magenta (more positive Tint)
///   ↓ lower  = skews more toward green
/// default: 0.00655
const double calWbAsShotDuvBias = 0.00655;

/// Δuv → Tint units (-150..150) scale factor.
///   ↑ higher = the same camera color yields a bigger estimated "As Shot" Tint
///   ↓ lower  = smaller estimated Tint
/// default: 3220.0
const double calWbAsShotTintPerDuv = 3220.0;

/// Mireds subtracted from the estimated temperature (our CCT reads a few
/// mireds cooler than Meridian's on the X100VI).
///   ↑ higher = "As Shot" runs WARMER (higher Kelvin)
///   ↓ lower  = cooler
/// default: 3.0
const double calWbAsShotCctMiredBias = 3.0;

/// Fallback path (camera with no usable color matrix): Tint from the R+B
/// gain-excess ratio. Much cruder than the colorimetric path.
///   ↑ higher = stronger estimated Tint in the fallback path
/// default: 200.0
const double calWbAsShotTintScaleFallback = 200.0;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  BASE LOOK — the "profile curve" (approximates Meridian's "Adobe Color") ║
// ╚══════════════════════════════════════════════════════════════════════════╝
//
// Meridian, at 0 edits, ALREADY applies the "Adobe Color" profile's tone
// curve (a gentle S-curve baked into the profile). darkmoon decodes the RAW
// with a straight sRGB gamma and nothing else, so its starting point is much
// FLATTER. In practice: presets made in Meridian look low-contrast here,
// and you end up compensating via Blacks/Whites in every preset.
//
// This number applies a fixed S-curve to every photo, right at the start of
// tone adjustments (after Exposure/WB, before Highlights/Shadows/Blacks/
// Whites and the curves) — the same slot the profile curve occupies in
// Meridian. The math is identical to the Contrast slider's, so "20" here is
// roughly a built-in Contrast +20.
///
//   ↑ higher = a more contrasty starting point (closer to Meridian)
//   ↓ lower  = flatter (0.0 = off, the old behavior)
//
// Calibrated to 20.0 by comparing DSF1309 against a real Meridian export
// (the "Filmatic Fuji 2 Meridian.xmp" profile imported unmodified) —
// 2026-08-29. In this range (~12 to ~28) overall contrast matches.
//
// ⚠️ Changing this changes the look of every photo and every preset —
//    including ones you already tuned in darkmoon before 2026-08-29 (they'll
//    get more contrasty). Re-tune those presets starting from this value,
//    not from 0.
//
// This is the FACTORY value. The user can override it live in
// Settings → "darkmoon Color Profile" (saved in AppSettings), no rebuild
// needed. Both CPU and GPU apply the curve.
/// default: 30.0   (0.0 = off; 2026-08-29: originally 20.0; briefly
/// lowered to 15.0 on 2026-09-02 — photos opened a bit brighter than the
/// same RAW in Meridian — then raised past both, to 30.0, same day,
/// explicit user request. Deliberately not touching `no_auto_bright`
/// (libraw.dart) for this — that's the decode-time exposure baseline,
/// and re-opening it risks the whole incident history in
/// project_darkmoon_color_profile.md; this S-curve is the safer, purely
/// render-time lever.)
const double calBaseContrast = 80.0;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  BASIC — Exposure / Brightness / Contrast                                 ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Exposure**: how many slider units equal 1 stop (doubling/halving the
/// light). The effect is  2^(sliderValue / this number).
///   ↑ higher = weaker Exposure (needs a bigger drag for the same change)
///   ↓ lower  = stronger Exposure
/// default: 12.0   (2026-09-02: still felt too weak at 16.67, explicit
/// user request to push it further)
const double calExposureUnitsPerStop = 12.0;

/// **Brightness**: same idea as Exposure, slider units per stop, but
/// Brightness uses a curve that protects blacks and whites (no clipping).
///   ↑ higher = weaker Brightness     ↓ lower = stronger Brightness
/// default: 20.0
const double calBrightnessUnitsPerStop = 20.0;

/// **Brightness** — how much the curve concentrates the effect in midtones
/// (instead of spreading across the whole range).
///   ↑ higher = affects midtones more, extremes stay more protected
///   ↓ lower  = more linear/even effect
/// default: 1.2
const double calBrightnessMidtoneStrength = 1.2;

/// **Contrast**: how hard the slider tilts the S-curve.
///   ↑ higher = more aggressive Contrast at the same value
///   ↓ lower  = gentler Contrast
/// default: 0.75   (2026-09-02: raised from 0.50, explicit user request —
/// felt too weak)
const double calContrastStrength = 0.75;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  BASIC — Highlights / Shadows / Whites / Blacks                           ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Highlights**: recovery/blowout strength.
///   ↑ higher = Highlights recovers/lifts much faster
///   ↓ lower  = subtler
/// default: 1.0
const double calHighlightsStrength = 1.0;

/// **Shadows**: multiplier on top of the slider value.
///   ↑ higher = stronger Shadows     ↓ lower = weaker
/// default: 1.0
const double calShadowsAmountScale = 1.0;

/// **Shadows** — width of the affected tonal range. This is an exponent: a
/// HIGH number confines the effect to only the deepest shadows; a LOW number
/// spreads it into the shadow-midtones too.
///   ↑ higher = effect more confined to deep shadows
///   ↓ lower  = reaches a wider shadow range (more "Meridian"-like)
/// default: 4.5
const double calShadowsFalloff = 4.5;

/// **Whites** — the brightness level above which the slider starts acting.
/// This is the floor of a mask (0..1 on perceived luminance).
///   ↑ higher (e.g. 0.5) = only the brightest whites move ("weak" effect)
///   ↓ lower (e.g. 0.30) = also reaches the upper-midtones ("strong" effect)
/// default: 0.32   (2026-09-02: lowered to 0.26, explicit user request —
/// Whites felt too weak)   [also on GPU: point_ops_post_denoise.frag → rapidWhiteMask]
const double calWhitesMaskLow = 0.26;

/// **Whites** — how much it lifts the white point at the slider's max value.
///   ↑ higher = Whites +100 brightens much more
///   ↓ lower  = Whites +100 barely changes anything
/// default: 0.40   (original Solstice: 0.25; 2026-09-02: raised to 0.40,
/// explicit user request — Whites felt too weak)   [also on GPU: point_ops_post_denoise.frag]
const double calWhitesLevelCoeff = 0.40;

/// **Blacks** — multiplier on top of the slider value.
///   ↑ higher = stronger Blacks (crushes/lifts black much harder)
///   ↓ lower  = weaker Blacks
/// default: 2.0   (original Solstice: 1.0)   [also on GPU: point_ops_post_denoise.frag]
const double calBlacksAmountScale = 2.0;

/// **Blacks** — width of the affected range (exponent, same idea as
/// Shadows').
///   ↑ higher (e.g. 12) = only the deepest black moves
///   ↓ lower (e.g. 7)   = reaches a wider shadow range
/// default: 9.0   (original Solstice: 12.0)   [also on GPU: point_ops_post_denoise.frag]
const double calBlacksFalloff = 9.0;

/// **Shadows/Blacks** — a local-contrast boost applied alongside the lift, so
/// the image doesn't go "flat" when shadows are opened up a lot.
///   ↑ higher = more "punch" when lifting shadows
///   ↓ lower  = flatter lift
/// default: 1.3
const double calShadowBlacksStretch = 1.3;

/// **Shadows/Blacks** — blend between the plain curve (0.0) and the
/// contrast-boosted curve above (1.0).
///   ↑ higher = leans more on the contrast boost
///   ↓ lower  = leans more on the plain curve
/// default: 0.85
const double calShadowBlacksContrastMix = 0.85;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  PRESENCE — Texture / Clarity / Dehaze                                    ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Texture** — radius (in pixels) of the detail it enhances. Small = very
/// fine detail (pores, hair); large = coarser detail.
///   ↑ higher = enhances larger structures
///   ↓ lower  = enhances only the finest detail
/// default: 3.5
const double calTextureSigma = 3.5;

/// **Texture** — strength multiplier on top of the slider.
///   ↑ higher = stronger Texture     ↓ lower = weaker
/// default: 2.7   (user raised to 2.0, then 2.3, then asked for more —
/// 2026-09-02)
const double calTextureStrength = 3.0;

/// **Clarity** — radius (in pixels) of the local contrast. Deliberately
/// large (mid-range contrast, more like "definition").
///   ↑ higher = wider effect/bigger "halo"
///   ↓ lower  = more localized effect
/// default: 25.0
const double calClaritySigma = 25.0;

/// **Clarity** — strength multiplier on top of the slider.
///   ↑ higher = stronger Clarity     ↓ lower = weaker
/// default: 0.65   (2026-09-01: raised from 0.5, explicit user request)
const double calClarityStrength = 0.65;

/// **Dehaze +** — how hard the positive slider pulls transmission down (=
/// removes haze). This is the main control over Dehaze strength.
///   ↑ higher (e.g. 0.85) = very aggressive Dehaze (original Solstice)
///   ↓ lower (e.g. 0.45) = quite gentle Dehaze
/// default: 0.55   [also on GPU: dehaze_apply.frag]
/// 2026-09-01: user set this to 0.1 (5.5x weaker) wanting a gentler Dehaze —
/// landed at a real but more moderate weakening instead (~1.6x), since the
/// transmission-floor bug below meant 0.1 was never actually tested against
/// a working Dehaze. Weakened again 2026-09-01 (user: "still a bit strong").
const double calDehazeTransmissionCoeff = 0.22;

/// **Dehaze** — transmission floor: keeps Dehaze from "breaking" the image
/// in the hazier spots. Higher = safer/gentler.
///   ↑ higher = caps the maximum effect (gentler)
///   ↓ lower  = lets Dehaze go further (can blow out)
/// default: 0.22   (original Solstice: 0.15)   [also on GPU: dehaze_apply.frag]
/// 2026-09-01: user set this to 1.0, which is a real bug, not just
/// "gentler" — `t = max(1.0 - strength*mappedHaze*coeff, floor)` and the
/// first term is always ≤ 1.0, so a floor of 1.0 clamps `t` to exactly 1.0
/// on every pixel regardless of the Dehaze slider, making positive Dehaze
/// a complete no-op (recR/recG/recB reduce to r/g/b unchanged, shadowLift
/// and satBoost both zero out too since both scale off `1.0 - t`). Set to
/// a real "safer/gentler" value instead — meaningfully higher than the
/// 0.22 default (caps how far Dehaze can push) without fully disabling it.
/// Raised again 2026-09-01 (user: "still a bit strong") — at this floor +
/// the coefficient above, the strongest possible pull (slider at 100, max
/// haze) only takes transmission down to ~0.78, a real but gentle range.
const double calDehazeTransmissionFloor = 0.55;

/// **Dehaze** — how much it saturates color in proportion to the haze
/// removed.
///   ↑ higher = Dehaze leaves color more "punchy"
///   ↓ lower  = Dehaze barely touches saturation
/// default: 0.32   (original Solstice: 0.5)   [also on GPU: dehaze_apply.frag]
/// 2026-09-01: weakened from 0.32, moderately (not all the way to the
/// user's 0.1) — same "floor bug meant this was never really tested"
/// reasoning as the coefficient above. Weakened again 2026-09-01.
const double calDehazeSatBoost = 0.14;

/// **Dehaze −** (add haze) — strength of the slider's negative side (blends
/// the image with atmospheric light, making it look "milky").
///   ↑ higher = stronger negative Dehaze
///   ↓ lower  = subtler
/// default: 0.55   (original Solstice: 0.7)   [also on GPU: dehaze_apply.frag]
/// 2026-09-01: the doc's "0.55" was already stale — the real prior
/// committed value was 0.30, not 0.55. Weakened moderately from *that*
/// (not from the stale comment) — user's 0.2 was a real ~33% cut, this
/// lands at roughly half that. Weakened again 2026-09-01.
const double calDehazeAddMix = 0.18;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  COLOR — Vibrance / Saturation                                            ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Vibrance +** — gain on the positive side. Vibrance already protects
/// skin tones and already-saturated colors; this number is the raw strength
/// before that protection kicks in.
///   ↑ higher = Vibrance +100 is much more intense
///   ↓ lower  = more restrained
/// default: 1.5
/// 2026-09-01: user set this to 0.1 (15x weaker than the 1.5 default,
/// ~30x weaker than the original 3.0) wanting less blow-out — landed on a
/// more moderate weakening (~2x from 1.5) instead, since 0.1 makes
/// Vibrance +100 barely perceptible (closer to "off" than "gentler").
/// Weakened again 2026-09-01 (user: "still a bit strong"). Raised back up
/// 2026-09-02 (explicit user request — wanted it stronger again).
const double calVibranceStrength = 0.7;

/// **Vibrance** — how much it HOLDS BACK the effect on skin tones (so faces
/// don't turn orange). 1.0 = holds back nothing; 0.0 = zeroes out on skin.
///   ↑ higher (near 1) = skin saturates right along with everything else
///   ↓ lower (near 0) = skin stays well protected
/// default: 0.2
const double calVibranceSkinDampen = 0.6;

/// **Saturation** — multiplier on top of the slider (the effect is
/// 1 + sliderValue/100 * this number).
///   ↑ higher = stronger Saturation     ↓ lower = weaker
/// default: 1.0
/// 2026-09-01: user set this to 0.1 (10x weaker) wanting less blow-out —
/// landed on a moderate 2x weakening instead, since 0.1 leaves Saturation
/// +100 as only a ~1.01x multiplier, effectively disabling the slider
/// rather than just softening it. Weakened again 2026-09-01. Weakened
/// further 2026-09-02 (explicit user request).
const double calSaturationStrength = 0.10;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  COLOR — Color Mixer / HSL (8 bands)                                      ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Mixer → Hue** — how many degrees of hue rotation each slider unit
/// produces (before per-band normalization and the saturation mask). The
/// Solstice port used 0.6 (= `0.3 * 2.0`); comparing against Meridian
/// (Filmatic Fuji 2 on DSF1309, 2026-08-29) showed the user needed ~1.9×
/// Meridian's value on Orange/Yellow/Aqua/Blue — i.e. darkmoon's Hue was
/// too weak. Raised toward that (landed at 1.0, not the full 1.15 this
/// comment used to say — corrected 2026-09-02, no functional change).
///   ↑ higher = the same Hue slider value rotates color more
///   ↓ lower  = rotates less (0.6 = original Solstice behavior)
/// ⚠️ changes older presets that touched Mixer Hue (they'll rotate further).
/// default: 1.0   (original Solstice: 0.6)   [also on GPU: point_ops_post_denoise.frag]
const double calMixerHueStrength = 1.0;

/// **Mixer → effective band width** — the "sharpness" of the gaussian that
/// decides how much each band (Red, Orange…) influences a pixel of a given
/// hue. A HIGH number = narrower bands, less "leakage" between neighboring
/// bands (e.g. touching Green doesn't pull Yellow/Aqua along with it as
/// much). A LOW number = wider, more overlapping bands.
///   ↑ higher (e.g. 2.5) = bands more separated, more surgical effect
///   ↓ lower (e.g. 1.0) = wider bands (more "leakage")
/// Symptom of this being too low: in Meridian you desaturate only Green,
/// but in darkmoon you have to compensate Yellow/Aqua because Green
/// "leaked" into them. The 2026-08-29 comparison suggests this may be too
/// wide; worth testing higher. Kept at 1.5 (original Solstice) for now.
/// default: 1.5   [also on GPU: point_ops_post_denoise.frag → rawHslInfluence]
const double calMixerBandSharpness = 1.5;

/// **Mixer → Saturation** — strength multiplier on the raw Saturation
/// slider (unlike Hue, this had no calibration constant at all before
/// 2026-09-01 — always applied at literal 1:1 strength). Real bug found
/// via a live preset (Filmatic Fuji 4's Green channel: Saturation -75,
/// Luminance -57, close to the -100 floor on both) — at full strength
/// this crushed all foliage detail into a near-featureless dark mass;
/// scaling the Amount slider down to ~35% (which also scales this) fixed
/// it, which only makes sense if the raw per-slider-unit strength itself
/// was too aggressive, the same shape of problem Hue already had.
///   ↑ higher = the same Saturation slider value desaturates/saturates more
///   ↓ lower  = gentler
/// default: 0.5   (original/unset: 1.0)   [also on GPU: point_ops_post_denoise.frag]
const double calMixerSaturationStrength = 0.5;

/// **Mixer → Luminance** — same idea as [calMixerSaturationStrength], for
/// the Luminance slider. This one is the more visually destructive of the
/// two at full strength (a large negative Luminance directly darkens a
/// whole hue band toward black, not just desaturating it).
///   ↑ higher = the same Luminance slider value brightens/darkens more
///   ↓ lower  = gentler
/// default: 0.5   (original/unset: 1.0)   [also on GPU: point_ops_post_denoise.frag]
const double calMixerLuminanceStrength = 0.5;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  DETAIL — Sharpen                                                         ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Sharpen → Amount** — strength multiplier on top of the slider.
///   ↑ higher = stronger Sharpen at the same value
///   ↓ lower  = gentler
/// default: 1.0
const double calSharpenStrength = 1.0;

/// **Sharpen → Detail** — how much the Detail slider injects the finest
/// detail (vs. the coarser edges).
///   ↑ higher = high Detail becomes more "micro-detail" (and more noise)
///   ↓ lower  = more restrained Detail
/// default: 0.6
const double calSharpenDetailMix = 0.6;

/// **Sharpen → Masking** — floor for "what counts as a real edge" (0..255
/// scale). Below this, Masking treats it as flat/noise and doesn't sharpen
/// it.
///   ↑ higher = only sharpens strong edges (protects noise more)
///   ↓ lower  = sharpens weaker detail too
/// default: 6.0
const double calSharpenEdgeThreshold = 6.0;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  EFFECTS — Vignette                                                       ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Vignette → Amount** — overall strength on top of the slider.
///   ↑ higher = Vignette darkens/lightens the edges much more
///   ↓ lower  = subtler Vignette
/// default: 0.8
const double calVignetteStrength = 0.8;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  EFFECTS — Film Grain                                                     ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Grain → Amount** — strength multiplier on top of the slider.
///   ↑ higher = more visible grain at the same value
///   ↓ lower  = subtler grain
/// default: 1.0
const double calGrainStrength = 1.0;

/// **Grain → Size** — the size (in pixels, at a 1080px reference) of each
/// grain particle when the Size slider is at 0 and at 100. Grain is scaled
/// along with the image resolution, so the relative size stays the same in
/// the preview and in the export.
///   ↑ higher = coarser grain
///   ↓ lower  = finer grain
/// default: 0.8 (at 0)  and  4.8 (at 100)
const double calGrainSizePxAt0 = 0.8;
const double calGrainSizePxAt100 = 4.8;

/// **Grain → Roughness** — the slider blends a fine noise (0) with a more
/// irregular/coarse noise (100). This number does NOT change the slider's
/// effect directly; it's how much the coarse noise is "stretched" relative
/// to the fine one.
///   ↑ higher = at 100, grain clumps into bigger blotches
///   ↓ lower  = at 100, grain stays closer to the fine look
/// default: 0.6
const double calGrainRoughCoordScale = 0.6;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  NOISE REDUCTION (Classic AI Denoise — Light / Medium / Strong)           ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **AI Denoise** — global multiplier on LUMINANCE smoothing (the
/// black-and-white grain), applied across all 3 levels.
///   ↑ higher = blurs grain more (loses more fine detail)
///   ↓ lower  = preserves detail (leaves more grain)
/// default: 1.0
const double calDenoiseLumaStrengthScale = 1.0;

/// **AI Denoise** — global multiplier on COLOR smoothing (colored noise
/// blotches), applied across all 3 levels.
///   ↑ higher = removes more color blotching
///   ↓ lower  = more conservative
/// default: 1.0
const double calDenoiseChromaStrengthScale = 1.0;
