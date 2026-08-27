#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform sampler2D uTexture;
out vec4 fragColor;

float toLinear(float value) {
  if (value <= 0.04045) return value / 12.92;
  return pow((value + 0.055) / 1.055, 2.4);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 c = texture(uTexture, uv).rgb;
  fragColor = vec4(toLinear(c.r), toLinear(c.g), toLinear(c.b), 1.0);
}
