// Cast shadow silhouette: the sprite's opaque pixels in the vertex colour, so the shadow mask is a solid
// shape and overlapping shadows never darken twice. The mask has one texel per world art pixel, so the
// sheared silhouette steps on the art grid like the sprites do. The renderer writes the channels it
// needs (red: cast shadow, blue: a tree canopy's shadow, where leaf dapple shows) with a colour mask.
// Colour and strength come from compositing the mask afterwards (shadow_composite.glsl).

#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    return vec4(color.rgb, step(0.5, Texel(tex, uv).a));
}
#endif
