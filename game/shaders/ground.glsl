// The ground canvas's weather coat: wet ground and puddles, frost creeping in from the creek bank,
// and snow cover. Drawn with the static ground canvas, so every pixel is a world art pixel.
//  - wet (0..1): the grass and road darken and gain a glossy sheen, with puddles in the low spots
//  - frost (0..1): a pale crust grows inward from the water's edge, in ragged pixel steps
//  - amount (0..1): snow, in clumps of art pixels, so it arrives patchily and melts back the same way
//
// World-anchored (#193): every position comes from the texture coordinate over the ground canvas
// (`groundSize`), never from the vertex position. LÖVE transforms streamed vertices on the CPU, so
// vertex_position is already in screen space and a pattern built on it sticks to the lens while the
// land pans and zooms.

uniform float amount;        // 0..1 how much of the ground is covered by snow
uniform vec3 snowColor;
uniform vec3 shadeColor;     // tint for the snow clump edges / low spots
uniform float clumpScale;    // noise frequency of the clumps in 1/ground pixels (higher = smaller patches)
uniform float patchScale;    // noise frequency of the broad drifts in 1/ground pixels

uniform float wet;           // 0..1 how soaked the ground is
uniform float wetDarken;     // brightness left on fully wet ground (1 = no change)
uniform float wetSaturation; // saturation on fully wet ground (above 1 = richer)
uniform float puddleCover;   // 0..1 share of the ground under a puddle when fully wet
uniform float puddleScale;   // puddle noise frequency in 1/ground pixels
uniform float puddleOpacity; // 0..1 how much of the sky shows in a puddle (the wet ground still shows through)
uniform vec3 puddleColor;    // the sky in the puddles
uniform vec3 puddleGlint;    // the bright pixel band along a puddle's top edge

uniform float frost;         // 0..1 how far the frost has crept
uniform float frostReach;    // art pixels the frost reaches in from the water's edge when fully grown
uniform vec3 frostColor;
uniform vec3 frostSnowColor;     // frost over snow: deeper than the snow so it shows
uniform float frostSparkle;      // 0..1 share of the frost pixels over snow that glint
uniform vec3 frostSparkleColor;

uniform vec2 groundSize;     // ground canvas size in pixels: one pixel per world art pixel

#ifdef PIXEL
#ifdef GL_ES
// World pixel coordinates run into the thousands: mediump would band the hash on phones.
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

// Art pixels from this one to the nearest transparent pixel (the creek bank), 1..4, else 9.
float bankDistance(Image t, vec2 uv, float limit) {
    vec2 texel = 1.0 / groundSize;
    for (int k = 1; k <= 4; k++) {
        if (float(k) > limit) {
            break;
        }
        float s = float(k);
        float open = 1.0;
        open = min(open, Texel(t, uv + vec2(s, 0.0) * texel).a);
        open = min(open, Texel(t, uv - vec2(s, 0.0) * texel).a);
        open = min(open, Texel(t, uv + vec2(0.0, s) * texel).a);
        open = min(open, Texel(t, uv - vec2(0.0, s) * texel).a);
        if (open < 0.5) {
            return s;
        }
    }
    return 9.0;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec4 base = Texel(tex, uv);
    if (base.a <= 0.0 || (amount <= 0.0 && wet <= 0.0 && frost <= 0.0)) {
        return base * color;
    }
    // World art pixel under this fragment: every sample below is a function of the land and
    // never of the screen, so the effects pan and zoom with the ground.
    vec2 px = floor(uv * groundSize) + 0.5;
    vec3 col = base.rgb;

    // Wet ground: darker, richer, with banded puddles that catch the sky.
    if (wet > 0.0) {
        float luma = dot(col, vec3(0.299, 0.587, 0.114));
        col = mix(vec3(luma), col, mix(1.0, wetSaturation, wet));
        col *= mix(1.0, wetDarken, wet);
        float depth = noise(px * puddleScale) * 0.7 + noise(px * puddleScale * 2.7 + 11.0) * 0.3;
        float edge = 1.0 - wet * puddleCover;            // puddles grow with the rain
        if (depth > edge) {
            float deep = floor((depth - edge) / (1.0 - edge) * 3.0) / 3.0;  // pixel-art bands
            col = mix(col, mix(puddleColor, puddleColor * 0.8, deep), puddleOpacity);
            // A bright pixel where the puddle's upper edge is (the pixel above is dry).
            float above = noise((px - vec2(0.0, 1.0)) * puddleScale) * 0.7
                + noise((px - vec2(0.0, 1.0)) * puddleScale * 2.7 + 11.0) * 0.3;
            col = mix(col, puddleGlint, step(above, edge) * 0.8);
        }
    }

    float covered = 0.0;
    // Snow: covered where the clump noise is below the amount; a thin shaded rim at the edge.
    if (amount > 0.0) {
        float patches = noise(px * patchScale);  // drifts several tiles wide, so the pattern reads as land
        float n = patches * 0.35 + noise(px * clumpScale) * 0.4 + hash(px) * 0.25;
        float threshold = amount * 1.1 - 0.05;
        covered = step(n, threshold);
        float rim = covered * step(threshold - 0.06, n);
        vec3 snow = mix(snowColor, shadeColor, rim);
        // Let some of the ground's own texture show through as faint shading.
        float luma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
        snow *= 0.92 + luma * 0.15;
        col = mix(col, snow, covered);
    }

    // Frost creeping inward from the bank over bare ground and snow alike, ragged so it reads as
    // crystals, not a stripe.
    if (frost > 0.0) {
        float reach = frostReach * frost;
        float d = bankDistance(tex, uv, ceil(reach));
        float ragged = 0.35 + 0.9 * hash(px);
        float crust = step(d, reach * ragged + 0.2);
        // Over snow the pale crust vanishes into white, so it turns a deeper ice blue with a few glints.
        vec3 crustColor = mix(frostColor, frostSnowColor, covered);
        float glint = covered * step(hash(px + 7.0), frostSparkle);
        crustColor = mix(crustColor, frostSparkleColor, glint);
        col = mix(col, crustColor, crust * 0.85);
    }
    return vec4(col, base.a) * color;
}
#endif
