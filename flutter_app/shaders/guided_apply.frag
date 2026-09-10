#version 460 core
#include <flutter/runtime_effect.glsl>

// Last step of blur.dart's guidedSmoothChannel, per channel:
// q = mean(a) * I + mean(b), with the box-blurred coefficients from
// guided_coeff.frag.

uniform vec2 uSize;
uniform sampler2D uSource;
uniform sampler2D uMeanA;
uniform sampler2D uMeanB;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 i = texture(uSource, uv).rgb;
  vec3 a = texture(uMeanA, uv).rgb;
  vec3 b = texture(uMeanB, uv).rgb;
  fragColor = vec4(clamp(a * i + b, 0.0, 1.0), 1.0);
}
