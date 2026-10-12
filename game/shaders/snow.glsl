// Snow cover over the ground (grass and road), drawn with the static ground canvas.
// Coverage grows with `amount` (0 = bare, 1 = fully white) in clumps of art pixels, so snow
// arrives patchily and melts back the same way. A little sparkle and blue shading keep it pixel-art.

uniform float amount;        // 0..1 how much of the ground is covered
uniform vec3 snowColor;
uniform vec3 shadeColor;     // tint for the clump edges / low spots
uniform float clumpScale;    // noise frequency of the clumps (higher = smaller patches)

varying vec2 worldPos;

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    worldPos = vertex_position.xy;
    return transform_projection * vertex_position;
}
#endif

#ifdef PIXEL
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
    vec2 px = floor(worldPos) + 0.5;
    float n = noise(px * clumpScale) * 0.7 + hash(px) * 0.3;
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
