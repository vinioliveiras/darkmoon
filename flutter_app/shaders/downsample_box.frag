#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of blur.dart's downsampleChannel — area-average downsample by
// an integer uFactor. Unlike the CPU version, this has no rowOffset/
// global-block-alignment concept: a GPU render always operates on the
// whole image in one pass (no row-banding like render_parallel.dart's
// CPU isolates), so the block grid is always naturally aligned to (0,0).
// Renders directly to a uFactor-times-smaller target — uSize here is the
// OUTPUT (downsampled) size, uSourceSize is the input's. See
// box_blur_h.frag for the pixel-center/UV-offset and fixed-loop-bound
// notes — this shader needs exact integer pixel indexing even more than
// the blur ones do, since a half-pixel error here shifts which whole
// source block an output pixel averages.

uniform vec2 uSize;
uniform vec2 uSourceSize;
uniform float uFactor;
uniform sampler2D uTexture;

out vec4 fragColor;

const int kMaxFactor = 16;

void main() {
  vec2 outP = floor(FlutterFragCoord().xy);
  int factor = int(uFactor);
  vec2 srcOrigin = outP * uFactor;
  vec3 sum = vec3(0.0);
  float count = 0.0;
  for (int dy = 0; dy < kMaxFactor; dy++) {
    if (dy >= factor) continue;
    float sy = srcOrigin.y + float(dy);
    if (sy >= uSourceSize.y) continue;
    for (int dx = 0; dx < kMaxFactor; dx++) {
      if (dx >= factor) continue;
      float sx = srcOrigin.x + float(dx);
      if (sx >= uSourceSize.x) continue;
      sum += texture(uTexture, (vec2(sx, sy) + 0.5) / uSourceSize).rgb;
      count += 1.0;
    }
  }
  fragColor = vec4(sum / max(count, 1.0), 1.0);
}
