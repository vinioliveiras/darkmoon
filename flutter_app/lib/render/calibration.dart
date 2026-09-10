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
///   Both renders read these. The GPU render is on by default for the
///   preview (export is always CPU), and since 2026-09-03 every constant
///   that has a shader counterpart reaches it as a uniform — nothing here
///   is duplicated inside a `.frag`. A comment marked  [also on GPU:
///   file.frag]  names the shader that consumes the value, so a change can
///   be checked with `integration_test/gpu_*` (see tool/gpu_test.sh).
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
const double calGlobalAmountCompression = 1.0;

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
  'ColorProfileAmount': 1.0,
  // 1.0 since 2026-09-10: the slider now delivers real stops in linear
  // light (calExposureUnitsPerStop), so the 3.0 -> 2.0 boost that used to
  // make up for a weak stage is no longer making up for anything.
  'Exposure': 1.0,
  'Contrast': 0.5,
  'Shadows': 0.5,
  'Blacks': 0.5,
  // Added 2026-09-09. These two were the only Basic tonal sliders with no
  // entry, so they alone fell through to the global fraction while their
  // four neighbours were protected — the shape of a list filled in a few
  // at a time, not of a decision. Measured on a real frame over the tones
  // each governs, at the slider's maximum: Highlights moved 1.75 levels
  // where Shadows moved 10.4. At 0.6 it moves about 3.5.
  'Highlights': 0.5,
  'Whites': 0.5,
  'Vibrance': 1.0,
  'Saturation': 0.8,
  'Dehaze': 0.4,
  'Clarity': 0.5,
  // Same gap in PRESENCE: Clarity and Dehaze had entries, Texture did not.
  'Texture': 0.5,
  // ── Shape, not amount (2026-09-09) ──────────────────────────────────
  //
  // The Amount slider answers "how much of this edit", and these are not
  // edits with a size — they are the shape the edit takes. Scaling a
  // *radius* toward its default has no meaning: a Sharpen Radius of 3.0
  // was reaching the renderer as 1.6, while SharpenAmount beside it passed
  // through untouched, so the amount was honoured and the shape it applied
  // at was not.
  //
  // The pipeline already knows this category — Temperature and Tint are
  // excluded from the scaling loop outright, on the stated grounds that
  // they "aren't naturally 0-centered deltas". These belong with them.
  // They are entries here rather than a second exclusion list so the
  // choice stays visible and adjustable in this file instead of hiding in
  // editor_screen.dart.
  //
  // VignetteAmount and GrainAmount are deliberately NOT here: those really
  // are amounts, and scaling them is what the slider is for.
  'SharpenRadius': 1.0,
  'SharpenDetail': 1.0,
  'SharpenMasking': 1.0,
  'VignetteMidpoint': 1.0,
  'VignetteFeather': 1.0,
  'GrainSize': 1.0,
  'GrainRoughness': 1.0,
  // Undamped, and the balance guard in detail_balance_test enforces it.
  // Sharpening is the counterweight to a denoise that is not damped at
  // all: measured on a detailed frame at preview scale, a Sharpen of 60
  // recovers 51% of the detail medium denoise removes when this is 1.0,
  // and only 15% when it falls through to the global 0.30 — which is the
  // "photo looks like a painting" report.
  'SharpenAmount': 1.0,
  // Family entries: any key starting with these uses them unless it has
  // an exact entry of its own, so 'Mixer' covers all 24 Colour Mixer
  // sliders and 'Grade' all 12 Colour Grading ones.
  //
  // Both are 1.0 on purpose. Until 2026-09-08 neither family was reached
  // by this scaling at all — their keys are built at runtime and were
  // never in the map it iterates — so every look built so far, and every
  // saved preset, assumes them at full strength. Damping them now would
  // quietly restyle the whole library. They are live and tunable from
  // here; changing them is a deliberate act, not a default.
  'Mixer': 0.5,
  'Grade': 0.5,
  // Real bug found 2026-09-02: dragging the "Color Profile Contrast"
  // slider (ColorProfileAmount) barely changed the render even across
  // its full range, because it fell back to the global 0.3 fraction like
  // every other slider — moving it from its default (30) to its max (60)
  // only ever actually applied 30 + (60-30)*0.3 = 39, not 60. Undamped
  // for the same reason Exposure/Contrast are: it's the one slider this
  // whole 30% rule was never meant to touch that quietly, since it's
  // itself a stand-in for a fixed baked-in curve, not a "how much of a
  // preset's edit" knob.
  //
  // Removed 2026-09-08 as unreachable under any naming: 'Shadow' (the
  // slider is 'Shadows'), 'Sharpen' ('SharpenAmount' and three shape
  // sliders), and 'MixerHueStrength' / 'MixerHueSaturation' /
  // 'MixerHueLuminance' / 'MixerHue' / 'MixerSaturation' /
  // 'MixerLuminance', none of which is a key or a family prefix — a
  // mixer key reads MixerRedHue, so only the 'Mixer' family above can
  // catch it. The first two are restored under their real names; the
  // rest were never doing anything, and reviving their values would have
  // cut the mixer to a fifth.
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

