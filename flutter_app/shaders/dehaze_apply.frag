#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of dehaze.dart's final per-pixel haze formula. uTransmission is
// the box-blurred (radius 20) preTransmission map; clamped here to
// [0.2, 1.0] — matching the CPU clamp that happens right after that blur,
// before its own strength-sign branch below.
//
// uStrength = amount/100 (dehaze.dart's `strength`): >= 0 removes haze
// (dark-channel-prior inversion), < 0 adds haze (blend toward atmospheric
// light) — same two branches as applyDehaze. uSource is already 0..1
// normalized (this pipeline's universal texture convention), matching
// applyDehaze's own `norm` buffer directly — no extra /255 needed.

uniform vec2 uSize;
uniform float uStrength;
uniform vec3 uAtmosphericLight;
uniform sampler2D uSource;
uniform sampler2D uTransmission;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 norm = texture(uSource, uv).rgb;
  float transmission = clamp(texture(uTransmission, uv).r, 0.2, 1.0);

  vec3 result;
  if (uStrength >= 0.0) {
    float t = 1.0 - uStrength * (1.0 - transmission);
    result = (norm - uAtmosphericLight) / t + uAtmosphericLight;
  } else {
    float hazeAmount = -uStrength;
    result = norm * (1.0 - hazeAmount) + uAtmosphericLight * hazeAmount;
  }
  fragColor = vec4(result, 1.0);
}
