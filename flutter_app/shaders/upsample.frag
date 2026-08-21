#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of blur.dart's upsampleChannelNearest — nearest-neighbor
// upsample by an integer uFactor, the inverse of downsample_box.frag.
// uSize here is the OUTPUT (full working resolution) size, uSourceSize is
// the smaller input's. See box_blur_h.frag for the pixel-center/UV-offset
// notes — this shader needs exact integer pixel indexing too, for the
// same reason downsample_box.frag does.

uniform vec2 uSize;
uniform vec2 uSourceSize;
uniform float uFactor;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 outP = floor(FlutterFragCoord().xy);
  vec2 srcPixel = floor(outP / uFactor);
  srcPixel = min(srcPixel, uSourceSize - 1.0);
  fragColor = vec4(
    texture(uTexture, (srcPixel + 0.5) / uSourceSize).rgb,
    1.0
  );
}