// calWbWorkingGamma (2.2) retired 2026-09-10: white balance is applied in
// linear light now (render.dart, applyExposureAndWhiteBalance), so there is
// no working-space gamma left to approximate.

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
/// Long edge (px) every neighbourhood-based radius/sigma in this file is
/// expressed against.
///
/// Sharpen, Texture, Clarity, Dehaze, the tonal blur and the always-on
/// chroma smoothing all measure their reach in pixels, so the same slider
/// value covered a different fraction of the scene at each of the three
/// resolutions an edit is rendered at — the editing preview, the dynamic
/// full-quality preview, and the export. A sigma-35 Clarity spanned 3.4%
/// of a 1024px frame and 0.45% of a 7728px one, which is why an edit
/// visibly changed strength when the full-quality pass replaced the quick
/// one, and why the preview never predicted the export. Grain and Vignette
/// already normalised this way (against 1080); these did not.
///
/// [RenderParams.renderScale] is `frameLongEdge / this`, and every such
/// radius is multiplied by it.
///
/// 1024 specifically, not Grain's 1080: it is [defaultPreviewMaxDimension],
/// so the editing preview at the default setting renders at scale 1.0 —
/// exactly what it rendered before this existed. Every constant below
/// therefore keeps the meaning it was hand-tuned to, and it is the
/// full-quality preview and the export that move to match the preview
/// rather than the other way round.
/// default: 1024.0
const double calRadiusReferenceLongEdge = 1024.0;

/// Ceiling on [RenderParams.renderScale] for the three *pixel-domain*
/// stages — the always-on chroma smoothing, AI Denoise and Sharpen.
///
/// [calRadiusReferenceLongEdge] scales every neighbourhood radius with the
/// frame so a slider covers the same fraction of the scene at every
/// resolution. That is right for Clarity and Dehaze, whose reach is a
/// property of the composition. It is wrong for noise and sharpening,
/// whose reach is a property of the sensor: grain is grain-sized in real
/// pixels no matter how many of them the frame has, and Meridian quotes
/// its own Detail radii in real pixels for exactly this reason.
///
/// Left uncapped, a 24MP export ran at renderScale 5.9 — denoise sigma
/// 11.7px, its noise window 35px, sharpen radius 5.9px — and the stages
/// inverted. Measured per frequency band against the untouched source
/// (fine 0.5-1.2px, mid 1.2-3px, coarse 3-8px), medium denoise plus the
/// default Sharpen 40:
///
///   scale 1.0 (1024px preview)  fine  95%   mid  95%   coarse 99%   halo +1%
///   scale 5.9 (24MP export)     fine 120%   mid 114%   coarse 92%   halo +18%
///
/// At export the denoise stopped removing fine grain (83% of it survived
/// medium) and ate broad structure instead, while the sharpen overshot
/// past the original and grew visible rims on hard edges. Flat smoothed
/// areas plus haloed over-contrasted edges is the recipe for an oil
/// painting, and that is what photographs came out looking like. The
/// 1024px preview renders at scale 1.0, so it could never show it.
///
///   1.0  = true pixel radii everywhere (Meridian's behaviour). Preview
///          and export no longer agree on sharpness; neither does any
///          other RAW editor, and sharpening is judged at 1:1.
///   2.0  = middle ground, half the drift, still a real cap.
///   999  = the old, uncapped behaviour.
/// default: 1.0
const double calDetailRadiusMaxScale = 1.0;

