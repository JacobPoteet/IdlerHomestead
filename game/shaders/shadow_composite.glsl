// Sun shadows, composited: the shadow mask (one texel per world art pixel, drawn by shadow.glsl and
// the contact rectangles) laid over the ground in one translucent pass, so cast and contact shadows
// merge into a single darkness instead of stacking.
//  - red: a cast shadow (its strength follows the sun and the cloud)
//  - green: a contact shadow under something standing there (it stays at night)
//  - blue: the cast shadow belongs to a tree canopy, so sun flecks show through it (leaf dapple): pixel
//    blobs of light, world-anchored, that shuffle a whole art pixel at a time as the leaves sway.
// World-anchored: the art pixel comes from the mask's texture coordinate (`origin` is the world art
// pixel at the mask's top-left), never the vertex position.

uniform vec3 shadowColor;
uniform float castStrength;  // 0..1 alpha of a cast shadow right now
uniform float contactStrength; // 0..1 alpha of a contact shadow
uniform vec2 origin;         // world art pixel at the mask's top-left texel
uniform vec2 maskSize;       // the mask in texels (art pixels)
uniform float dapple;        // 0..1 how much light the flecks let through (0 = no dapple)
uniform float dappleShade;   // multiplier on a canopy's shadow between the flecks (leaves shade deeper than a post)
uniform float dappleCover;   // 0..1 share of a canopy shadow that is fleck
uniform float dappleScale;   // fleck noise frequency, 1/art pixels (higher = smaller flecks)
uniform vec2 dappleShift;    // whole art pixels the flecks are pushed by the swaying leaves
uniform float ditherAmount;  // 0..1 how much of the shadow is drawn as a dither pattern instead of a flat translucent tone
uniform float ditherAlpha;   // 0..1 alpha of one shadow pixel in the pattern (the pattern's coverage makes up the rest)

#ifdef PIXEL
#ifdef GL_ES
// World pixel coordinates run into the thousands: mediump would band the hash on phones.
precision highp float;
#endif
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
#include "dither"

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec3 m = Texel(tex, uv).rgb;
    float shade = m.r * castStrength;
    if (dapple > 0.0 && m.b > 0.5 && shade > 0.0) {
        shade = min(1.0, shade * dappleShade);
        vec2 px = origin + floor(uv * maskSize);
        // Two sizes of fleck; the shift moves the small ones further, so the pattern shimmers rather than slides.
        vec2 p = (px + dappleShift) * dappleScale;
        float n = noise(p) * 0.6 + noise((px + dappleShift * 2.0) * dappleScale * 2.6 + 13.0) * 0.4;
        float edge = 1.0 - dappleCover;
        // Two steps: a bright heart and a half-lit rim round it, so a fleck reads as a soft spot in pixel art.
        float fleck = step(edge, n) * 0.5 + step(edge + 0.07, n) * 0.5;
        shade *= 1.0 - dapple * fleck;
    }
    float a = max(shade, m.g * contactStrength);
    if (ditherAmount > 0.0 && a > 0.0) {
        // Shadow density becomes the share of art pixels that are shadow: a Bayer stipple on the world grid.
        vec2 dpx = origin + floor(uv * maskSize);
        float stipple = ditherAlpha * ditherMask(a / ditherAlpha, dpx);
        a = mix(a, stipple, ditherAmount);
    }
    return vec4(shadowColor, a) * color;
}
#endif
