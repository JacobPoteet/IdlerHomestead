// Cast shadow silhouette: the sprite's opaque pixels as flat white, so the shadow mask is a solid
// shape and overlapping shadows never darken twice. Colour and strength come from compositing the
// mask afterwards (world_renderer.lua drawShadows).

#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    return vec4(1.0, 1.0, 1.0, step(0.5, Texel(tex, uv).a));
}
#endif
