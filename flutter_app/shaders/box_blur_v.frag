#version 460 core
#include <flutter/runtime_effect.glsl>

// The vertical half of the separable box blur — see box_blur_h.frag for
// the pixel-center/UV-offset and loop-bound notes that apply here too.

uniform vec2 uSize;
uniform float uRadius;
uniform sampler2D uTexture;

out vec4 fragColor;

const int kMaxRadius = 128;
// Widest window the loop below can walk, in taps minus one.
const int kMaxSpan = 2 * kMaxRadius;

void main() {
  vec2 p = floor(FlutterFragCoord().xy);
  int radius = int(uRadius);
  if (radius <= 0) {
    fragColor = texture(uTexture, (p + 0.5) / uSize);
    return;
  }
  vec3 sum = vec3(0.0);
  int span = radius * 2;
  for (int k = 0; k <= kMaxSpan; k++) {
    if (k > span) break;
    float y = clamp(p.y + float(k - radius), 0.0, uSize.y - 1.0);
    sum += texture(uTexture, (vec2(p.x, y) + 0.5) / uSize).rgb;
  }
  fragColor = vec4(sum / float(span + 1), 1.0);
}
