// Sunbeams: slanted shafts of warm light across the land at low sun, drawn additively over the graded
// frame (before the bloom, so the brightest ones glow). World-anchored like the cloud shadows: the
// position comes from the quad's texture coordinate (`rect` is the quad in world art pixels), snapped
// to blocks of art pixels and cut into a few bands so the shafts read as pixel art. The shafts run
// along `dir`, the way the sun's shadows fall, and breathe slowly.

uniform vec4 rect;           // the quad in world art pixels: x, y, width, height
uniform vec2 dir;            // unit vector the shafts run along (away from the sun)
uniform float time;          // seconds, for the slow breathing
uniform float strength;      // 0..1 brightness of the brightest band (already scaled by the sun and the sky)
uniform float scale;         // stripe frequency across the beams, 1/art pixels
uniform float patch;         // frequency of the broad patches that break the stripes up, 1/art pixels
uniform float block;         // art pixels per beam pixel
uniform vec3 beamColor;

#ifdef PIXEL
#ifdef GL_ES
precision highp float;
#endif
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

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
    vec2 world = floor((rect.xy + uv * rect.zw) / block) * block;
    vec2 across = vec2(-dir.y, dir.x);
    float a = dot(world, across);
    float along = dot(world, dir);
    float stripes = noise(vec2(a * scale, time * 0.03)) * 0.7 + noise(vec2(a * scale * 2.7 + 9.0, -time * 0.05)) * 0.3;
    float broken = noise(vec2(along * patch + a * patch * 0.5, time * 0.02 + 4.0));
    float beam = smoothstep(0.52, 0.85, stripes) * smoothstep(0.25, 0.7, broken);
    float band = floor(beam * 3.0 + 0.5) / 3.0;
    return vec4(beamColor * band * strength, 1.0) * color;
}
#endif
