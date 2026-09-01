#version 460 core
#include <flutter/runtime_effect.glsl>

// Fused GPU pass for Saturation + Vibrance + Vignette + Grain (in that
// order — Vignette order matches Solstice's apply_creative_color; Saturation
// and Vibrance deliberately do NOT (see render.dart's _applyVibrance doc
// comment — a direct HSV saturation multiply, hue-exact by construction, not
// Solstice's scene-linear luminance mix); Grain is the last thing
// render.dart's applyGlobalPointOps adds, after Vignette) — the stages
// render.dart's applyGlobalAdjustmentSteps runs *after* Dehaze. Kept as
// their own small pass (rather than folded into point_ops_post_denoise.frag)
// to preserve render.dart's exact stage order without restructuring it:
// Dehaze (dehaze_apply.frag) has to sit between the point-ops pass and
// this one — see project_gpu_render_plan.md's Phase 5/6 notes. (Dehaze
// itself no longer needs a CPU readback since it moved to Solstice's
// fixed-atmospheric-light algorithm — see dehaze_gpu.dart — but the pass
// split here was never about that, so it stays.)

uniform vec2 uSize;
uniform float uVibranceAmount; // params.vibrance / 100.0
uniform float uSaturationFactor; // 1.0 + params.saturation / 100.0
uniform float uVignetteStrength; // params.vignette.amount/100 * 0.8
uniform float uVignetteStart; // clamp(midpoint/100, 0, 1)
uniform float uVignetteFeatherWidth; // clamp(feather/100, 0.02, 1)
// Grain — grain.dart's applyGrain. This shader stays in 0..1 space
// throughout (unlike render.dart's 0..255 buffer), so uGrainAmount omits
// the CPU side's `* 255.0` — everything else (frequency/roughFrequency/
// roughness) is identical. 0.0 = off.
uniform float uGrainAmount;
uniform float uGrainFrequency;
uniform float uGrainRoughFrequency;
uniform float uGrainRoughness;
uniform sampler2D uSource;

out vec4 fragColor;

const vec3 kLumaWeights = vec3(0.2126, 0.7152, 0.0722);
const float kCornerRadius = 1.4142135623730951; // sqrt(2), a corner's distance.

// Hue in degrees (0-360) of [c] (0..1 components) — same convention as
// hsl.dart's rgbToHsl.
float hueOf(vec3 c) {
  float maxC = max(c.r, max(c.g, c.b));
  float minC = min(c.r, min(c.g, c.b));
  float d = maxC - minC;
  if (d < 1e-6) return 0.0;
  float hue;
  if (maxC == c.r) {
    hue = mod((c.g - c.b) / d, 6.0);
  } else if (maxC == c.g) {
    hue = (c.b - c.r) / d + 2.0;
  } else {
    hue = (c.r - c.g) / d + 4.0;
  }
  hue *= 60.0;
  if (hue < 0.0) hue += 360.0;
  return hue;
}

// Inverse of hueOf/the (maxC, sat) pair below — same convention as
// hsl.dart's hsvToRgb. Used by the Saturation/Vibrance pass so it can
// reconstruct a colour with hue and value held *exactly* fixed.
vec3 hsvToRgbLocal(float h, float s, float v) {
  float c = v * s;
  float x = c * (1.0 - abs(mod(h / 60.0, 2.0) - 1.0));
  float m = v - c;
  vec3 rgb;
  if (h < 60.0) rgb = vec3(c, x, 0.0);
  else if (h < 120.0) rgb = vec3(x, c, 0.0);
  else if (h < 180.0) rgb = vec3(0.0, c, x);
  else if (h < 240.0) rgb = vec3(0.0, x, c);
  else if (h < 300.0) rgb = vec3(x, 0.0, c);
  else rgb = vec3(c, 0.0, x);
  return rgb + m;
}

// --- Grain (grain.dart port) ---
//
// Unlike the CPU path (see grain.dart's _GradientLattice), this runs the
// per-pixel hash directly with no precomputed lattice cache: on the GPU
// every pixel is already an independent parallel invocation, so there's
// no "same 4 corners re-hashed for every pixel in a lattice cell" cost
// to amortize the way there was in the CPU's serial per-pixel loop —
// the lattice cache was a CPU-specific optimization, not something this
// shader needs.

float grainFract(float x) { return x - floor(x); }

// Port of grain.dart's _hash — note the two equal (x, z) inputs.
float grainHash(float px, float py) {
  float x = grainFract(px * 0.1031);
  float y = grainFract(py * 0.1031);
  float z = grainFract(px * 0.1031);
  float d = x * (y + 33.33) + y * (z + 33.33) + z * (x + 33.33);
  x += d;
  y += d;
  z += d;
  return grainFract((x + y) * z);
}

