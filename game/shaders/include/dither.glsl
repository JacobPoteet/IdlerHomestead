// Shared ordered-dither helpers (pulled in with `#include "dither"`, see src/render/shaders.lua).
// Every function takes a WORLD art-pixel coordinate (whole numbers), never a screen pixel, so a pattern
// stays glued to the land when the camera pans and is the same size at every zoom.

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

float ditherThreshold(vec2 px) {
    return (bayer8(px) * 64.0 + 0.5) / 64.0;
}

// `v` (0..1) snapped to `steps` levels, the rounding decided by the dither threshold at `px`: the average
// over a patch is `v`, so a smooth ramp becomes a stipple that thickens from one level to the next
// instead of a hard ring. `amount` (0..1) scales how much of the pattern is used (0 = plain banding).
float ditherQuantize(float v, float steps, vec2 px, float amount) {
    float t = mix(0.5, ditherThreshold(px), amount);
    return clamp(floor(v * steps + t) / steps, 0.0, 1.0);
}

// 1 where the pattern lets `coverage` (0..1) through at `px`, else 0: a screen-door fade.
float ditherMask(float coverage, vec2 px) {
    return step(ditherThreshold(px), coverage);
}
