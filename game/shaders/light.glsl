// One night light: a warm pool of light on the ground around a campfire, lamp, stove or window.
// Drawn ADDITIVELY over the already-graded world, so it glows on top of the night grade rather than
// being darkened by it. World-anchored: the position comes from the quad's texture coordinate (`rect`
// is the quad in world art pixels), snapped to whole art pixels. The falloff is cut into a few
// brightness bands with a light ordered dither between them, so it reads as pixel art, not a soft blur.
// The pool is a little flat (taller than wide would look like a ball in the air).

uniform vec4 rect;           // the quad in world art pixels: x, y, width, height
uniform vec2 center;         // the light's centre, world art pixels
uniform float radius;        // art pixels
uniform vec3 lightColor;     // already scaled by brightness
uniform float bands;         // number of brightness steps
uniform float falloff;       // falloff exponent
uniform float dither;        // 0..1 ordered dither between bands

#ifdef PIXEL
#ifdef GL_ES
precision highp float;
#endif
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec2 px = floor(rect.xy + uv * rect.zw);
    vec2 p = px + 0.5 - center;
    float d = length(vec2(p.x, p.y * 1.25)) / radius;
    if (d >= 1.0) {
        return vec4(0.0);
    }
    float f = pow(1.0 - d, falloff);
    // 2x2 ordered dither: 0, 2, 3, 1 over the art-pixel grid.
    float b = mod(mod(px.x, 2.0) * 2.0 + mod(px.y, 2.0) * 3.0, 4.0) / 4.0 - 0.375;
    float band = clamp(floor(f * bands + b * dither * 2.0) / bands, 0.0, 1.0);
    return vec4(lightColor * band, 1.0);
}
#endif
