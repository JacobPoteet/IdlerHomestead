// Shared dither helpers (pulled in with `#include "dither"`, see src/render/shaders.lua). Include it
// inside the PIXEL block. Each effect has its own settings in tuning.visuals.dither, packed into a vec4
// by src/render/dither.lua:  d.x = algorithm index, d.y = pattern scale (art pixels per cell),
// d.z = amount (0..1 of the pattern used), d.w = steps (brightness levels; 0 = leave smooth).
//
// Every function takes a WORLD art-pixel coordinate (whole numbers), never a screen pixel, so a pattern
// stays glued to the land when the camera pans and is the same size at every zoom.
//
// Algorithm indices (the order of tuning.visuals.dither.algorithms):
//   0 bands   no pattern: a plain cut at the middle of each step
//   1 bayer2  ordered 2x2, a coarse checker
//   2 bayer4  ordered 4x4
//   3 bayer8  ordered 8x8 (the finest regular pattern)
//   4 blue    blue noise (even, no grid look; a texture built in code, see src/render/blue_noise.lua)
//   5 ign     interleaved gradient noise (a cheap diagonal-streaked noise)
//   6 white   white noise (a hash: clumpy, for comparison)

uniform Image blueNoise;     // one texel per art pixel, tiled; the rank of the pixel in 0..1
uniform float blueSize;      // the blue-noise texture's edge in texels

// 2x2 Bayer: 0, 0.5, 0.75, 0.25 over the four cells.
float bayer2(vec2 a) {
    a = floor(a);
    return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

// 4x4 and 8x8 Bayer, recursively; thresholds in (0, 1), centred so the average is 0.5.
float bayer4(vec2 a) {
    return bayer2(a * 0.5) * 0.25 + bayer2(a);
}

float bayer8(vec2 a) {
    return bayer4(a * 0.5) * 0.25 + bayer2(a);
}

float ditherHash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// The threshold (0..1) at art pixel `px` for the algorithm in `d`.
float ditherThreshold(vec2 px, vec4 d) {
    vec2 q = floor(px / max(d.y, 1.0));
    if (d.x < 0.5) {
        return 0.5;
    } else if (d.x < 1.5) {
        return (bayer2(q) * 4.0 + 0.5) / 4.0;
    } else if (d.x < 2.5) {
        return (bayer4(q) * 16.0 + 0.5) / 16.0;
    } else if (d.x < 3.5) {
        return (bayer8(q) * 64.0 + 0.5) / 64.0;
    } else if (d.x < 4.5) {
        return Texel(blueNoise, (mod(q, blueSize) + 0.5) / blueSize).r;
    } else if (d.x < 5.5) {
        return fract(52.9829189 * fract(dot(q, vec2(0.06711056, 0.00583715))));
    }
    return ditherHash(q);
}

// `v` (0..1) snapped to d.w levels, the rounding decided by the threshold at `px`: over a patch the
// average is `v`, so a smooth ramp becomes a stipple that thickens from one level to the next instead
// of a hard ring. d.z scales how much of the pattern is used (0 = plain banding). d.w <= 0 leaves `v`.
float ditherQuantize(float v, vec2 px, vec4 d) {
    if (d.w < 0.5) {
        return v;
    }
    float t = mix(0.5, ditherThreshold(px, d), d.z);
    return clamp(floor(v * d.w + t) / d.w, 0.0, 1.0);
}

// 1 where the pattern lets `coverage` (0..1) through at `px`, else 0: a screen-door fade. The amount
// is not used here: a mask is all pattern, so callers mix it in themselves.
float ditherMask(float coverage, vec2 px, vec4 d) {
    return step(ditherThreshold(px, d), coverage);
}
