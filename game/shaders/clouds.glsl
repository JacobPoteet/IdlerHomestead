// Cloud shadows drifting over the land. Drawn as one translucent quad over the visible part of the
// map, after everything else in the world pass and before the colour grade.
// World-anchored: the position comes from the quad's texture coordinate (`rect` is the quad in world
// art pixels), never the vertex position. The shadow is snapped to blocks of art pixels and cut into
// three bands, so it reads as pixel art rather than a smooth blur. The pattern drifts by `offset`,
// which the renderer accumulates from the weather's wind, so a gust speeds the clouds up without a jump.

uniform vec4 rect;           // the quad in world art pixels: x, y, width, height
uniform vec2 offset;         // art pixels the cloud pattern has drifted so far
uniform float coverage;      // 0..1 how overcast it is (0 = open sky)
uniform float strength;      // 0..1 alpha of the darkest band (already scaled by daylight)
uniform float scale;         // noise frequency in 1/art pixels (smaller = bigger clouds)
uniform float block;         // art pixels per shadow pixel (1 = full art resolution)
uniform vec3 shadowColor;

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
    vec2 world = rect.xy + uv * rect.zw;
    // Snap in world space, then subtract the drift, so a shadow pixel is one fixed block of land.
    vec2 cell = floor(world / block) * block;
    vec2 p = (cell - offset) * scale;
    float n = noise(p) * 0.6 + noise(p * 2.3 + 17.0) * 0.3 + noise(p * 5.1 + 3.0) * 0.1;
    // More coverage lowers the bar: sparse puffs when clear, near-total shade under storm cloud.
    float bar = 1.0 - coverage * 0.62;
    float density = smoothstep(bar, bar + 0.22, n);
    float band = floor(density * 3.0 + 0.5) / 3.0;       // pixel-art bands
    return vec4(shadowColor, band * strength) * color;
}
#endif
