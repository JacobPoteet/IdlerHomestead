// Screen-wide colour grade applied to the rendered world (not the HUD).
//  - time-of-day tint and light level (from tuning.visuals.lightKeys)
//  - saturation
//  - vignette
//  - film grain on the art-pixel grid, updated at a low frame rate for a hand-made feel

uniform vec3 tint;
uniform float light;
uniform float saturation;
uniform float vignette;
uniform float grain;
uniform float time;
uniform float pixelSize;     // screen pixels per art pixel, so grain matches the pixel art

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

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec3 c = Texel(tex, uv).rgb;

    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(vec3(luma), c, saturation);

    c *= tint * light;

    vec2 d = uv - 0.5;
    c *= 1.0 - vignette * smoothstep(0.15, 0.6, dot(d, d) * 2.0);

    vec2 cell = floor(screen / pixelSize);
    float g = hash(cell + floor(time * 12.0) * 13.7) - 0.5;
    c += g * grain;

    return vec4(c, 1.0) * color;
}
#endif
