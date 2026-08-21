#version 460 core
#include <flutter/runtime_effect.glsl>

// Rec.709 luminance, replicated across RGB so the result can flow through
// the same generic box-blur/downsample/upsample pipeline any other
// "channel" texture does (luminance.dart's luminanceRgb, normalized to
// 0..1 instead of 0..255 — matches every other GPU shader's working
// space).

uniform vec2 uSize;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float lum = dot(texture(uTexture, uv).rgb, vec3(0.2126, 0.7152, 0.0722));
  fragColor = vec4(lum, lum, lum, 1.0);
}
