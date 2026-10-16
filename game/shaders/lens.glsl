// The Power and Water lenses (GDD §9.4, D141, D145; src/render/lens.lua). One full-screen pass over the graded
// frame: the world is washed to a cool blueprint, then one system is painted over it in dither density, so a
// value reads by pattern as well as colour. Everything is cut on the world's art-pixel grid, and the dither
// settings (tuning.visuals.dither.lens, include/dither.glsl) decide the pattern and the number of bands.
//
// dataMap has one texel per tile. Power: r = source pools, g = sink bands, b = sinks short of power.
// Water: r = water table, g = irrigation coverage, b = ground a well or pump can go on, a = dry coverage.
// Connections, reach rings and gauges are drawn by the renderer over this pass.

uniform Image dataMap;       // one texel per tile, nearest filtered
uniform vec2 mapTiles;       // the map in tiles
uniform float tileSize;      // art pixels per tile
uniform vec2 gridOrigin;     // screen pixel where an art pixel starts (the camera's rounded translation)
uniform float pixelSize;     // screen pixels per art pixel
uniform float mode;          // 1 = power, 2 = water
uniform vec3 washTint;       // the blueprint's cool multiplier
uniform float washKeep;      // 0..1 share of the world's colour that stays
uniform float washAmount;    // 0..1 strength of the wash
uniform float washDarken;    // brightness multiplier of the washed world
uniform float dim;           // 0..1 brightness of the painted layer (lower at night)
uniform float alpha;         // 0..1 opacity of a painted pixel
uniform float edgeAlpha;     // 0..1 opacity of a contour line
uniform vec4 dither;         // algorithm, scale, amount, steps (include/dither.glsl)
uniform vec3 cSource;
uniform vec3 cSink;
uniform vec3 cShort;
uniform vec3 cTable;
uniform vec3 cCover;
uniform vec3 cDry;
uniform vec3 cSpot;
uniform vec3 cLine;
uniform float coverDensity;  // 0..1 stipple density of coverage at one line
uniform float spotDensity;   // 0..1 stipple density on ground a well or pump can go on
uniform float tableFloor;    // 0..1 water table below which nothing is painted

#ifdef PIXEL
#ifdef GL_ES
precision highp float;
#endif
#include "dither"

vec4 tileAt(vec2 t) {
    vec2 c = clamp(floor(t), vec2(0.0), mapTiles - 1.0);
    return Texel(dataMap, (c + 0.5) / mapTiles);
}

// Bilinear between tile centres, so pools and bands are round, not square.
vec4 smoothAt(vec2 t) {
    vec2 p = t - 0.5;
    vec2 i = floor(p);
    vec2 f = p - i;
    vec4 top = mix(tileAt(i), tileAt(i + vec2(1.0, 0.0)), f.x);
    vec4 bottom = mix(tileAt(i + vec2(0.0, 1.0)), tileAt(i + vec2(1.0, 1.0)), f.x);
    return mix(top, bottom, f.y);
}

// Paint `col` into `c` where band level `q` (0..1) and the pattern say so: the denser the band, the more
// pixels are inked, and the inked ones are brighter.
vec3 band(vec3 c, vec3 col, float q, vec2 cell) {
    if (q <= 0.0) {
        return c;
    }
    float m = ditherMask(0.3 + 0.7 * q, cell + vec2(5.0, 2.0), dither);
    return mix(c, col * mix(0.6, 1.0, q) * dim, m * alpha);
}

float tableLevel(vec2 cell) {
    float v = smoothAt((cell + 0.5) / tileSize).r;
    return max(v - tableFloor, 0.0) / (1.0 - tableFloor);
}

float tableBand(vec2 cell) {
    return floor(tableLevel(cell) * max(dither.w, 1.0));
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec4 src = Texel(tex, uv);
    vec2 cell = floor((screen - gridOrigin) / pixelSize);
    float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
    vec3 wash = mix(vec3(luma), src.rgb, washKeep) * washTint * washDarken;
    vec3 c = mix(src.rgb, wash, washAmount);
    vec2 t = (cell + 0.5) / tileSize;
    if (t.x < 0.0 || t.y < 0.0 || t.x > mapTiles.x || t.y > mapTiles.y) {
        return vec4(c, src.a);
    }
    if (mode < 1.5) {
        vec4 d = smoothAt(t);
        c = band(c, cSource, ditherQuantize(d.r, cell, dither), cell);
        c = band(c, cSink, ditherQuantize(d.g, cell + vec2(2.0, 7.0), dither), cell);
        c = band(c, cShort, ditherQuantize(d.b, cell + vec2(2.0, 7.0), dither), cell + vec2(1.0, 1.0));
    } else {
        c = band(c, cTable, ditherQuantize(tableLevel(cell), cell, dither), cell);
        float here = tableBand(cell);
        if (here > 0.0 && (tableBand(cell + vec2(1.0, 0.0)) != here || tableBand(cell + vec2(0.0, 1.0)) != here)) {
            c = mix(c, cLine * dim, edgeAlpha);
        }
        vec4 d = tileAt(t);
        if (d.g > 0.0) {
            vec3 col = d.a > 0.0 ? cDry : cCover;
            float density = min(0.95, coverDensity * (0.5 + 2.0 * d.g));
            c = mix(c, col * dim, ditherMask(density, cell + vec2(3.0, 9.0), dither) * alpha * 0.8);
            float e1 = tileAt((cell + vec2(1.0, 0.0) + 0.5) / tileSize).g;
            float e2 = tileAt((cell - vec2(1.0, 0.0) + 0.5) / tileSize).g;
            float e3 = tileAt((cell + vec2(0.0, 1.0) + 0.5) / tileSize).g;
            float e4 = tileAt((cell - vec2(0.0, 1.0) + 0.5) / tileSize).g;
            if (min(min(e1, e2), min(e3, e4)) <= 0.0) {
                c = mix(c, col * dim, alpha);
            }
        }
        if (d.b > 0.5) {
            c = mix(c, cSpot * dim, ditherMask(spotDensity, cell + vec2(7.0, 3.0), dither) * alpha);
        }
    }
    return vec4(c, src.a);
}
#endif
