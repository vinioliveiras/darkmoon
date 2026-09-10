#version 460 core
#include <flutter/runtime_effect.glsl>

// Sharpen's edge-strength input: abs(channel - blurred), fed into a second
// (full-sigma) blur pass to estimate local edge magnitude (sharpen.dart's
// `edgeStrength`, built from `highFreq[p].abs()`). Luminance-only and
// always non-negative after abs(), so unlike chroma_extract.frag this
// needs no signed bias/scale encoding.

uniform vec2 uSize;
uniform sampler2D uChannel;
uniform sampler2D uBlurred;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  // Per channel: a replicated single channel comes out replicated (the
  // Sharpen and Clarity callers), RGB comes out per channel (Dehaze's
  // regional estimate, through gpu_pass.dart's runGuidedSmoothGpu).
  vec3 ch = texture(uChannel, uv).rgb;
  vec3 bl = texture(uBlurred, uv).rgb;
  fragColor = vec4(abs(ch - bl), 1.0);
}
