// Creek water.
// Drawn over every water tile in world space. Ripples are snapped to the art's pixel grid and
// quantized into a few bands so the water reads as pixel art, not a smooth gradient.
//  - depth shading: shallow at the banks -> deep mid-channel (from a per-tile depth map)
//  - ripples drift downstream along `flow`
//  - sparkles scaled by daylight
//  - animated foam where the water meets the bank
//  - `rain` (0..1): rain dimples spread as flat pixel rings, and the ripples fill with more crests (#98)
//  - `ice` (0..1) freezes it over: pale, still, with crack lines
//  World-anchored: it is drawn from a SpriteBatch, whose vertices LÖVE transforms on the GPU, so
//  vertex_position here is the world position (streamed rectangles would arrive in screen space).

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
uniform float ice;           // 0 = open water .. 1 = frozen solid
uniform vec3 iceColor;
uniform vec3 iceDeepColor;
uniform Image reflection;   // the bank's objects mirrored below their feet, in the world canvas's own pixels (transparent elsewhere)
uniform float reflectionOn;  // 0 = no reflections this frame (the image is not read)
uniform vec2 reflectionSize; // the reflection canvas in pixels (the same size as the world canvas)
uniform float pixelSize;     // canvas pixels per art pixel, so the ripple shifts the reflection by whole art pixels
uniform float reflectOpacity; // 0..1 how much of a reflection shows at the bank
uniform float reflectDistort; // art pixels the ripples push the reflection sideways at most
uniform vec3 reflectTint;    // colour multiplier on the reflected picture (darker and bluer than the real thing)
uniform vec3 skyColor;       // what the water mirrors of the open sky
uniform float skyAmount;     // 0..1 how much sky colour the water takes on in full daylight
uniform float rain;          // 0..1 how hard it rains (0 = dry)
uniform float rainCell;      // art pixels per rain ring cell (one ring at a time per cell)
uniform float rainSeconds;   // seconds a ring takes to spread and fade
uniform float rainRadius;    // art pixels, widest ring radius (rings are flat: half as tall as wide)
uniform float rainDensity;   // 0..1 chance a cell gets a ring each cycle at full rain
uniform float rainAlpha;     // 0..1 ring strength when it first lands

varying vec2 worldPos;

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    worldPos = vertex_position.xy;
    return transform_projection * vertex_position;
}
#endif

#ifdef PIXEL
#ifdef GL_ES
// World pixel coordinates run into the thousands: mediump would band the hash on phones.
precision highp float;
#endif
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

    // The sky in the water: ripple crests catch more of it, and it fades with the daylight.
    col = mix(col, skyColor, skyAmount * daylight * (0.35 + 0.65 * band) * (1.0 - ice));

    // Things on the bank, mirrored: shifted sideways by whole art pixels along rippled rows, fading with depth.
    if (reflectionOn > 0.0 && ice < 1.0) {
        float row = floor(sin(px.y * 0.9 + time * 1.7) * 1.4 + 0.5);
        float push = floor((ripple - 0.5) * reflectDistort * 2.0 + 0.5);
        vec2 ruv = (screen + vec2((row + push) * pixelSize, 0.0)) / reflectionSize;
        vec4 r = Texel(reflection, ruv);
        float fade = 1.0 - 0.5 * smoothstep(bankDepth, 0.9, depth);
        col = mix(col, r.rgb * reflectTint, step(0.5, r.a) * reflectOpacity * fade * (1.0 - ice));
    }

    // Sparkles on ripple crests, only in daylight.
    float crest = step(0.86 - 0.08 * rain, ripple) * step(0.5, hash(px + floor(time * 4.0)));
    col = mix(col, highlightColor, crest * sparkle * daylight);

    // Rain rings: a dimple lands in a cell, spreads as a flat one-pixel ring and fades.
    if (rain > 0.0) {
        vec2 cell = floor(px / rainCell);
        float t = time / rainSeconds + hash(cell);
        float cycle = floor(t);
        float age = t - cycle;
        vec2 seed = cell + cycle * 7.31;
        if (hash(seed + 5.7) < rain * rainDensity) {
            vec2 room = vec2(rainCell - 2.0 * rainRadius - 1.0, rainCell - rainRadius - 1.0);
            vec2 centre = cell * rainCell + vec2(rainRadius + 0.5, rainRadius * 0.5 + 0.5)
                + floor(vec2(hash(seed + 1.7), hash(seed + 3.1)) * room);
            vec2 d = (px - centre) * vec2(1.0, 2.0);
            float ring = step(abs(length(d) - (1.0 + age * rainRadius)), 0.7);
            col = mix(col, highlightColor, ring * (1.0 - age) * rainAlpha);
        }
    }

    // Foam hugging the banks, wobbling over time.
    float wobble = noise(px * 0.25 + vec2(time * 0.8, -time * 1.1));
    float foam = step(depth, bankDepth + foamWidth * (0.3 + 0.9 * wobble));
    col = mix(col, foamColor, foam * 0.8);

    // Ice: pale and still, darker over deep water, with fine cracks along noise ridges.
    vec3 iceCol = mix(iceColor, iceDeepColor, smoothstep(bankDepth, 0.95, depth) * 0.6);
    float cn = noise(px * 0.12);
    float crack = step(abs(cn - 0.5), 0.025);
    iceCol = mix(iceCol, iceDeepColor * 0.85, crack * 0.7);
    iceCol *= 0.97 + hash(floor(px / 3.0)) * 0.06;
    col = mix(col, iceCol, ice);

    return vec4(col, 1.0) * color;
}
#endif
