// Screen-wide colour grade applied to the rendered world (not the HUD).
//  - time-of-day tint and light level (from tuning.visuals.lightKeys)
//  - the light buffer (D128): night lights are painted into `lightMap`, and they LIGHT the picture, so a
//    fire brightens and warms the grass and walls it reaches (the texture still shows) instead of a flat
//    glow sitting on top. A little of the light is also added flat, so a lamp's core stays bright.
//  - split toning: cool shadows, warm highlights; an S-curve contrast; a tinted lift in the blacks
//  - saturation
//  - vignette
//  - film grain on the art-pixel grid, updated at a low frame rate for a hand-made feel
//  - heat shimmer (D85): the picture is sampled a whole art pixel to the left or right in patches that
//    climb, over the land on a hot clear noon and in a column above a burning stove or campfire. The
//    patches are laid on the world's art-pixel grid (gridOrigin, worldCell), so they stay with the land.

uniform vec3 tint;
uniform float light;
uniform float saturation;
uniform Image lightMap;      // night lights painted in the world canvas's own pixels (black where unlit)
uniform float lightAmount;   // 0 when no light is on (the map is not read), else 1
uniform float lightGain;     // how strongly the lights brighten what they reach (multiplies the picture)
uniform float lightGlow;     // how much of the light is added flat on top
uniform vec3 shadowTone;     // colour multiplier for the darks
uniform vec3 highlightTone;  // colour multiplier for the brights
uniform float toneMid;       // luma where the tone swings from shadowTone to highlightTone
uniform float toneWidth;     // luma span of that swing
uniform float contrast;      // 0..1 strength of the S-curve
uniform vec3 blackLift;      // light added to the darkest pixels (a tinted, milky black)
uniform float vignette;
uniform float grain;
uniform float time;
uniform float pixelSize;     // screen pixels per art pixel, so grain matches the pixel art

uniform vec2 canvasSize;     // the world canvas in screen pixels
uniform vec2 gridOrigin;     // screen pixel where an art pixel starts (the camera's rounded translation)
uniform vec2 worldCell;      // the world art pixel at the origin cell, so shimmer patches stay with the land
uniform float hazeAmount;    // 0..1 how hot the day is (0 = no land shimmer)
uniform float hazeCover;     // 0..1 share of the land that wobbles at full heat
uniform vec2 hazePatch;      // patch size in art pixels
uniform float hazeRise;      // art pixels per second the patches climb
uniform float hazeSpeed;     // radians per second of the wobble
uniform float sourceSpeed;   // radians per second of a fire's column wobble
uniform float heatCount;     // shimmering fires in view (at most 4)
uniform vec4 heatSources[4]; // x, y: column base in screen pixels; z: half-width, w: height, in art pixels

#ifdef PIXEL
#ifdef GL_ES
// The grain seed grows with `time`: mediump would overflow and band it on phones.
precision highp float;
#endif
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Whole art pixels (-1, 0 or 1) to shift the picture sideways at this screen pixel.
float shimmer(vec2 p) {
    float shift = 0.0;
    vec2 cell = floor((p - gridOrigin) / pixelSize);
    if (hazeAmount > 0.0) {
        vec2 wc = cell + worldCell;
        vec2 patch = floor(vec2(wc.x / hazePatch.x, (wc.y + time * hazeRise) / hazePatch.y));
        if (hash(patch) < hazeCover * hazeAmount) {
            shift = sin(wc.y * 1.3 + time * hazeSpeed) > 0.0 ? 1.0 : -1.0;
        }
    }
    for (int i = 0; i < 4; i++) {
        if (float(i) >= heatCount) {
            break;
        }
        vec4 s = heatSources[i];
        float dx = (p.x - s.x) / pixelSize;
        float dy = (s.y - p.y) / pixelSize;      // art pixels above the base
        if (dy > 0.0 && dy < s.w && abs(dx) < s.z * (1.0 - 0.5 * dy / s.w)) {
            float wave = sin(dy * 1.1 - time * sourceSpeed + float(i) * 2.0) * (1.0 - dy / s.w);
            if (wave > 0.15) {
                shift = 1.0;
            } else if (wave < -0.15) {
                shift = -1.0;
            }
        }
    }
    return shift;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec2 suv = uv;
    if (hazeAmount > 0.0 || heatCount > 0.0) {
        suv.x += shimmer(uv * canvasSize) * pixelSize / canvasSize.x;
    }
    vec3 c = Texel(tex, suv).rgb;

    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(vec3(luma), c, saturation);

    vec3 lit = tint * light;
    if (lightAmount > 0.0) {
        vec3 pool = Texel(lightMap, uv).rgb;
        c = c * (lit + pool * lightGain) + pool * lightGlow;
    } else {
        c *= lit;
    }

    float tone = smoothstep(toneMid - toneWidth, toneMid + toneWidth, dot(c, vec3(0.299, 0.587, 0.114)));
    c *= mix(shadowTone, highlightTone, tone);
    c = clamp(c, 0.0, 1.0);
    c = mix(c, c * c * (3.0 - 2.0 * c), contrast);
    c += blackLift * (1.0 - c);

    vec2 d = uv - 0.5;
    c *= 1.0 - vignette * smoothstep(0.15, 0.6, dot(d, d) * 2.0);

    vec2 cell = floor(screen / pixelSize);
    float g = hash(cell + floor(time * 12.0) * 13.7) - 0.5;
    c += g * grain;

    return vec4(c, 1.0) * color;
}
#endif
