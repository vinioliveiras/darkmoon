#version 460 core
#include <flutter/runtime_effect.glsl>

// Replace color — GPU port of replace_color.dart's applyReplaceColor:
// pixels near the picked colour (RGB distance, full inside uCore, a
// smoothstep ramp over uFeather) move in hue, saturation and value, and
// the result blends over the source by that weight times uAmount. The
// last global pass, after film_lut.frag / post_dehaze.frag, exactly
// where render.dart's applyGlobalPointOps runs it.

uniform vec2 uSize;
uniform vec3 uRef;       // the picked colour, 0..1
uniform float uCore;     // full-weight distance, 0..255 units
uniform float uFeather;  // ramp past uCore, 0..255 units
uniform float uHue;      // degrees
uniform float uSatMul;   // 1 + saturation/100
uniform float uLumMul;   // 1 + luminance/100
uniform float uAmount;   // 0..1
uniform sampler2D uSource;

out vec4 fragColor;

// Mirrors hsl.dart's rgbToHsv (h in degrees, s/v in 0..1).
vec3 rgbToHsv(vec3 c) {
  float maxC = max(c.r, max(c.g, c.b));
  float minC = min(c.r, min(c.g, c.b));
  float d = maxC - minC;
  float hue = 0.0;
  if (d > 0.0) {
    if (maxC == c.r) {
      hue = 60.0 * mod((c.g - c.b) / d, 6.0);
    } else if (maxC == c.g) {
      hue = 60.0 * ((c.b - c.r) / d + 2.0);
    } else {
      hue = 60.0 * ((c.r - c.g) / d + 4.0);
    }
    if (hue < 0.0) hue += 360.0;
  }
  return vec3(hue, maxC == 0.0 ? 0.0 : d / maxC, maxC);
}

// Mirrors hsl.dart's hsvToRgb.
vec3 hsvToRgb(float h, float s, float v) {
  float c = v * s;
  float x = c * (1.0 - abs(mod(h / 60.0, 2.0) - 1.0));
  float m = v - c;
  vec3 rgb;
  if (h < 60.0) rgb = vec3(c, x, 0.0);
  else if (h < 120.0) rgb = vec3(x, c, 0.0);
  else if (h < 180.0) rgb = vec3(0.0, c, x);
  else if (h < 240.0) rgb = vec3(0.0, x, c);
  else if (h < 300.0) rgb = vec3(x, 0.0, c);
  else rgb = vec3(c, 0.0, x);
  return rgb + m;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 src = texture(uSource, uv);
  vec3 c = clamp(src.rgb, 0.0, 1.0);
  float dist = length((c - uRef) * 255.0);
  float w;
  if (dist <= uCore) {
    w = 1.0;
  } else if (uFeather <= 0.0 || dist >= uCore + uFeather) {
    w = 0.0;
  } else {
    float t = clamp((dist - uCore) / uFeather, 0.0, 1.0);
    w = 1.0 - t * t * (3.0 - 2.0 * t);
  }
  w *= uAmount;
  if (w <= 0.0) {
    fragColor = src;
    return;
  }
  vec3 hsv = rgbToHsv(c);
  float nh = mod(hsv.x + uHue, 360.0);
  if (nh < 0.0) nh += 360.0;
  vec3 moved = hsvToRgb(nh, clamp(hsv.y * uSatMul, 0.0, 1.0),
                        clamp(hsv.z * uLumMul, 0.0, 1.0));
  fragColor = vec4(mix(c, moved, w), src.a);
}
