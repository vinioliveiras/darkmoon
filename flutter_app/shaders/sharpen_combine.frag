#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of sharpen.dart's applySharpen final per-pixel combine step.
// Unlike the CPU version's `if (params.detail > 0)` / `if (maskAmount > 0)`
// branches (skipped entirely when off, to avoid wasted work), this shader
// always computes both terms and lets uDetailMix/uMaskAmount naturally
// zero out their own contribution when the corresponding slider is 0:
//   - detailMix=0  -> residual*(1-0) + fineResidual*0 == residual
//   - maskAmount=0 -> factor *= 1 - 0*(1-edgeWeight) == factor
// so the result is identical to the CPU branches regardless of what
// uFineBlurred/uEdgeStrength/uNoiseVar actually contain in that case —
// see sharpen_gpu.dart's doc comment for why this lets the orchestration
// skip conditional uniform flags entirely (unlike local_contrast_combine.frag,
// which has no such natural-zero-cancellation and needs explicit flags).

uniform vec2 uSize;
uniform float uStrength;   // amount / 100
uniform float uDetailMix;  // detail / 100
uniform float uMaskAmount; // masking / 100
uniform sampler2D uSource;
uniform sampler2D uLuminance;
uniform sampler2D uBlurred;
uniform sampler2D uFineBlurred;
uniform sampler2D uEdgeStrength;
uniform sampler2D uNoiseVar;

out vec4 fragColor;

// sharpen.dart's edgeThreshold=6.0 is calibrated on the 0-255 scale;
// rescaled to this shader's 0..1 working space (magnitude / 255, then
// squared) to keep edgeWeight's ratio identical.
const float kEdgeThreshold = 6.0 / 255.0;
const float kEdgeThresholdVar = kEdgeThreshold * kEdgeThreshold;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 source = texture(uSource, uv).rgb;
  float luminance = texture(uLuminance, uv).r;
  float blurred = texture(uBlurred, uv).r;
  float fineBlurred = texture(uFineBlurred, uv).r;
  float edge = texture(uEdgeStrength, uv).r;
  float noiseVar = texture(uNoiseVar, uv).r;

  float residual = luminance - blurred;
  float fineResidual = luminance - fineBlurred;
  residual = residual * (1.0 - uDetailMix * 0.6) + fineResidual * uDetailMix;

  float edgeSq = edge * edge;
  float edgeWeight = edgeSq / (edgeSq + noiseVar + kEdgeThresholdVar);
  float factor = uStrength * (1.0 - uMaskAmount * (1.0 - edgeWeight));

  float delta = residual * factor;
  fragColor = vec4(source + vec3(delta), 1.0);
}
