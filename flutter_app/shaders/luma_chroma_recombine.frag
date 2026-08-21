#version 460 core
#include <flutter/runtime_effect.glsl>

// AI denoise (classical)'s final step: `img[i] = clamp(denoisedLuma[i] +
// denoisedChroma[i], 0, 255)` (ai_denoise.dart). Unlike
// chroma_recombine.frag, both inputs here are already-denoised outputs of
// their own separate adaptiveDenoiseChannel pipelines (different sigma/
// strength for luma vs chroma), not recomputed from the original source.

uniform vec2 uSize;
uniform sampler2D uDenoisedLuma;
uniform sampler2D uDenoisedChroma;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float lum = texture(uDenoisedLuma, uv).r;
  vec3 chroma = texture(uDenoisedChroma, uv).rgb * 2.0 - 1.0;
  fragColor = vec4(clamp(lum + chroma, 0.0, 1.0), 1.0);
}
