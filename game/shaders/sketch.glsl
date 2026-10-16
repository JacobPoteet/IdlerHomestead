// A sprite drawn as a pencil sketch (GDD §9.4, D142; src/render/sketch.lua), for things planned but not
// real yet: a planned crop, a building being placed or queued. The silhouette's edge becomes a pencil
// line, the art's own dark outline a second stroke, the inside a light diagonal hatch over a faint wash,
// all with a little grain. The vertex colour is the ink.

uniform vec2 texel;   // 1 / atlas size
uniform vec4 bounds;  // this sprite's cell in the atlas, uv: left, top, right, bottom
uniform float hatch;  // 0..1 opacity of the inside hatch
uniform float wash;   // 0..1 opacity of the flat wash under the hatch

#ifdef PIXEL
#ifdef GL_ES
precision highp float;
#endif
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float alphaAt(Image tex, vec2 q) {
    if (q.x < bounds.x || q.y < bounds.y || q.x > bounds.z || q.y > bounds.w) {
        return 0.0;
    }
    return Texel(tex, q).a;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec4 base = Texel(tex, uv);
    if (base.a < 0.5) {
        return vec4(0.0);
    }
    vec2 px = floor(uv / texel);
    float edge = 0.0;
    if (alphaAt(tex, uv + vec2(texel.x, 0.0)) < 0.5) edge = 1.0;
    if (alphaAt(tex, uv - vec2(texel.x, 0.0)) < 0.5) edge = 1.0;
    if (alphaAt(tex, uv + vec2(0.0, texel.y)) < 0.5) edge = 1.0;
    if (alphaAt(tex, uv - vec2(0.0, texel.y)) < 0.5) edge = 1.0;
    float grain = hash(px);
    if (edge > 0.5) {
        // The pencil line: mostly solid, a few pixels lighter where the lead skipped.
        return vec4(color.rgb, color.a * (grain < 0.12 ? 0.45 : 0.95));
    }
    // The dark outline drawn into the art reads as a second pencil stroke.
    float luma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
    if (luma < 0.18) {
        return vec4(color.rgb, color.a * 0.7);
    }
    float line = mod(px.x + px.y, 3.0) < 0.5 ? 1.0 : 0.0;
    float a = max(wash, line * hatch * (grain < 0.2 ? 0.5 : 1.0));
    return vec4(color.rgb, color.a * a);
}
#endif
