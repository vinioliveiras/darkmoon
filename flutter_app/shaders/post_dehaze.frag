#version 460 core
#include <flutter/runtime_effect.glsl>

// Fused GPU pass for Saturation + Vibrance + Vignette (in that order,
// matching RapidRAW's apply_creative_color) — the three stages
// render.dart's applyGlobalAdjustmentSteps runs *after* Dehaze. Kept as
// their own small pass (rather than folded into point_ops_post_denoise.frag)
// specifically to preserve render.dart's exact stage order without
// restructuring it: Dehaze's CPU<->GPU atmospheric-light readback has to
// sit between the point-ops pass and this one, even though none of these
// three stages themselves needs a readback — see
// project_gpu_render_plan.md's Phase 5/6 notes.

uniform vec2 uSize;
uniform float uVibranceAmount; // params.vibrance / 100.0
uniform float uSaturationFactor; // 1.0 + params.saturation / 100.0
uniform float uVignetteStrength; // params.vignette.amount/100 * 0.8
uniform float uVignetteStart; // clamp(midpoint/100, 0, 1)
uniform float uVignetteFeatherWidth; // clamp(feather/100, 0.02, 1)
uniform sampler2D uSource;

out vec4 fragColor;

const vec3 kLumaWeights = vec3(0.2126, 0.7152, 0.0722);
const float kCornerRadius = 1.4142135623730951; // sqrt(2), a corner's distance.

float srgbToLinear(float value) {
  float c = clamp(value, 0.0, 1.0);
  if (c <= 0.04045) return c / 12.92;
  return pow((c + 0.055) / 1.055, 2.4);
}

float linearToSrgb(float value) {
  float c = clamp(value, 0.0, 1.0);
  if (c <= 0.0031308) return c * 12.92;
  return 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

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

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;
  vec3 c = texture(uSource, uv).rgb;

  // RapidRAW's apply_creative_color runs on scene-linear RGB (its whole
  // pipeline stays linear until final display encode) — the luminance mix
  // below, and the saturation/hue readings driving Vibrance's masks, must
  // therefore run on linear values too, not the gamma-encoded source
  // texture directly.
  c = vec3(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b));

  // Saturation: flat gain, applied before Vibrance — matches
  // apply_creative_color in WGSL, so Vibrance's masks below read the
  // already-saturated color, not the original.
  float luminance = dot(c, kLumaWeights);
  c = luminance + (c - luminance) * uSaturationFactor;

  // RapidRAW Vibrance: saturation-aware gain with a soft skin-tone
  // dampener. The positive and negative branches intentionally use
  // different saturation masks, matching apply_creative_color in WGSL.
  // Near-gray pixels (delta below 0.02, same threshold as render.dart's
  // _applyVibrance) are left untouched entirely, not just lightly masked,
  // matching apply_creative_color's own early return.
  float maxC = max(c.r, max(c.g, c.b));
  float minC = min(c.r, min(c.g, c.b));
  if (uVibranceAmount != 0.0 && maxC - minC >= 0.02) {
    float currentSaturation = (maxC - minC) / max(maxC, 0.001);
    float hue = hueOf(c);
    float hueDistance = min(abs(hue - 25.0), 360.0 - abs(hue - 25.0));
    float isSkin = smoothstep(35.0, 10.0, hueDistance);
    float skinDampener = mix(1.0, 0.6, isSkin);
    float vibranceFactor;
    if (uVibranceAmount >= 0.0) {
      vibranceFactor = 1.0 + uVibranceAmount *
          (1.0 - smoothstep(0.4, 0.9, currentSaturation)) *
          skinDampener * 3.0;
    } else {
      vibranceFactor = 1.0 + uVibranceAmount *
          (1.0 - smoothstep(0.2, 0.8, currentSaturation));
    }
    c = luminance + (c - luminance) * vibranceFactor;
  }

  c = vec3(linearToSrgb(c.r), linearToSrgb(c.g), linearToSrgb(c.b));

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

  fragColor = vec4(c, 1.0);
}
