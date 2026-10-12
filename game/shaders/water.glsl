// Creek water.
// Drawn over every water tile in world space. Ripples are snapped to the art's pixel grid and
// quantized into a few bands so the water reads as pixel art, not a smooth gradient.
//  - depth shading: shallow at the banks -> deep mid-channel (from a per-tile depth map)
//  - ripples drift downstream along `flow`
//  - sparkles scaled by daylight
//  - animated foam where the water meets the bank

uniform float time;
uniform Image depthMap;      // R: 0 at the bank .. 1 at the deepest point; one texel per tile, linear filtered
uniform vec2 mapPixels;      // map size in world pixels
uniform vec2 flow;           // downstream direction * speed, in pixels per second
uniform vec3 shallowColor;
uniform vec3 deepColor;
uniform vec3 foamColor;
uniform vec3 highlightColor;
uniform float rippleScale;   // ripple noise frequency
uniform float sparkle;       // 0..1 highlight strength
uniform float foamWidth;     // depth band past the bank line where foam can appear
uniform float bankDepth;     // depth-map value exactly at the bank line
uniform float daylight;      // 0..1 from the lighting system

varying vec2 worldPos;

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    worldPos = vertex_position.xy;
    return transform_projection * vertex_position;
}
#endif

#ifdef PIXEL
// Sine-free hash (stable precision on mobile GPUs).
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
    vec2 px = floor(worldPos) + 0.5;                       // snap to art pixels
    float depth = Texel(depthMap, px / mapPixels).r;

    vec3 col = mix(shallowColor, deepColor, smoothstep(bankDepth, 0.95, depth));

    // Two noise layers drifting downstream at different speeds.
    vec2 p = (px - flow * time) * rippleScale;
    float n1 = noise(p);
    float n2 = noise(p * 1.9 + vec2(17.0, 5.0) - flow * time * rippleScale * 0.6);
    float ripple = n1 * 0.6 + n2 * 0.4;
    float band = floor(ripple * 4.0) / 4.0;                // pixel-art banding
    col *= 0.9 + band * 0.2;

    // Sparkles on ripple crests, only in daylight.
    float crest = step(0.86, ripple) * step(0.5, hash(px + floor(time * 4.0)));
    col = mix(col, highlightColor, crest * sparkle * daylight);

    // Foam hugging the banks, wobbling over time.
    float wobble = noise(px * 0.25 + vec2(time * 0.8, -time * 1.1));
    float foam = step(depth, bankDepth + foamWidth * (0.3 + 0.9 * wobble));
    col = mix(col, foamColor, foam * 0.8);

    return vec4(col, 1.0) * color;
}
#endif
