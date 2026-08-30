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
///      Lightroom at the same value).
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
// ║  WHITE BALANCE (Temperature / Tint)                                       ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// Strength of the **Tint** slider — how hard a Tint of ±100 pushes toward
/// green vs. magenta.
///   ↑ higher = more aggressive Tint (green/magenta shows up faster)
///   ↓ lower  = gentler Tint
/// default: 0.35   (the old model used 0.25; raised toward Lightroom)
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
// These 3 values were fit by least squares against Lightroom on 4 real
// X100VI files (matches within ~2% Kelvin / ~3.5 tint). If you use a
// different camera and "As Shot" is skewing green/magenta or cool/warm vs.
// Lightroom, re-tune here (note the reference photos you used).

/// Fixed Δuv (green/magenta) added before converting to Tint — our reference
/// white locus sits ~0.0065 uv too green compared to Lightroom's.
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
/// mireds cooler than Lightroom's on the X100VI).
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
// ║  BASE LOOK — the "profile curve" (approximates Lightroom's "Adobe Color") ║
// ╚══════════════════════════════════════════════════════════════════════════╝
//
// Lightroom, at 0 edits, ALREADY applies the "Adobe Color" profile's tone
// curve (a gentle S-curve baked into the profile). darkmoon decodes the RAW
// with a straight sRGB gamma and nothing else, so its starting point is much
// FLATTER. In practice: presets made in Lightroom look low-contrast here,
// and you end up compensating via Blacks/Whites in every preset.
//
// This number applies a fixed S-curve to every photo, right at the start of
// tone adjustments (after Exposure/WB, before Highlights/Shadows/Blacks/
// Whites and the curves) — the same slot the profile curve occupies in
// Lightroom. The math is identical to the Contrast slider's, so "20" here is
// roughly a built-in Contrast +20.
///
//   ↑ higher = a more contrasty starting point (closer to Lightroom)
//   ↓ lower  = flatter (0.0 = off, the old behavior)
//
// Calibrated to 20.0 by comparing DSF1309 against a real Lightroom export
// (the "Filmatic Fuji 2 Lightroom.xmp" profile imported unmodified) —
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
/// default: 20.0   (0.0 = off)
const double calBaseContrast = 20.0;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  BASIC — Exposure / Brightness / Contrast                                 ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Exposure**: how many slider units equal 1 stop (doubling/halving the
/// light). The effect is  2^(sliderValue / this number).
///   ↑ higher = weaker Exposure (needs a bigger drag for the same change)
///   ↓ lower  = stronger Exposure
/// default: 20.0
const double calExposureUnitsPerStop = 20.0;

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
/// default: 1.25
const double calContrastStrength = 1.25;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  BASIC — Highlights / Shadows / Whites / Blacks                           ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Highlights**: recovery/blowout strength.
///   ↑ higher = Highlights recovers/lifts much faster
///   ↓ lower  = subtler
/// default: 1.75
const double calHighlightsStrength = 1.75;

/// **Shadows**: multiplier on top of the slider value.
///   ↑ higher = stronger Shadows     ↓ lower = weaker
/// default: 1.0
const double calShadowsAmountScale = 1.0;

/// **Shadows** — width of the affected tonal range. This is an exponent: a
/// HIGH number confines the effect to only the deepest shadows; a LOW number
/// spreads it into the shadow-midtones too.
///   ↑ higher = effect more confined to deep shadows
///   ↓ lower  = reaches a wider shadow range (more "Lightroom"-like)
/// default: 4.5
const double calShadowsFalloff = 4.5;

/// **Whites** — the brightness level above which the slider starts acting.
/// This is the floor of a mask (0..1 on perceived luminance).
///   ↑ higher (e.g. 0.5) = only the brightest whites move ("weak" effect)
///   ↓ lower (e.g. 0.30) = also reaches the upper-midtones ("strong" effect)
/// default: 0.32     [also on GPU: point_ops_post_denoise.frag → rapidWhiteMask]
const double calWhitesMaskLow = 0.32;

/// **Whites** — how much it lifts the white point at the slider's max value.
///   ↑ higher = Whites +100 brightens much more
///   ↓ lower  = Whites +100 barely changes anything
/// default: 0.42   (original RapidRAW: 0.25)   [also on GPU: point_ops_post_denoise.frag]
const double calWhitesLevelCoeff = 0.42;

/// **Blacks** — multiplier on top of the slider value.
///   ↑ higher = stronger Blacks (crushes/lifts black much harder)
///   ↓ lower  = weaker Blacks
/// default: 1.5   (original RapidRAW: 1.0)   [also on GPU: point_ops_post_denoise.frag]
const double calBlacksAmountScale = 1.5;

/// **Blacks** — width of the affected range (exponent, same idea as
/// Shadows').
///   ↑ higher (e.g. 12) = only the deepest black moves
///   ↓ lower (e.g. 7)   = reaches a wider shadow range
/// default: 9.0   (original RapidRAW: 12.0)   [also on GPU: point_ops_post_denoise.frag]
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
/// default: 3.0
const double calTextureSigma = 3.0;

/// **Texture** — strength multiplier on top of the slider.
///   ↑ higher = stronger Texture     ↓ lower = weaker
/// default: 1.0
const double calTextureStrength = 1.0;

/// **Clarity** — radius (in pixels) of the local contrast. Deliberately
/// large (mid-range contrast, more like "definition").
///   ↑ higher = wider effect/bigger "halo"
///   ↓ lower  = more localized effect
/// default: 25.0
const double calClaritySigma = 25.0;

/// **Clarity** — strength multiplier on top of the slider.
///   ↑ higher = stronger Clarity     ↓ lower = weaker
/// default: 1.0
const double calClarityStrength = 1.0;

/// **Dehaze +** — how hard the positive slider pulls transmission down (=
/// removes haze). This is the main control over Dehaze strength.
///   ↑ higher (e.g. 0.85) = very aggressive Dehaze (original RapidRAW)
///   ↓ lower (e.g. 0.45) = quite gentle Dehaze
/// default: 0.55   [also on GPU: dehaze_apply.frag]
const double calDehazeTransmissionCoeff = 0.55;

/// **Dehaze** — transmission floor: keeps Dehaze from "breaking" the image
/// in the hazier spots. Higher = safer/gentler.
///   ↑ higher = caps the maximum effect (gentler)
///   ↓ lower  = lets Dehaze go further (can blow out)
/// default: 0.22   (original RapidRAW: 0.15)   [also on GPU: dehaze_apply.frag]
const double calDehazeTransmissionFloor = 0.22;

/// **Dehaze** — how much it saturates color in proportion to the haze
/// removed.
///   ↑ higher = Dehaze leaves color more "punchy"
///   ↓ lower  = Dehaze barely touches saturation
/// default: 0.32   (original RapidRAW: 0.5)   [also on GPU: dehaze_apply.frag]
const double calDehazeSatBoost = 0.32;

/// **Dehaze −** (add haze) — strength of the slider's negative side (blends
/// the image with atmospheric light, making it look "milky").
///   ↑ higher = stronger negative Dehaze
///   ↓ lower  = subtler
/// default: 0.55   (original RapidRAW: 0.7)   [also on GPU: dehaze_apply.frag]
const double calDehazeAddMix = 0.55;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  COLOR — Vibrance / Saturation                                            ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Vibrance +** — gain on the positive side. Vibrance already protects
/// skin tones and already-saturated colors; this number is the raw strength
/// before that protection kicks in.
///   ↑ higher = Vibrance +100 is much more intense
///   ↓ lower  = more restrained
/// default: 3.0
const double calVibranceStrength = 3.0;

/// **Vibrance** — how much it HOLDS BACK the effect on skin tones (so faces
/// don't turn orange). 1.0 = holds back nothing; 0.0 = zeroes out on skin.
///   ↑ higher (near 1) = skin saturates right along with everything else
///   ↓ lower (near 0) = skin stays well protected
/// default: 0.6
const double calVibranceSkinDampen = 0.6;

/// **Saturation** — multiplier on top of the slider (the effect is
/// 1 + sliderValue/100 * this number).
///   ↑ higher = stronger Saturation     ↓ lower = weaker
/// default: 1.0
const double calSaturationStrength = 1.0;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  COLOR — Color Mixer / HSL (8 bands)                                      ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Mixer → Hue** — how many degrees of hue rotation each slider unit
/// produces (before per-band normalization and the saturation mask). The
/// RapidRAW port used 0.6 (= `0.3 * 2.0`); comparing against Lightroom
/// (Filmatic Fuji 2 on DSF1309, 2026-08-29) showed the user needed ~1.9×
/// Lightroom's value on Orange/Yellow/Aqua/Blue — i.e. darkmoon's Hue was
/// too weak. Raised to 1.15.
///   ↑ higher = the same Hue slider value rotates color more
///   ↓ lower  = rotates less (0.6 = original RapidRAW behavior)
/// ⚠️ changes older presets that touched Mixer Hue (they'll rotate further).
/// default: 1.15   (original RapidRAW: 0.6)   [also on GPU: point_ops_post_denoise.frag]
const double calMixerHueStrength = 1.15;

/// **Mixer → effective band width** — the "sharpness" of the gaussian that
/// decides how much each band (Red, Orange…) influences a pixel of a given
/// hue. A HIGH number = narrower bands, less "leakage" between neighboring
/// bands (e.g. touching Green doesn't pull Yellow/Aqua along with it as
/// much). A LOW number = wider, more overlapping bands.
///   ↑ higher (e.g. 2.5) = bands more separated, more surgical effect
///   ↓ lower (e.g. 1.0) = wider bands (more "leakage")
/// Symptom of this being too low: in Lightroom you desaturate only Green,
/// but in darkmoon you have to compensate Yellow/Aqua because Green
/// "leaked" into them. The 2026-08-29 comparison suggests this may be too
/// wide; worth testing higher. Kept at 1.5 (original RapidRAW) for now.
/// default: 1.5   [also on GPU: point_ops_post_denoise.frag → rawHslInfluence]
const double calMixerBandSharpness = 1.5;

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
