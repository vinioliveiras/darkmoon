#version 460 core
#include <flutter/runtime_effect.glsl>

// Baseline chroma smoothing's final step: `img[i] = clamp(luminance[i] +
// denoisedChroma[i], 0, 255)` (baseline_chroma.dart). Luminance is
// recomputed from the original (pre-denoise) source here rather than
// carried as its own texture through the pipeline — cheap (one dot
// product) and avoids a second render target.

uniform vec2 uSize;
uniform sampler2D uSource;
uniform sampler2D uDenoisedChroma;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 src = texture(uSource, uv).rgb;
  float lum = dot(src, vec3(0.2126, 0.7152, 0.0722));
  vec3 chroma = texture(uDenoisedChroma, uv).rgb * 2.0 - 1.0;
  fragColor = vec4(clamp(lum + chroma, 0.0, 1.0), 1.0);
}
