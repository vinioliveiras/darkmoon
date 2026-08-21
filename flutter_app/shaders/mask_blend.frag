#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of render.dart's renderRgbWithMasks per-pixel blend step:
// `buffer[p] = buffer[p]*(1-a) + layerBuffer[p]*a` — exactly what mix()
// computes. uAlpha is mask.dart's computeMaskAlpha output (CPU-computed;
// see mask_gpu.dart's doc comment for why mask geometry/alpha itself
// stays on CPU), uploaded as an 8-bit texture — the one real precision
// difference from CPU's continuous Float32 alpha (e.g. a CPU alpha of
// exactly 1.0 can quantize to 254/255 here), same class of quantization
// tradeoff as every other GPU pass in this pipeline.

uniform vec2 uSize;
uniform sampler2D uBase;
uniform sampler2D uLayer;
uniform sampler2D uAlpha;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 base = texture(uBase, uv).rgb;
  vec3 layer = texture(uLayer, uv).rgb;
  float a = texture(uAlpha, uv).r;
  fragColor = vec4(mix(base, layer, a), 1.0);
}
