#version 460 core
#include <flutter/runtime_effect.glsl>

// Last step of blur.dart's guidedSmoothChannel: q = mean(a) * I + mean(b),
// with the box-blurred (a, b) pair from guided_ab.frag in uMeanAb's R
// and G. Replicated to RGB like every single-channel image in this
// pipeline, so local_contrast_combine.frag reads it as the base.

uniform vec2 uSize;
uniform sampler2D uChannel;
uniform sampler2D uMeanAb;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float l = texture(uChannel, uv).r;
  vec2 ab = texture(uMeanAb, uv).rg;
  float q = clamp(ab.r * l + ab.g, 0.0, 1.0);
  fragColor = vec4(q, q, q, 1.0);
}
