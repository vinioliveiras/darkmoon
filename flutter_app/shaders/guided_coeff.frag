#version 460 core
#include <flutter/runtime_effect.glsl>

// Per-pixel fit of blur.dart's guidedSmoothChannel, per channel: from the
// box mean and the box mean absolute deviation of the image, either the
// `a` (uWhich = 0) or the `b` (uWhich = 1) of the local linear model
// `q = a * I + b` — one pass each, since a three-channel a and a
// three-channel b do not fit one RGBA8 texture. The fourth power (rather
// than the guided filter paper's variance ratio) is the CPU side's
// choice — see guidedSmoothChannel's doc comment for the numbers.

uniform vec2 uSize;
uniform float uThreshold; // the effect's cal*EdgeThreshold / 255
uniform float uWhich;     // 0 = a, 1 = b
uniform sampler2D uMean;
uniform sampler2D uMad;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 mean = texture(uMean, uv).rgb;
  vec3 mad = texture(uMad, uv).rgb;
  vec3 m2 = mad * mad;
  vec3 v = m2 * m2;
  float t2 = uThreshold * uThreshold;
  vec3 a = v / (v + vec3(t2 * t2));
  fragColor = vec4(uWhich > 0.5 ? (1.0 - a) * mean : a, 1.0);
}
