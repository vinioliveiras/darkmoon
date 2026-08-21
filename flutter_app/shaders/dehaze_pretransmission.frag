#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of dehaze.dart's `preTransmission[p] = 1.0 - 0.9 *
// normalizedDark[p]` — the pointwise step between the spatial min filter
// (min_filter_h/v.frag, run on dehaze_min_channel.frag's output) and the
// box blur (box_blur_h/v.frag, radius 20) that together build the
// transmission map.

uniform vec2 uSize;
uniform sampler2D uNormalizedDark;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float d = texture(uNormalizedDark, uv).r;
  float t = 1.0 - 0.9 * d;
  fragColor = vec4(t, t, t, 1.0);
}
