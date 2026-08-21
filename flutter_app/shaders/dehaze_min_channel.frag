#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of dehaze.dart's per-pixel step feeding into its dark-channel
// spatial min filter: divide each channel by the atmospheric-light
// estimate (uAtmosphericLight, computed on CPU — see
// estimateAtmosphericLight's doc comment for why that one step stays
// CPU-side), then keep the minimum of the three normalized channels.
// This is NOT itself the spatial min filter — min_filter_h/v.frag runs
// next on this shader's output to produce normalizedDark.

uniform vec2 uSize;
uniform vec3 uAtmosphericLight;
uniform sampler2D uSource;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 c = texture(uSource, uv).rgb / uAtmosphericLight;
  float m = min(c.r, min(c.g, c.b));
  fragColor = vec4(m, m, m, 1.0);
}
