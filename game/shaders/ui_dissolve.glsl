// A dither dissolve (GDD §9.4, D142; src/render/dissolve.lua). The UI layer was drawn into a canvas; this
// puts it on screen through the shared dither on the UI pixel grid: a pixel shows once the coverage passes
// its threshold in the pattern, so a book, a card or the wheel comes in (or goes out) as a stipple that
// thickens, not as an alpha fade.

uniform float coverage;   // 0..1 share of the pattern let through
uniform float uiScale;    // target pixels per UI pixel
uniform vec4 dither;      // tuning.visuals.dither.transition (src/render/dither.lua)

#ifdef PIXEL
#ifdef GL_ES
precision highp float;
#endif
#include "dither"

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    float t = ditherThreshold(floor(screen / uiScale), dither);
    if (t >= coverage) {
        return vec4(0.0);
    }
    return Texel(tex, uv) * color;
}
#endif
