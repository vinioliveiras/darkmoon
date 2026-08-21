#version 460 core
#include <flutter/runtime_effect.glsl>

// Splits a source texture into chroma (rgb - luminance per channel),
// matching baseline_chroma.dart/ai_denoise.dart's shared pattern:
// `chromaR/G/B[p] = img[i] - luminanceRgb(...)`. Luminance itself isn't
// output here — the two recombine shaders that consume denoised chroma
// each get luminance their own way (chroma_recombine.frag recomputes it
// from the original source, luma_chroma_recombine.frag takes an already-
// denoised luminance texture) rather than needing a second render target
// (dart:ui's simple Canvas-based shader API has no multi-render-target
// support).
//
// Chroma is signed (range roughly [-1, 1] in this shader's 0..1-normalized
// working space, since it's a difference of two 0..1 values) but 8-bit
// render targets are unsigned-normalized and would clip anything
// negative. Encoded here as `chroma*0.5 + 0.5` (range [-1,1] -> [0,1]) and
// decoded back in every shader that reads a chroma texture for real math
// (residual_sq.frag, denoise_combine.frag, chroma_recombine.frag,
// luma_chroma_recombine.frag) — search those files for "decode" if
// touching this encoding. Box blur/downsample/upsample need no special
// handling of this: they're linear (weighted-average) operations, so
// blurring/resampling the *encoded* values and decoding afterward gives
// the exact same result as decoding first — the affine encoding commutes
// with any linear operation.

uniform vec2 uSize;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 c = texture(uTexture, uv).rgb;
  float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
  vec3 chroma = c - lum;
  fragColor = vec4(chroma * 0.5 + 0.5, 1.0);
}
