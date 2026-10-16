// A HUD or panel plate of frosted glass, lit like the world (GDD §9.4, D142; src/ui/plate.lua).
// The world behind is read from a small blurred copy of the graded frame, cut into levels with the shared
// dither on the UI pixel grid (pixel-art frost, not a smooth blur), pulled toward the plate's own colour
// and tinted by a share of the time-of-day and season grade. The edges follow the world's top-left sun:
// a dark outline, a lit inner edge on the top and left, a cool shade on the bottom and right, and corners
// cut in steps. On frozen days frost creeps in from the corners, and snow settles along the top edge
// while the ground is white.

uniform Image frost;       // blurred, downsampled graded world (a 1x1 dummy when there is none)
uniform vec2 screenSize;   // pixels of the target
uniform float uiScale;     // target pixels per UI pixel
uniform vec4 rect;         // the plate in target pixels: x, y, w, h
uniform vec3 base;         // the plate's own colour
uniform vec3 tint;         // the grade's tint, pulled toward white by the UI share (and dimmed at night)
uniform float see;         // 0..1 how much of the world shows through
uniform vec3 litColor;
uniform float litAmount;
uniform vec3 shadeColor;
uniform float shadeAmount;
uniform vec3 inkColor;     // the outline
uniform float alpha;
uniform float cornerCut;   // UI pixels
uniform float frostAmount; // 0..1
uniform float frostReach;  // UI pixels from a corner at full frost
uniform float frostRing;   // 1 on a small plate: frost stays on the outline ring, off the middle (where an icon sits)
uniform vec3 frostColor;
uniform float snowAmount;  // 0..1
uniform vec3 snowColor;
uniform vec3 snowShade;
uniform vec2 glintAt;      // the amber glint's pixel on the plate, UI pixels (-1 = none)
uniform vec3 glintColor;
uniform vec4 dither;       // tuning.visuals.dither.plate (src/render/dither.lua)

#ifdef PIXEL
#ifdef GL_ES
precision highp float;
#endif
#include "dither"

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec2 q = floor((screen - rect.xy) / uiScale);              // UI pixel inside the plate
    vec2 size = floor(rect.zw / uiScale + 0.5);
    vec2 far = size - 1.0 - q;
    float cx = min(q.x, far.x);
    float cy = min(q.y, far.y);
    if (cx + cy < cornerCut) {
        return vec4(0.0);                                       // the stepped corner
    }
    // The world behind, one sample per UI pixel, cut into levels with the shared dither.
    vec2 cell = (floor(screen / uiScale) + 0.5) * uiScale / screenSize;
    vec3 world = Texel(frost, cell).rgb;
    if (dither.w > 0.5) {
        float t = ditherThreshold(floor(screen / uiScale), dither) - 0.5;
        world = floor(world * dither.w + t * dither.z + 0.5) / dither.w;
    }
    vec3 col = mix(base, world, see) * tint;

    float edge = min(cx, cy);
    float a = alpha;
    if (edge < 1.0 || cx + cy < cornerCut + 1.0) {
        col = inkColor;                                         // the outline, following the cut corner
        a = 0.95;
    } else if (q.y < 2.0 || q.x < 2.0) {
        col = mix(col, litColor, litAmount);                    // the sun-side edge
    } else if (far.y < 2.0 || far.x < 2.0) {
        col = mix(col, shadeColor, shadeAmount);                // the shade side
    }

    // Frost from each corner, ragged; it stays near the corners, away from text.
    if (frostAmount > 0.0) {
        float d = cx + cy;
        float reach = frostReach * frostAmount;
        float h = ditherHash(q * 1.7 + 3.1);
        if ((frostRing < 0.5 || edge < 1.0) && d < reach + cornerCut && h < (1.0 - (d - cornerCut) / max(reach, 0.001)) * 0.9) {
            col = mix(col, frostColor, edge < 1.0 ? 0.8 : 0.6);
            a = max(a, 0.9);
        }
    }
    // Snow along the top edge; the top row fills first.
    if (snowAmount > 0.0 && q.y < 3.0) {
        float h = ditherHash(vec2(q.x * 0.37, 7.0) + floor(q.x / 3.0));
        float chance = clamp(snowAmount * 1.2 - q.y * 0.35, 0.0, 1.0);
        if (h < chance) {
            col = q.y < 1.5 ? snowColor : snowShade;
            a = 1.0;
        }
    }
    // One pixel of glint on the outline (a calm amber signal, src/ui/signals.lua).
    if (abs(q.x - glintAt.x) < 0.5 && abs(q.y - glintAt.y) < 0.5) {
        col = glintColor;
        a = 1.0;
    }
    return vec4(col, a) * color;
}
#endif