// Port of grain.dart's _gradientNoise (quintic-smoothed value noise).
float grainGradientNoise(float px, float py) {
  float ix = floor(px);
  float iy = floor(py);
  float fx = px - ix;
  float fy = py - iy;
  float ux = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0);
  float uy = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0);

  float gx00 = grainHash(ix, iy) * 2.0 - 1.0;
  float gy00 = grainHash(ix + 11.0, iy + 37.0) * 2.0 - 1.0;
  float gx10 = grainHash(ix + 1.0, iy) * 2.0 - 1.0;
  float gy10 = grainHash(ix + 12.0, iy + 37.0) * 2.0 - 1.0;
  float gx01 = grainHash(ix, iy + 1.0) * 2.0 - 1.0;
  float gy01 = grainHash(ix + 11.0, iy + 38.0) * 2.0 - 1.0;
  float gx11 = grainHash(ix + 1.0, iy + 1.0) * 2.0 - 1.0;
  float gy11 = grainHash(ix + 12.0, iy + 38.0) * 2.0 - 1.0;

  float dot00 = gx00 * fx + gy00 * fy;
  float dot10 = gx10 * (fx - 1.0) + gy10 * fy;
  float dot01 = gx01 * fx + gy01 * (fy - 1.0);
  float dot11 = gx11 * (fx - 1.0) + gy11 * (fy - 1.0);

  float bottom = dot00 + (dot10 - dot00) * ux;
  float top = dot01 + (dot11 - dot01) * ux;
  return bottom + (top - bottom) * uy;
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;
  vec3 c = texture(uSource, uv).rgb;

  // Saturation/Vibrance — see render.dart's _applySaturation/_applyVibrance
  // doc comments for why these are a direct HSV saturation multiply (hue
  // and value held *exactly* fixed by construction) on the gamma-encoded
  // colour directly, rather than Solstice's scene-linear luminance mix:
  // that technique is hue-preserving only when hue is measured on those
  // same linear values — gamma-encoding each channel back independently
  // afterward measurably rotates the *displayed* hue for a strong boost on
  // an already-separated colour. No linear round-trip needed here at all.

  // Saturation: flat gain, applied before Vibrance, so Vibrance's masks
  // below read the already-saturated color, not the original.
  {
    float maxC = max(c.r, max(c.g, c.b));
    float minC = min(c.r, min(c.g, c.b));
    float sat = maxC > 0.0 ? (maxC - minC) / maxC : 0.0;
    if (sat >= 1e-4) {
      float hue = hueOf(c);
      float newSat = clamp(sat * uSaturationFactor, 0.0, 1.0);
      c = hsvToRgbLocal(hue, newSat, maxC);
    }
  }

  // Vibrance: saturation-aware gain with a soft skin-tone dampener. The
  // positive and negative branches intentionally use different saturation
  // masks. Near-gray pixels (value*sat below 0.02, same threshold as
  // render.dart's _applyVibrance) are left untouched entirely.
  {
    float maxC = max(c.r, max(c.g, c.b));
    float minC = min(c.r, min(c.g, c.b));
    float sat = maxC > 0.0 ? (maxC - minC) / maxC : 0.0;
    if (uVibranceAmount != 0.0 && maxC * sat >= 0.02) {
      float hue = hueOf(c);
      float hueDistance = min(abs(hue - 25.0), 360.0 - abs(hue - 25.0));
      float isSkin = smoothstep(35.0, 10.0, hueDistance);
      float skinDampener = mix(1.0, 0.6, isSkin);
      float vibranceFactor;
      if (uVibranceAmount >= 0.0) {
        vibranceFactor = 1.0 + uVibranceAmount *
            (1.0 - smoothstep(0.4, 0.9, sat)) *
            skinDampener * 3.0;
      } else {
        vibranceFactor = 1.0 + uVibranceAmount *
            (1.0 - smoothstep(0.2, 0.8, sat));
      }
      float newSat = clamp(sat * vibranceFactor, 0.0, 1.0);
      c = hsvToRgbLocal(hue, newSat, maxC);
    }
  }

  // Vignette: radial multiplicative darkening/lightening, ellipse-shaped
  // to match the photo's aspect ratio (per-axis normalization by
  // half-width/half-height) — matches applyVignette. The ~0.5px offset
  // from using FlutterFragCoord()'s pixel-center coordinate directly
  // (instead of floor()'d) is imperceptible for this smooth radial
  // gradient, unlike Phase 2's neighbor-indexed shaders where it mattered.
  vec2 center = uSize * 0.5;
  vec2 d = (fragCoord - center) / center;
  float radius = length(d) / kCornerRadius;
  float t = clamp((radius - uVignetteStart) / uVignetteFeatherWidth, 0.0, 1.0);
  float weight = t * t * (3.0 - 2.0 * t);
  float vignetteFactor = 1.0 + uVignetteStrength * weight;
  c *= vignetteFactor;

  // Grain — matches grain.dart's applyGrain: luma-masked so it fades out
  // of deep shadows and bright highlights, on the gamma-encoded `c`
  // directly (not linear), same as the CPU path at this point in the
  // pipeline.
  if (uGrainAmount != 0.0) {
    float grainLuma = dot(c, kLumaWeights);
    if (grainLuma > 0.0) {
      float grainLumaMask = smoothstep(0.0, 0.15, grainLuma) *
          (1.0 - smoothstep(0.6, 1.0, grainLuma));
      if (grainLumaMask > 0.0) {
        // grain.dart's noise is a hash keyed off the *integer* pixel
        // coordinate — unlike the smooth vignette gradient above,
        // FlutterFragCoord()'s +0.5 pixel-center offset matters here: a
        // hash-based lattice is only continuous *within* a cell, so
        // leaving the offset in would shift some pixels into the
        // neighboring (uncorrelated) cell relative to the CPU path.
        // floor() recovers the same integer coordinate grain.dart uses.
        vec2 pixelCoord = floor(fragCoord);
        float noiseBase = grainGradientNoise(
          pixelCoord.x * uGrainFrequency,
          pixelCoord.y * uGrainFrequency
        );
        float noiseRough = grainGradientNoise(
          pixelCoord.x * uGrainRoughFrequency + 5.2,
          pixelCoord.y * uGrainRoughFrequency + 1.3
        );
        float noiseVal = noiseBase + (noiseRough - noiseBase) * uGrainRoughness;
        c += vec3(noiseVal * uGrainAmount * grainLumaMask);
      }
    }
  }

  fragColor = vec4(c, 1.0);
}
