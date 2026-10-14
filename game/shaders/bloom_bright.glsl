// Bloom, pass 1: keep only what is brighter than `threshold` (by its brightest channel, so saturated
// orange flames and lamp bulbs count as bright), with a soft knee so the cut-off never shows as an edge.
// Drawn from the graded frame into a quarter-size canvas.

uniform float threshold;     // 0..1 brightness where bloom starts
uniform float knee;          // 0..1 softness of the start

#ifdef PIXEL
#ifdef GL_ES
precision highp float;
#endif
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec3 c = Texel(tex, uv).rgb;
    float b = max(c.r, max(c.g, c.b));
    float soft = clamp(b - threshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 0.0001);
    float keep = max(soft, b - threshold) / max(b, 0.0001);
    return vec4(c * keep, 1.0);
}
#endif
