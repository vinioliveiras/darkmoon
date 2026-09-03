#version 460 core
#include <flutter/runtime_effect.glsl>

// Both halves of the separable box blur in one pass — exactly equivalent
// to box_blur_h.frag followed by box_blur_v.frag, since clamp-to-edge is
// itself separable (clamping x per row and then y per column gives the
// same window as clamping both here).
//
// Worth having because a pass is expensive and a tap is not. Measured on
// a 6 MP frame, every pass costs ~20-25ms regardless of what it does:
// Clarity's 41-tap blur and Texture's 5-tap blur came out at the same
// 24.4ms/pass. That cost is the render-target allocation and GPU submit
// behind each Picture.toImage(), not the shader body — so trading 2r+1
// extra taps for one fewer pass is a win at the radii this pipeline
// actually uses most.
//
// Only up to kMaxRadius: the tap count here grows as (2r+1)^2 against the
// separable pair's 2(2r+1), so the trade inverts for a wide blur.
// gpu_pass.dart's runBoxBlurGpu picks the path; see fusedBoxBlurMaxRadius
// for where the crossover was measured.
//
// See box_blur_h.frag for the pixel-center/UV-offset and loop-bound notes,
// which apply here in both dimensions.

uniform vec2 uSize;
uniform float uRadius;
uniform sampler2D uTexture;

out vec4 fragColor;

const int kMaxRadius = 16;
const int kMaxSpan = 2 * kMaxRadius;

void main() {
  vec2 p = floor(FlutterFragCoord().xy);
  int radius = int(uRadius);
  if (radius <= 0) {
    fragColor = texture(uTexture, (p + 0.5) / uSize);
    return;
  }
  int span = radius * 2;
  vec3 sum = vec3(0.0);
  for (int dy = 0; dy <= kMaxSpan; dy++) {
    if (dy > span) break;
    float y = clamp(p.y + float(dy - radius), 0.0, uSize.y - 1.0);
    for (int dx = 0; dx <= kMaxSpan; dx++) {
      if (dx > span) break;
      float x = clamp(p.x + float(dx - radius), 0.0, uSize.x - 1.0);
      sum += texture(uTexture, (vec2(x, y) + 0.5) / uSize).rgb;
    }
  }
  float taps = float(span + 1);
  fragColor = vec4(sum / (taps * taps), 1.0);
}
