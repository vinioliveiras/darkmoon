#version 460 core
#include <flutter/runtime_effect.glsl>

// The "Film" stage — GPU port of film_lut.dart's applyFilmLut: a 3D
// colour look-up table, trilinear, blended over the input by uAmount.
// Runs after post_dehaze.frag (Saturation/Vibrance/Vignette/Grain), the
// last thing renderImageGpu does, matching where render.dart's
// applyGlobalPointOps applies it on the CPU.
//
// uLut is the table packed as a 2D texture (see film_lut.dart's file
// comment): width = size*size, height = size; blue slice b starts at
// x = b*size, red runs along x inside the slice, green runs down y.
// Every texel is fetched at its centre so the sampler's own filtering
// never mixes two slices; the eight fetches below are the same eight
// corners applyFilmLut reads, weighted the same way.

uniform vec2 uSize;
uniform float uAmount; // 0..2, extrapolated past 1
uniform float uLutSize; // entries per axis (filmLutSize)
uniform sampler2D uSource;
uniform sampler2D uLut;

out vec4 fragColor;

vec3 fetchLut(float r, float g, float b) {
  float n = uLutSize;
  vec2 texel = vec2(b * n + r + 0.5, g + 0.5) / vec2(n * n, n);
  return texture(uLut, texel).rgb;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 src = texture(uSource, uv);
  float n = uLutSize - 1.0;
  vec3 f = clamp(src.rgb, 0.0, 1.0) * n;
  vec3 i0 = floor(f);
  i0 = min(i0, vec3(n));
  vec3 i1 = min(i0 + 1.0, vec3(n));
  vec3 t = f - i0;

  vec3 c000 = fetchLut(i0.r, i0.g, i0.b);
  vec3 c100 = fetchLut(i1.r, i0.g, i0.b);
  vec3 c010 = fetchLut(i0.r, i1.g, i0.b);
  vec3 c110 = fetchLut(i1.r, i1.g, i0.b);
  vec3 c001 = fetchLut(i0.r, i0.g, i1.b);
  vec3 c101 = fetchLut(i1.r, i0.g, i1.b);
  vec3 c011 = fetchLut(i0.r, i1.g, i1.b);
  vec3 c111 = fetchLut(i1.r, i1.g, i1.b);

  vec3 c00 = mix(c000, c100, t.r);
  vec3 c10 = mix(c010, c110, t.r);
  vec3 c01 = mix(c001, c101, t.r);
  vec3 c11 = mix(c011, c111, t.r);
  vec3 c0 = mix(c00, c10, t.g);
  vec3 c1 = mix(c01, c11, t.g);
  vec3 looked = mix(c0, c1, t.b);

  fragColor = vec4(clamp(mix(src.rgb, looked, uAmount), 0.0, 1.0), src.a);
}
