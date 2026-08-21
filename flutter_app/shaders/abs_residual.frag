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
  float ch = texture(uChannel, uv).r;
  float bl = texture(uBlurred, uv).r;
  float a = abs(ch - bl);
  fragColor = vec4(a, a, a, 1.0);
}
