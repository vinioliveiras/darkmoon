#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of the residualSq computation inside blur.dart's
// adaptiveDenoiseChannel: `r = channel[i] - blurred[i]; residualSq[i] =
// r*r`. Shared by both baseline chroma smoothing (uIsChroma=1, needs
// chroma_extract.frag's bias/scale decoded first) and AI denoise's
// luminance pass (uIsChroma=0, luminance_extract.frag's output is already
// a plain 0..1 value, no decoding needed) — see chroma_extract.frag's
// comment for why chroma needs this and luminance doesn't.
//
// Output is scaled by uScale (gpuResidualSqScale, see gpu_pass.dart) and
// every consumer divides it back out. Real bug fixed 2026-09-03: this used
// to write the raw r*r into an 8-bit render target, whose quantization
// step is 1/255. Photographic noise sits far below that — a 2-level
// residual is r = 2/255, so r*r ≈ 6e-5, which rounds to exactly 0 — so the
// local noise variance every consumer reads back was zero almost
// everywhere. In denoise_combine.frag that inflated edgeWeight from ~0.44
// to ~0.80 for typical noise, i.e. the GPU path denoised roughly half as
// much as the CPU path, in the always-on baseline chroma smoothing as well
// as in AI Denoise; it also silently disabled Texture's noise-awareness
// and skewed Sharpen's masking.
//
// The scale clips (rather than wraps) at the top of the 0..1 range, which
// is the harmless direction: clipping *underestimates* the variance, and
// every consumer uses it as `rSq / (rSq + noiseVar + eps)` where a smaller
// noiseVar means less smoothing. It only clips where rSq is large anyway —
// real edges, which is exactly where these formulas want the effect
// preserved rather than smoothed away.

uniform vec2 uSize;
uniform float uIsChroma;
uniform float uScale;
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
  fragColor = vec4(clamp(r * r * uScale, 0.0, 1.0), 1.0);
}
