// Screen-wide colour grade applied to the rendered world (not the HUD).
//  - time-of-day tint and light level (from tuning.visuals.lightKeys)
//  - the light buffer (D128): night lights are painted into `lightMap` (one texel per world art pixel),
//    and they LIGHT the picture, so a fire brightens and warms the grass and walls it reaches (the texture
//    still shows) instead of a flat glow sitting on top. The lit colour is first pulled toward grey, so
//    firelight on green grass reads warm rather than olive. A little is also added flat, so a lamp's core
//    stays bright.
//  - split toning: cool shadows, warm highlights; an S-curve contrast; a tinted lift in the blacks
//  - saturation
//  - vignette
//  - film grain on the art-pixel grid, updated at a low frame rate for a hand-made feel
//  - depth of field (#283, off by default): toward the top and bottom of the view the picture is softened
//    a step at a time, each art pixel averaged with its neighbours one or two art pixels away. Every
//    screen pixel in an art pixel computes the same average, so it stays blocky pixel art, never a smear.
//  - heat shimmer (D85): the picture is sampled a whole art pixel to the left or right in patches that
//    climb, over the land on a hot clear noon and in a column above a burning stove or campfire. The
//    patches are laid on the world's art-pixel grid (gridOrigin, worldCell), so they stay with the land.

uniform vec3 tint;
uniform float light;
uniform float saturation;
uniform Image lightMap;      // night lights, one texel per world art pixel (black where unlit)
uniform float lightAmount;   // 0 when no light is on (the map is not read), else 1
uniform vec2 lightOrigin;    // screen pixel where the light map's first texel starts
uniform vec2 lightSize;      // the light map in texels
uniform float lightGain;     // how strongly the lights brighten what they reach (multiplies the picture)
uniform float lightGlow;     // how much of the light is added flat on top
uniform float lightNeutral;  // 0..1 how far a lit colour is pulled toward grey before the light tints it
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

uniform float dof;           // 0 = no depth of field, else 0..1 strength of the softening at the edges
uniform float dofClear;      // 0..1 share of the half-height (out from the middle) that stays sharp
uniform float dofSteps;      // how many steps the softening takes toward the edge

uniform vec2 canvasSize;     // the world canvas in screen pixels
uniform vec2 gridOrigin;     // screen pixel where an art pixel starts (the camera's rounded translation)
uniform vec2 worldCell;      // the world art pixel at the origin cell, so shimmer patches stay with the land
uniform float hazeAmount;    // 0..1 how hot the day is (0 = no land shimmer)
uniform float hazeCover;     // 0..1 share of the land that wobbles at full heat
uniform vec2 hazePatch;      // patch size in art pixels
uniform float hazeRise;      // art pixels per second the patches climb
uniform float hazeSpeed;     // radians per second of the wobble
uniform float sourceSpeed;   // radians per second of a fire's column wobble
uniform float sourceSteps;   // times a second the column's wobble moves on (whole steps, so it stays chunky)
uniform float sourceWave;    // radians per art-pixel row of the wobble (its vertical frequency)
uniform float sourceDeadZone; // 0..1 wave level below which a pixel stays put (the calm between the bands)
uniform float sourceReach;   // how far the dithered column reaches: higher keeps more pixels moving toward its edges
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
#include "dither"

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
    // A fire's column works on whole art pixels: the offsets are measured from this art pixel's centre, not
    // from the screen pixel, and the wave steps in time, so nothing crawls through an art pixel as thin lines.
    vec2 centre = gridOrigin + (cell + 0.5) * pixelSize;
    float t = floor(time * sourceSteps) / sourceSteps;
    for (int i = 0; i < 4; i++) {
        if (float(i) >= heatCount) {
            break;
        }
        vec4 s = heatSources[i];
        float dx = (centre.x - s.x) / pixelSize;
        float dy = (s.y - centre.y) / pixelSize; // art pixels above the base
        float width = s.z * (1.0 - 0.5 * dy / s.w);
        if (dy > 0.0 && dy < s.w && abs(dx) < width) {
            // The wobble fades toward the top and the sides; an ordered dither decides which art pixels
            // still move, so the column thins out into a stipple instead of ending at a hard edge.
            float strength = (1.0 - dy / s.w) * (1.0 - abs(dx) / width);
            float wave = sin(floor(dy) * sourceWave - t * sourceSpeed + float(i) * 2.0);
            if (abs(wave) > sourceDeadZone && ditherMask(strength * sourceReach, cell + worldCell) > 0.5) {
                shift = wave > 0.0 ? 1.0 : -1.0;
            }
        }
    }
    return shift;
}

// The picture averaged over the art pixels round this one (`r` art pixels away), sampled at art-pixel
// centres, so every screen pixel of an art pixel gets the same colour.
vec3 soften(Image tex, vec2 centre, float r) {
    vec3 sum = vec3(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 q = centre + vec2(float(x), float(y)) * r * pixelSize;
            float w = (x == 0 && y == 0) ? 4.0 : ((x == 0 || y == 0) ? 2.0 : 1.0);
            sum += Texel(tex, clamp(q / canvasSize, vec2(0.0), vec2(1.0))).rgb * w;
        }
    }
    return sum / 16.0;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec2 suv = uv;
    vec2 p = uv * canvasSize;
    if (hazeAmount > 0.0 || heatCount > 0.0) {
        suv.x += shimmer(p) * pixelSize / canvasSize.x;
    }
    vec3 c = Texel(tex, suv).rgb;
    if (dof > 0.0) {
        vec2 centre = gridOrigin + (floor((p - gridOrigin) / pixelSize) + 0.5) * pixelSize;
        float off = abs(centre.y / canvasSize.y * 2.0 - 1.0);
        float e = floor(smoothstep(dofClear, 1.0, off) * dofSteps + 0.5) / dofSteps;
        if (e > 0.0) {
            c = mix(c, soften(tex, centre, e > 0.5 ? 2.0 : 1.0), min(1.0, e * 2.0) * dof);
        }
    }

    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(vec3(luma), c, saturation);

    vec3 lit = tint * light;
    if (lightAmount > 0.0) {
        vec3 pool = Texel(lightMap, (floor((p - lightOrigin) / pixelSize) + 0.5) / lightSize).rgb;
        vec3 surface = mix(c, vec3(dot(c, vec3(0.299, 0.587, 0.114))), lightNeutral * min(1.0, dot(pool, vec3(0.333)) * 3.0));
        c = c * lit + surface * pool * lightGain + pool * lightGlow;
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
