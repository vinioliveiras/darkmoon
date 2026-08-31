#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of blur.dart's upsampleChannelBilinear — bilinear upsample by
// an integer uFactor, the inverse of downsample_box.frag. uSize here is
// the OUTPUT (full working resolution) size, uSourceSize is the smaller
// input's.
//
// Was nearest-neighbor (2026-08-31 — see upsampleChannelBilinear's own
// doc comment in blur.dart for the full story: fine at baseline chroma
// smoothing's normal subtle strength, but a hard-edged 4x4 block artifact
// once a big downstream brightness lift amplifies it). Blends the 4
// nearest downsampled texels explicitly in GLSL math (not relying on the
// sampler's own filter mode) so this stays reproducible the same way the
// old exact-texel-center nearest lookup was.

uniform vec2 uSize;
uniform vec2 uSourceSize;
uniform float uFactor;
uniform sampler2D uTexture;

out vec4 fragColor;

vec3 texel(vec2 p) {
  return texture(uTexture, (p + 0.5) / uSourceSize).rgb;
}

void main() {
  vec2 outP = floor(FlutterFragCoord().xy);
  vec2 srcCoord = clamp(
    (outP + 0.5) / uFactor - 0.5,
    vec2(0.0),
    uSourceSize - 1.0
  );
  vec2 src0 = floor(srcCoord);
  vec2 src1 = min(src0 + 1.0, uSourceSize - 1.0);
  vec2 frac = srcCoord - src0;

  vec3 top = mix(texel(vec2(src0.x, src0.y)), texel(vec2(src1.x, src0.y)), frac.x);
  vec3 bottom = mix(texel(vec2(src0.x, src1.y)), texel(vec2(src1.x, src1.y)), frac.x);
  fragColor = vec4(mix(top, bottom, frac.y), 1.0);
}
