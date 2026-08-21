#version 460 core
#include <flutter/runtime_effect.glsl>

// The vertical half of the separable min filter — see min_filter_h.frag
// for the pixel-center/UV-offset and fixed-loop-bound notes that apply
// here too.

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
    float y = clamp(p.y + float(k), 0.0, uSize.y - 1.0);
    m = min(m, texture(uTexture, (vec2(p.x, y) + 0.5) / uSize).rgb);
  }
  fragColor = vec4(m, 1.0);
}
