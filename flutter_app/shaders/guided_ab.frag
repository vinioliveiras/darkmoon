#version 460 core
#include <flutter/runtime_effect.glsl>

// Per-pixel fit of blur.dart's guidedSmoothChannel: from the box mean
// and the box mean absolute deviation of the luminance, the `a` and `b`
// of the local linear model `q = a * I + b`. Packed as R = a, G = b so
// the next box blur averages both in one pass. The fourth power (rather
// than the guided filter paper's variance ratio) is the CPU side's
// choice — see guidedSmoothChannel's doc comment for the numbers.

uniform vec2 uSize;
uniform float uThreshold; // calClarityEdgeThreshold / 255
uniform sampler2D uMean;
uniform sampler2D uMad;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float mean = texture(uMean, uv).r;
  float mad = texture(uMad, uv).r;
  float m2 = mad * mad;
  float v = m2 * m2;
  float t2 = uThreshold * uThreshold;
  float a = v / (v + t2 * t2);
  fragColor = vec4(a, (1.0 - a) * mean, 0.0, 1.0);
}
