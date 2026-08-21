#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of blur.dart's adaptiveDenoiseChannel's final combine step:
// `edgeWeight = rSq/(rSq+localNoiseVar+1.0); denoised = blurred +
// r*edgeWeight; out = channel + (denoised-channel)*strength`. The CPU
// formula's "+1.0" epsilon is calibrated for its 0..255 working scale;
// this shader works in 0..1, so it's rescaled to 1.0/255^2 (kEpsilon)
// to keep edgeWeight's actual ratio — and therefore the denoise
// strength/behavior — identical, not just superficially similar.
//
// uIsChroma selects chroma_extract.frag's bias/scale encoding (decode the
// two inputs before the math, re-encode the result) vs luminance's plain
// 0..1 values (no encoding either way) — see chroma_extract.frag.

uniform vec2 uSize;
uniform float uIsChroma;
uniform float uStrength;
uniform sampler2D uChannel;
uniform sampler2D uBlurred;
uniform sampler2D uNoiseVar;

out vec4 fragColor;

const float kEpsilon = 1.0 / (255.0 * 255.0);

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 chRaw = texture(uChannel, uv).rgb;
  vec3 blRaw = texture(uBlurred, uv).rgb;
  vec3 noiseVar = texture(uNoiseVar, uv).rgb;
  vec3 ch = uIsChroma > 0.5 ? (chRaw * 2.0 - 1.0) : chRaw;
  vec3 bl = uIsChroma > 0.5 ? (blRaw * 2.0 - 1.0) : blRaw;

  vec3 r = ch - bl;
  vec3 rSq = r * r;
  vec3 edgeWeight = rSq / (rSq + noiseVar + kEpsilon);
  vec3 denoised = bl + r * edgeWeight;
  vec3 result = ch + (denoised - ch) * uStrength;

  fragColor = vec4(
    uIsChroma > 0.5 ? (result * 0.5 + 0.5) : result,
    1.0
  );
}
