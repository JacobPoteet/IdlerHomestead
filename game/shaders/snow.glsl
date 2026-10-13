// Snow cover over the ground (grass and road), drawn with the static ground canvas.
// Coverage grows with `amount` (0 = bare, 1 = fully white) in clumps of art pixels, so snow
// arrives patchily and melts back the same way. A little sparkle and blue shading keep it pixel-art.

uniform float amount;        // 0..1 how much of the ground is covered
uniform vec3 snowColor;
uniform vec3 shadeColor;     // tint for the clump edges / low spots
uniform float clumpScale;    // noise frequency of the clumps in 1/ground pixels (higher = smaller patches)
uniform float patchScale;    // noise frequency of the broad drifts in 1/ground pixels

uniform vec2 groundSize;     // ground canvas size in pixels: one pixel per world art pixel
// The clump position comes from the texture coordinate (0..1 over the ground canvas), never from
// the vertex position: LÖVE transforms streamed vertices on the CPU, so vertex_position is already
// in screen space and a pattern built on it sticks to the lens while the land pans and zooms.

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

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec4 base = Texel(tex, uv);
    if (base.a <= 0.0 || amount <= 0.0) {
        return base * color;
    }
    // World art pixel under this fragment: every sample below is a function of the land and
    // never of the screen, so the snow pans and zooms with the ground (#193).
    vec2 px = floor(uv * groundSize) + 0.5;
    float patches = noise(px * patchScale);  // drifts several tiles wide, so the pattern reads as land
    float n = patches * 0.35 + noise(px * clumpScale) * 0.4 + hash(px) * 0.25;
    // Covered where the clump noise is below the amount; a thin shaded rim at the edge.
    float threshold = amount * 1.1 - 0.05;
    float covered = step(n, threshold);
    float rim = covered * step(threshold - 0.06, n);
    vec3 snow = mix(snowColor, shadeColor, rim);
    // Let some of the ground's own texture show through as faint shading.
    float luma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
    snow *= 0.92 + luma * 0.15;
    return vec4(mix(base.rgb, snow, covered), base.a) * color;
}
#endif
