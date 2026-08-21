#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of the residualSq computation inside blur.dart's
// adaptiveDenoiseChannel: `r = channel[i] - blurred[i]; residualSq[i] =
// r*r`. Shared by both baseline chroma smoothing (uIsChroma=1, needs
// chroma_extract.frag's bias/scale decoded first) and AI denoise's
// luminance pass (uIsChroma=0, luminance_extract.frag's output is already
// a plain 0..1 value, no decoding needed) — see chroma_extract.frag's
// comment for why chroma needs this and luminance doesn't. residualSq
// itself is always in [0,1] regardless (channel/blurred are each within
// [0,1] or [-1,1], so their difference squared never needs its own
// encoding) — safe to box-blur directly downstream.

uniform vec2 uSize;
uniform float uIsChroma;
uniform sampler2D uChannel;
uniform sampler2D uBlurred;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 ch = texture(uChannel, uv).rgb;
  vec3 bl = texture(uBlurred, uv).rgb;
  if (uIsChroma > 0.5) {
    ch = ch * 2.0 - 1.0;
    bl = bl * 2.0 - 1.0;
  }
  vec3 r = ch - bl;
  fragColor = vec4(r * r, 1.0);
}