// This is the FACTORY value, and since 2026-09-09 it applies only under a
// colour profile that is not Default — Default means the photo arrives as
// decoded (see ColorProfileMode.darkmoonDefault). The per-photo override
// lives in the colour profile editor, under the tone curve. Both CPU and
// GPU apply the curve.
/// default: 80.0   (0.0 = off; 2026-08-29: originally 20.0; briefly
/// lowered to 15.0 on 2026-09-02 — photos opened a bit brighter than the
/// same RAW in Meridian — then raised past both, to 30.0, then to 80.0,
/// same day, explicit user request each time. Deliberately not touching
/// `no_auto_bright` (libraw.dart) for this — that's the decode-time
/// exposure baseline, and re-opening it risks the whole incident history
/// in project_darkmoon_color_profile.md; this S-curve is the safer,
/// purely render-time lever.)
const double calBaseContrast = 80.0;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  BASIC — Exposure / Brightness / Contrast                                 ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Exposure**: how many slider units equal 1 stop (doubling/halving the
/// light, in linear light). The effect is  2^(sliderValue / this number).
///   ↑ higher = weaker Exposure (needs a bigger drag for the same change)
///   ↓ lower  = stronger Exposure
/// default: 1.0   The slider reads -5..5 in stops, like Meridian's, and an
/// imported preset's Exposure2012 lands on it 1:1 — so one unit is one
/// real stop. History: 12.0 until 2026-09-10 (from 16.67 on 2026-09-02,
/// "still felt too weak"), back when the stage multiplied the
/// gamma-encoded buffer; that multiply moved linear light by about 2.2x
/// the nominal stops, and the number was compensating for a slider that
/// meant nothing physical. Since 2026-09-10 Exposure runs in linear light
/// (render.dart's applyExposureAndWhiteBalance), the units are real, and
/// the Amount-slider override for Exposure below went back to 1.0 with it.
const double calExposureUnitsPerStop = 1.0;

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
const double calWhitesMaskLow = 0.32;

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
/// default: 3.0   (user raised to 2.0, then 2.3, then 2.7, then asked
/// for more — 2026-09-02)
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

/// **Clarity** — edge threshold (2026-09-10). Clarity's base is an
/// edge-preserving (guided) smoothing rather than a plain blur: local
/// variation under this mean absolute deviation (0-255) is texture, which
/// Clarity boosts as before; variation over it is an edge, which the base
/// follows so the boost paints no halo across it. Measured on a synthetic
/// 60|200 step at Clarity 100: halo 19 levels → 4; the gain on a ±20
/// texture 1.55 → 1.53 (`tool/clarity_halo_probe.dart`).
///   ↑ higher = more halo, more punch on medium-contrast edges
///   ↓ lower  = less halo, but medium-contrast texture gets less Clarity
///   0 = plain Gaussian base (the pre-2026-09-10 look)
/// default: 20.0   [also on GPU: guided_ab.frag via uniform]
const double calClarityEdgeThreshold = 20.0;

/// **Dehaze +** — how hard the positive slider pulls transmission down (=
/// removes haze). This is the main control over Dehaze strength.
///   ↑ higher (e.g. 0.85) = very aggressive Dehaze (original Solstice)
///   ↓ lower (e.g. 0.45) = quite gentle Dehaze
/// default: 0.22   (original Solstice: 0.55)   [also on GPU: dehaze_apply.frag]
/// 2026-09-01: user set this to 0.1 (5.5x weaker) wanting a gentler Dehaze —
/// landed at a real but more moderate weakening instead (~1.6x), since the
/// transmission-floor bug below meant 0.1 was never actually tested against
/// a working Dehaze. Weakened again 2026-09-01 (user: "still a bit strong").
const double calDehazeTransmissionCoeff = 0.22;

/// **Dehaze** — transmission floor: keeps Dehaze from "breaking" the image
/// in the hazier spots. Higher = safer/gentler.
///   ↑ higher = caps the maximum effect (gentler)
///   ↓ lower  = lets Dehaze go further (can blow out)
/// default: 0.55   (original Solstice: 0.15)   [also on GPU: dehaze_apply.frag]
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
/// default: 0.14   (original Solstice: 0.5)   [also on GPU: dehaze_apply.frag]
/// 2026-09-01: weakened from 0.32, moderately (not all the way to the
/// user's 0.1) — same "floor bug meant this was never really tested"
/// reasoning as the coefficient above. Weakened again 2026-09-01.
const double calDehazeSatBoost = 0.14;

/// **Dehaze −** (add haze) — strength of the slider's negative side (blends
/// the image with atmospheric light, making it look "milky").
///   ↑ higher = stronger negative Dehaze
///   ↓ lower  = subtler
/// default: 0.18   (original Solstice: 0.7)   [also on GPU: dehaze_apply.frag]
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
/// default: 0.7   (original: 1.5)
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
/// default: 0.6   (2026-09-02: user's own direct edit, confirmed keep —
/// raised from 0.2, i.e. skin now holds back less than it briefly did)
const double calVibranceSkinDampen = 0.6;

/// **Saturation** — multiplier on top of the slider (the effect is
/// 1 + sliderValue/100 * this number).
///   ↑ higher = stronger Saturation     ↓ lower = weaker
/// default: 0.5   (original: 1.0)
///
/// Was 0.10 until 2026-09-09, and the comment here had been arguing
/// against itself for a week: it recorded that the decision was "a
/// moderate 2x weakening" *because* 0.1 leaves Saturation +100 as roughly
/// a 1.01x multiplier, "effectively disabling the slider rather than just
/// softening it" — and then the constant was 0.1 anyway, through three
/// rounds of further weakening.
///
/// Measured before changing it: at 0.10, Saturation at its maximum moved a
/// real frame by 1.4 levels out of 255, and by 2.8 even with the Amount
/// slider's damping removed. That is not a soft control, it is an inert
/// one, which is how it was reported. 0.5 is the value the note above
/// describes.
const double calSaturationStrength = 0.5;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  COLOR — Color Mixer / HSL (8 bands)                                      ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Mixer → how completely each hue is assigned to a band**, 0..1.
///
/// This is the difference between "surgical" and "filter", and it is not
/// a width or a sharpness.
///
/// At 1 the eight band influences are normalised to sum to 1, so every
/// pixel is fully assigned to whichever band is nearest and receives that
/// band's full slider value. Measured on a hue sweep, that means a
/// yellow-green at 90 degrees and a near-cyan at 150 both move by the
/// whole of Green's Hue slider, because Green dominates both. Narrowing
/// the band does not help: it only moves the boundary, and inside it the
/// response is still all-or-nothing.
///
/// At 0 the raw Gaussian is used as-is, so influence falls off *within*
/// the band — a hue at the centre gets the full adjustment and one near
/// the edge gets a fraction of it. That graded response is what makes a
/// colour edit read as surgical rather than as a filter.
///
/// The cost of lowering it is that hues sitting between two band centres
/// receive less total adjustment than before, so an existing preset built
/// on the mixer will render a little weaker.
///   ↑ higher = every hue fully claimed by its nearest band
///   ↓ lower  = graded falloff, edits confined nearer each band's centre
/// default: 0
const double calMixerBandNormalisation = 0.0;

/// **Mixer → band centres** — the hue each of the 8 bands is built
/// around, degrees, in the order Red, Orange, Yellow, Green, Aqua, Blue,
/// Purple, Magenta.
///
/// Not evenly spaced, and deliberately so: Red sits at 358 rather than 0
/// because the reds people adjust are the warm ones just off pure red.
const List<double> calMixerBandCentres = [
  358.0,
  25.0,
  60.0,
  115.0,
  180.0,
  225.0,
  280.0,
  330.0,
];

/// **Mixer → band widths** — how far each band reaches, degrees, same
/// order as [calMixerBandCentres].
///
/// This is the knob for "changing one colour should not change its
/// neighbours". A band's influence is a Gaussian of this width, and the
/// eight are normalised per pixel, so what matters is each width against
/// its neighbours' rather than its absolute value.
///
/// Green at 90 is the one to know about: it is twice most of the others
/// and reaches from yellow-green to cyan, so dragging Green moves a third
/// of the spectrum. Measured on a hue sweep, Green Hue at +100 visibly
/// moves every hue from 75 to 165 degrees.
///   ↑ higher = that band takes in more neighbouring hues
///   ↓ lower  = tighter selection, and more of the spectrum falls to the
///              bands either side
const List<double> calMixerBandWidths = [
  35.0,
  45.0,
  40.0,
  90.0,
  60.0,
  60.0,
  55.0,
  50.0,
];

/// **Mixer → per band** — scales one band's Hue/Saturation/Luminance
/// sliders, on top of the three global strengths below.
///
/// This is the knob for "one colour is too sensitive". The global
/// strengths move all eight bands together; this moves one. 1.0 leaves a
/// band exactly as it was, 0.5 makes its sliders half as strong, 0 makes
/// them inert.
///
/// Applied where the slider values become mixer values, which is one
/// place, ahead of both the CPU and the GPU — so there is no shader
/// counterpart to keep in step and no way for the two to disagree.
///
/// Note this changes what an existing preset does to that band, the same
/// way the global strengths do.
///
/// If a band feels sensitive because it reaches colours you did not mean
/// it to — Orange spanning 45° from a centre of 25° covers a lot of skin
/// — that is its *width*, not its strength: see [calMixerBandCentres] and
/// [calMixerBandWidths] below, which reach the shader as `uMixerBands`.
///   ↑ higher = that band's sliders bite harder
///   ↓ lower  = gentler, finer control over that colour
/// default: 1.0 for all eight
const Map<String, double> calMixerBandStrength = {
  'Red': 1.0,
  'Orange': 1.0,
  'Yellow': 1.0,
  'Green': 1.0,
  'Aqua': 1.0,
  'Blue': 1.0,
  'Purple': 1.0,
  'Magenta': 1.0,
};

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
/// default: 0.8
const double calGrainSizePxAt0 = 0.8;

/// The same, for the Size slider at 100 — see [calGrainSizePxAt0].
/// default: 4.8
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

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  UPRIGHT (Crop & Transform — Auto / Level)                                ║
// ╚══════════════════════════════════════════════════════════════════════════╝
//
// These tune a MEASUREMENT, not a render stage: Auto reads the photo and
// writes the Straighten/Vertical/Horizontal sliders, which the geometry
// pass then applies exactly as if they had been dragged by hand. So
// there is no GPU counterpart to keep in step here — the correction runs
// in `applyCropTransform`, ahead of the colour pipeline and shared by
// both paths.

/// **Upright** — how far from vertical (or horizontal) an edge may lean
/// and still be counted as part of that family.
///   ↑ higher = takes in more edges, including ones that belong to
///              nothing (a roofline read as a leaning wall)
///   ↓ lower  = only near-perfect edges count, so steep perspectives
///              stop being measurable at all
/// default: 35
const double calUprightMaxTiltDeg = 35.0;

/// **Upright** — how much the measured fan-out must exceed the edges'
/// disagreement about it before a correction is applied at all.
///
/// The single most important number here. Any three lines have a slope
/// through them; whether it means anything depends on whether the rest
/// agree. Without this gate Auto always answers, and on a photo whose
/// edges are not one family it answers with noise.
///   ↑ higher = only corrects obvious, agreeing perspectives
///   ↓ lower  = corrects more photos, and gets more of them wrong
/// default: 2
const double calUprightMinAgreement = 2.0;

/// **Upright** — how far off the robust trend a line may sit and still
/// join the least-squares refit, as a multiple of the typical miss.
///
/// The robust fit decides which lines belong; this says how generously,
/// and the refit then uses all of them properly.
///   ↑ higher = lets a stray line back into the final slope
///   ↓ lower  = discards real family members and wastes their evidence
/// default: 2.5
const double calUprightRefitCutoff = 2.5;

/// **Upright** — how many edges of a family are needed before its slope
/// is trusted.
///   ↑ higher = only corrects photos with plenty of structure
///   ↓ lower  = corrects from very little evidence
/// default: 4
const int calUprightMinLines = 4;

/// **Upright** — how far apart two edges must sit, as a fraction of how
/// far the family spans, for the slope through them to count.
///
/// A pair almost on top of each other divides by almost nothing and
/// returns a slope of almost anything.
///   ↑ higher = fewer, steadier pairs
///   ↓ lower  = more pairs, wilder tails
/// default: 0.15
const double calUprightMinPairSeparation = 0.15;

/// **Upright** — how much of the frame the measured edges must span
/// before their fan-out is believed, as a fraction of width/height.
///   ↑ higher = only corrects when edges are found across the frame
///   ↓ lower  = corrects from edges clustered in one place, which is
///              extrapolation and swings wildly
/// default: 0.25
const double calUprightMinSpread = 0.25;

/// **Upright** — corrections smaller than this (slider units) are left at
/// zero, since they are within the measurement's own noise.
///   ↑ higher = Auto ignores mild perspective
///   ↓ lower  = Auto nudges photos that did not need it
/// default: 2
const double calUprightDeadZone = 2.0;

/// **Upright** — how many candidate edges the detector may return.
///   ↑ higher = more evidence, more time, more junk edges
///   ↓ lower  = faster, but a busy photo may lose the real family
/// default: 40
const double calUprightMaxLines = 40;

/// **Upright** — how strong an edge must be, relative to the strongest in
/// the photo, to be a candidate at all.
///   ↑ higher = only bold edges count
///   ↓ lower  = faint edges join in, and with them their noise
/// default: 0.2
const double calUprightLineFloor = 0.2;

/// **Upright** — slider units per unit of measured vertical fan-out, at
/// the gentle end.
///
/// Set by measurement, not taste: `upright_auto_calibration_test.dart`
/// drives synthetic perspectives through the real geometry pass and
/// bisects for the slider value that leaves no convergence behind.
///
/// It takes two numbers because one does not fit. The geometry pass
/// anchors the bottom edge, so its response is not linear, and the
/// measured ratio climbs steadily from about 112 units per unit of
/// fan-out on a gentle perspective to about 143 on a steep one. A single
/// constant splits that difference and is then wrong at both ends —
/// worst exactly where the error shows most, on the strong perspectives.
///   ↑ higher = over-corrects, tipping verticals the other way
///   ↓ lower  = leaves some convergence in
/// default: 107 (measured)
const double calUprightVerticalGain = 107.0;

/// **Upright** — how much [calUprightVerticalGain] grows per unit of
/// fan-out, which is what makes the mapping fit both ends.
///   ↑ higher = corrects steep perspectives harder
///   ↓ lower  = flatter response, back toward a single constant
/// default: 58 (measured)
const double calUprightVerticalGainSlope = 58.0;

/// **Upright** — the same, for horizontal fan-out.
///
/// **Negative on purpose.** The two axes measure tilt against different
/// references, so their fan-out comes out opposite in sign for the same
/// physical perspective; the sign lives here rather than being hidden in
/// the measurement. Flipping it would tip a photo further over instead of
/// correcting it. Measured at -97 to -112 over the same range, which is
/// tighter than the vertical axis manages.
/// default: -101 (measured)
const double calUprightHorizontalGain = -101.0;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  BASE EXPOSURE (match the camera's own rendering)                        ║
// ╚══════════════════════════════════════════════════════════════════════════╝
//
// This tunes a MEASUREMENT that becomes a photo's starting exposure, not
// a render stage: the offset is folded into RenderParams.exposure before
// any rendering happens, so it needs no GPU counterpart — both paths get
// it through the exposure they already apply.

/// **Base exposure** — how far, in stops, the decode may be pushed to
/// reach the brightness of the camera's own embedded preview.
///
/// A cap, not a target. The measurement is a ratio of two mean
/// luminances, and the two images are not guaranteed to be the same crop
/// or even the same scene rendering — a film simulation can be a long way
/// from a neutral decode. Beyond this the comparison is more likely to be
/// wrong than the decode is.
///   ↑ higher = matches the camera more closely, trusts the preview more
///   ↓ lower  = safer against an odd preview, leaves more to correct
/// default: 1.5
const double calCameraExposureLimitStops = 1.5;

/// **Decode-time brightness** (2026-09-10): how far, in stops, the RAW
/// decode may be brightened *inside LibRaw* (`params.bright`, applied in
/// its float pipeline before the 8-bit quantisation) to land on the
/// camera's own preview. Without LibRaw's auto-bright a decode sits some
/// 2.5-4 stops under the camera's JPEG on the X-T5 frames measured, so
/// this cap is far above [calCameraExposureLimitStops], which now only
/// bounds the *residual* the render's Exposure stage spends afterwards.
///   ↑ higher = trusts the preview further
///   ↓ lower  = a decode with a strange preview stays darker
/// default: 5.0
const double calDecodeBrightLimitStops = 5.0;

/// **Decode-time brightness, no preview**: for a RAW with no embedded
/// JPEG to match, LibRaw's own auto-bright is used with this fraction of
/// the frame allowed to clip. LibRaw's default is 0.01 (1%), which is
/// what every decode used to pay; the camera's own JPEGs clip 0.05-0.6%.
///   ↑ higher = brighter, more clipping
///   ↓ lower  = darker, safer highlights
/// default: 0.001
const double calDecodeAutoBrightClip = 0.001;

/// **Camera tone match**: how much of the camera's own tonality a photo
/// opens with.
///
/// A RAW carries the camera's own JPEG rendering of the same shot, and
/// `cameraToneCurve` fits a 33-point curve mapping our decode's tonality
/// onto it. At 1.0 the photo opens looking like the camera's own
/// rendering; at 0.0 it opens on the hand-tuned [calBaseContrast] S-curve
/// instead, the way it did before 2026-09-09. In between is a blend of
/// the two curves.
///
/// Measured across three X-T5 frames: mean absolute error against the
/// camera, over the 1st-99th percentiles, is 12.5 levels at 0.0 and 0.6
/// at 1.0.
///
/// The curve replaces [calBaseContrast] rather than stacking with it, and
/// subsumes the base-exposure offset — a curve carrying the camera's whole
/// tonality carries its mean along with it, so the offset is not spent as
/// well.
///   ↑ higher = closer to the camera's own rendering
///   ↓ lower  = closer to darkmoon's own base look
/// default: 1.0
const double calCameraToneMatch = 1.0;

/// **Base exposure** — mean luma (0-1, gamma-encoded, *not* linear) below
/// which the comparison is refused.
///
/// The offset is a ratio, and a ratio of two nearly-black frames is noise
/// amplified without limit. A genuinely dark photo is exactly where a
/// wrong answer would be most visible.
///   ↑ higher = refuses more photos, leaving them as decoded
///   ↓ lower  = answers for darker frames, less reliably
/// default: 0.026   (2026-09-09: was 0.002 when the means were linearised;
/// same darkness, restated in the encoding the means are now taken in)
const double calCameraExposureLumaFloor = 0.026;
