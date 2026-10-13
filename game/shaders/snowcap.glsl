// Snow resting on the tops of objects (roofs, fences, barrels), drawn in place of the sprite while
// the ground is snowy. The cap is found from the sprite itself: a pixel is "top" when a transparent
// pixel (or the edge of its atlas cell) lies within `capDepth` pixels straight above it. Coverage
// follows the ground's snow `amount`, ragged by a per-pixel hash, so it builds and melts with it.

uniform float amount;        // 0..1 snow on the ground (same value as ground.glsl)
uniform float capDepth;      // art pixels of cap at full snow (1..4)
uniform vec3 snowColor;
uniform vec3 shadeColor;     // the cap's lowest row
uniform vec2 texel;          // 1 / atlas size
uniform vec4 bounds;         // this sprite's cell in the atlas, uv: left, top, right, bottom

#ifdef PIXEL
#ifdef GL_ES
precision highp float;
#endif
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec4 base = Texel(tex, uv);
    if (base.a <= 0.0 || amount <= 0.0) {
        return base * color;
    }
    // Distance up to the silhouette: 1 = the top row of the sprite.
    float d = 9.0;
    for (int k = 1; k <= 4; k++) {
        if (float(k) > capDepth) {
            break;
        }
        vec2 q = uv - vec2(0.0, float(k)) * texel;
        float a = q.y < bounds.y ? 0.0 : Texel(tex, q).a;
        if (a < 0.5) {
            d = float(k);
            break;
        }
    }
    if (d > capDepth) {
        return base * color;
    }
    vec2 px = floor(uv / texel);
    // The top row fills first, deeper rows only as the snow gets thick.
    float chance = clamp(amount * 1.25 - (d - 1.0) * 0.3, 0.0, 1.0);
    if (hash(px) >= chance) {
        return base * color;
    }
    vec3 snow = mix(snowColor, shadeColor, step(1.5, d));
    return vec4(snow, base.a) * color;
}
#endif
