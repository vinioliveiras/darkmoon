#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of blur.dart's _boxBlurHorizontal — one half of the separable
// box-mean blur (boxBlurMean = this + box_blur_v.frag). Unlike the CPU's
// O(1)-per-pixel sliding-window sum, this resamples the whole window per
// fragment (O(radius) per pixel) — acceptable since every fragment runs
// in parallel and Phase 0 confirmed the mechanics are cheap; the sliding-
// window trick doesn't translate to a stateless per-fragment shader.
// Operates on all 3 RGB channels at once (see project_gpu_render_plan.md's
// "multi-channel packing win" — chroma smoothing packs R/G/B chroma into
// one texture instead of 3 separate single-channel passes).
//
// Two easy-to-miss precision points, both required for exact-integer
// pixel indexing to match the CPU reference (found via a failing
// downsample/upsample test, then applied here defensively too):
// FlutterFragCoord() returns the fragment's *pixel-center* coordinate
// (0.5, 1.5, ... for pixel index 0, 1, ...), so `floor()` is needed to
// recover the plain integer pixel index; and `texture()`'s UV must add
// back 0.5 before dividing by size, or bilinear sampling reads from a
// texel's edge instead of its center.
//
// The loop bound below is a compile-time constant (kMaxRadius), not
// int(uRadius) directly — Skia's runtime-effect SkSL compiler rejects a
// uniform-derived loop bound ("loop index must be compared with a
// constant expression"). kMaxRadius=128 comfortably covers every radius
// this pipeline needs (Clarity's Gaussian-approx box radii are the
// largest, well under 100); iterations beyond the real radius are
// skipped via `continue`, not computed.

uniform vec2 uSize;
uniform float uRadius;
uniform sampler2D uTexture;

out vec4 fragColor;

const int kMaxRadius = 128;

void main() {
  vec2 p = floor(FlutterFragCoord().xy);
  int radius = int(uRadius);
  if (radius <= 0) {
    fragColor = texture(uTexture, (p + 0.5) / uSize);
    return;
  }
  vec3 sum = vec3(0.0);
  for (int k = -kMaxRadius; k <= kMaxRadius; k++) {
    if (k < -radius || k > radius) continue;
    float x = clamp(p.x + float(k), 0.0, uSize.x - 1.0);
    sum += texture(uTexture, (vec2(x, p.y) + 0.5) / uSize).rgb;
  }
  fragColor = vec4(sum / float(radius * 2 + 1), 1.0);
}
