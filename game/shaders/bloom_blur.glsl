// Bloom, pass 2: a 9-tap separable gaussian (5 texture reads using linear filtering). `step` is the
// direction in texels: (1/w, 0) for the horizontal pass, (0, 1/h) for the vertical one.

uniform vec2 step;

#ifdef PIXEL
#ifdef GL_ES
precision highp float;
#endif
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec3 sum = Texel(tex, uv).rgb * 0.2270270270;
    sum += Texel(tex, uv + step * 1.3846153846).rgb * 0.3162162162;
    sum += Texel(tex, uv - step * 1.3846153846).rgb * 0.3162162162;
    sum += Texel(tex, uv + step * 3.2307692308).rgb * 0.0702702703;
    sum += Texel(tex, uv - step * 3.2307692308).rgb * 0.0702702703;
    return vec4(sum, 1.0);
}
#endif
