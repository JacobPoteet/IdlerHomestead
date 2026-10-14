// Wind sway for crops, brush and tree canopies. Drawn in place of the plain sprite.
// The sprite is drawn on a quad padded a few pixels each side (so the leaning tip is not clipped by its
// cell); each row is shifted sideways by a WHOLE number of art pixels, growing toward the tip, so the
// sway steps like pixel art and never blurs. Pixels sampled outside the sprite's own atlas cell are
// transparent, so a neighbouring sprite never bleeds in.
// The vertex colour carries per-plant data (no per-sprite uniform): r = sway phase 0..1 (neighbours
// differ a little, so a gust rolls across the field), g = 1 when the crop is thirsty (tinted).

uniform float swayTime;      // radians; accumulated from the eased wind so a gust never jumps the pose
uniform float amplitude;     // art pixels the tip leans at weight 1 (already scaled by the wind strength)
uniform float lean;          // 0..1 steady downwind share of the sway
uniform float gust;          // 0..1 slower swell on top
uniform vec3 thirsty;        // colour multiplier for a thirsty crop
uniform vec3 wetTint;        // colour multiplier for plants standing on wet land (1 = dry)
uniform vec4 bounds;         // this sprite's cell in the atlas, uv: left, top, right, bottom
uniform vec2 texel;          // 1 / atlas size
uniform float spriteH;       // sprite height, art pixels
uniform float weight;        // this kind's multiplier on the amplitude
uniform float root;          // 0..1 share of the height (from the bottom) that stays still

#ifdef PIXEL
#ifdef GL_ES
// swayTime grows without bound between wraps: mediump would lose the phase on phones.
precision highp float;
#endif
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    float fromBottom = (bounds.w - uv.y) / texel.y / spriteH;           // 0 at the foot, 1 at the tip
    float h = clamp((fromBottom - root) / (1.0 - root), 0.0, 1.0);
    float phase = color.r * 6.2831853;
    float wave = sin(swayTime + phase) * (1.0 - lean) + lean + gust * sin(swayTime * 0.37 + phase * 0.5);
    float shift = floor(amplitude * weight * h * h * wave + 0.5);       // whole art pixels
    vec2 q = uv - vec2(shift * texel.x, 0.0);
    if (q.x < bounds.x || q.x >= bounds.z || q.y < bounds.y || q.y >= bounds.w) {
        return vec4(0.0);
    }
    vec4 base = Texel(tex, q);
    return vec4(base.rgb * wetTint * mix(vec3(1.0), thirsty, color.g), base.a);
}
#endif
