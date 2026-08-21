#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of blur.dart's _minFilterHorizontal — one half of the
// separable sliding-window minimum ("erosion"), used by Dehaze's dark-
// channel estimate. Same per-fragment resampling tradeoff as
// box_blur_h.frag (min isn't a linear filter, so the CPU's own sliding-
// window trick doesn't apply there either — this shader isn't a
// regression versus the CPU's own O(radius)-per-pixel cost, just a port
// of it). See box_blur_h.frag for the pixel-center/UV-offset and
// fixed-loop-bound notes that apply here too.

uniform vec2 uSize;
uniform float uRadius;
uniform sampler2D uTexture;

out vec4 fragColor;

const int kMaxRadius = 32;

void main() {
  vec2 p = floor(FlutterFragCoord().xy);
  int radius = int(uRadius);
  vec3 m = texture(uTexture, (p + 0.5) / uSize).rgb;
  if (radius <= 0) {
    fragColor = vec4(m, 1.0);
    return;
  }
  for (int k = -kMaxRadius; k <= kMaxRadius; k++) {
    if (k < -radius || k > radius) continue;
    float x = clamp(p.x + float(k), 0.0, uSize.x - 1.0);
    m = min(m, texture(uTexture, (vec2(x, p.y) + 0.5) / uSize).rgb);
  }
  fragColor = vec4(m, 1.0);
}
