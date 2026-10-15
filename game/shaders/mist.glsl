// Morning mist: low, pale banks over the creek and the ground beside it. One translucent quad over the
// visible map, drawn after the world's sprites and before the colour grade (so dawn warms it).
// World-anchored (the position comes from the quad's texture coordinate, `rect` is the quad in world art
// pixels), snapped to blocks of art pixels and cut into a few bands so it reads as pixel art. The banks
// drift by `offset`; `strength` (time of morning, calm, damp) scales the whole thing.

uniform Image reachMap;      // one texel per tile, linear: tiles from the creek / 31
uniform float reachTiles;    // tiles inland the mist spreads over
uniform vec2 mapPixels;      // the map in art pixels
uniform vec4 rect;           // the quad in world art pixels: x, y, width, height
uniform vec2 offset;         // art pixels the banks have drifted so far
uniform float strength;      // 0..1
uniform float ground;        // 0..1 mist left over far from the creek
uniform float scale;         // noise frequency, 1/art pixels
uniform float block;         // art pixels per mist pixel
uniform float maxAlpha;
uniform vec3 mistColor;
uniform vec4 dither;         // algorithm, scale, amount, steps (include/dither.glsl)

#ifdef PIXEL
#ifdef GL_ES
precision highp float;
#endif
#include "dither"
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec2 world = rect.xy + uv * rect.zw;
    vec2 cell = floor(world / block) * block;
    float away = Texel(reachMap, (cell + 0.5 * block) / mapPixels).r * 31.0;   // tiles from the creek
    float near = clamp(1.0 - away / reachTiles, 0.0, 1.0);
    float low = ground + (1.0 - ground) * near;                     // how low-lying / creek-side this spot is
    vec2 p = (cell - offset) * scale;
    // Stretched along x so the banks lie flat on the land.
    float n = noise(p * vec2(0.7, 1.4)) * 0.65 + noise(p * vec2(1.6, 3.1) + 11.0) * 0.35;
    float d = clamp((n * 0.75 + low * 0.55 - 0.25) * 2.2, 0.0, 1.0) * strength;
    // Pixel-art density levels (the last one only where the mist is thickest); the dither interleaves them.
    float band = ditherQuantize(max(d - 0.5 / max(dither.w, 1.0), 0.0), floor(world), dither);
    return vec4(mistColor, band * maxAlpha) * color;
}
#endif
