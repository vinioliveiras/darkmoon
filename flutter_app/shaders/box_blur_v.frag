#version 460 core
#include <flutter/runtime_effect.glsl>

// The vertical half of the separable box blur — see box_blur_h.frag for
// the pixel-center/UV-offset and loop-bound notes that apply here too.

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
    float y = clamp(p.y + float(k), 0.0, uSize.y - 1.0);
    sum += texture(uTexture, (vec2(p.x, y) + 0.5) / uSize).rgb;
  }
  fragColor = vec4(sum / float(radius * 2 + 1), 1.0);
}
