// One night light: a warm pool of light on the ground around a campfire, lamp, stove or window.
// Drawn ADDITIVELY over the already-graded world, so it glows on top of the night grade rather than
// being darkened by it. World-anchored: the position comes from the quad's texture coordinate (`rect`
// is the quad in world art pixels), snapped to whole art pixels. The falloff is cut into a few
// brightness steps with a full ordered (Bayer) dither between them, so it reads as pixel art, not a soft blur.
// The pool is a little flat (taller than wide would look like a ball in the air).

uniform vec4 rect;           // the quad in world art pixels: x, y, width, height
uniform vec2 center;         // the light's centre, world art pixels
uniform float radius;        // art pixels
uniform vec3 lightColor;     // already scaled by brightness
uniform float bands;         // number of brightness steps
uniform float falloff;       // falloff exponent
uniform float dither;        // 0..1 how much of the ordered dither pattern is used between bands

#ifdef PIXEL
#ifdef GL_ES
precision highp float;
#endif
#include "dither"
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec2 px = floor(rect.xy + uv * rect.zw);
    vec2 p = px + 0.5 - center;
    float d = length(vec2(p.x, p.y * 1.25)) / radius;
    if (d >= 1.0) {
        return vec4(0.0);
    }
    float f = pow(1.0 - d, falloff);
    // Ordered (Bayer 8x8) dither between the brightness steps: the steps interleave as a stipple, so the
    // pool fades out like a gradient with no rings.
    return vec4(lightColor * ditherQuantize(f, bands, px, dither), 1.0);
}
#endif
