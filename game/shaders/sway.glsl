// Wind sway for crops, brush and tree canopies. Drawn in place of the plain sprite.
// The sprite is drawn on a quad padded a few pixels each side (so the leaning tip is not clipped by its
// cell); each row is shifted sideways by a WHOLE number of art pixels, growing toward the tip, so the
// sway steps like pixel art and never blurs. Pixels sampled outside the sprite's own atlas cell are
// transparent, so a neighbouring sprite never bleeds in.
// The vertex colour carries per-plant data (no per-sprite uniform): r = sway phase 0..1 (neighbours
// differ a little, so a gust rolls across the field), g = 1 when the crop is thirsty (tinted).
// In autumn the sprite also gets the warm rim light of rim.glsl, worked out on the swayed picture so the
// rim follows the leaning leaves, and the same sun lighting (a faint lit side, a cool form shade away from
// the light) every season.

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
uniform float rimStrength;   // 0..1 brightness added on a rim pixel (0 = off), as rim.glsl
uniform vec3 rimColor;
uniform float rimSide;       // -1 or 1: the atlas x direction toward the sun
uniform float rimSideWeight; // 0..1 how much of the rim the sunward side gets
uniform float rimTop;        // 0..1 how much of the rim the top edge gets
uniform float inkLuma;       // brightness below which an opaque pixel counts as outline
uniform float shadeStrength; // 0..1 how far a pixel on the side away from the light goes toward shadeColor (0 = off)
uniform vec3 shadeColor;     // colour multiplier for that form shade (cool)
uniform float shadeSideWeight; // 0..1 how much shade the side away from the sun gets
uniform float shadeBottom;   // 0..1 how much shade the bottom edge gets (the sun is up-screen)

#ifdef PIXEL
#ifdef GL_ES
// swayTime grows without bound between wraps: mediump would lose the phase on phones.
precision highp float;
#endif
// The sprite's texel that lands on `uv` after the sway (transparent outside its own atlas cell).
vec4 swayed(Image tex, vec2 uv, float phase) {
    float fromBottom = (bounds.w - uv.y) / texel.y / spriteH;           // 0 at the foot, 1 at the tip
    float h = clamp((fromBottom - root) / (1.0 - root), 0.0, 1.0);
    float wave = sin(swayTime + phase) * (1.0 - lean) + lean + gust * sin(swayTime * 0.37 + phase * 0.5);
    float shift = floor(amplitude * weight * h * h * wave + 0.5);       // whole art pixels
    vec2 q = uv - vec2(shift * texel.x, 0.0);
    if (q.x < bounds.x || q.x >= bounds.z || q.y < bounds.y || q.y >= bounds.w) {
        return vec4(0.0);
    }
    return Texel(tex, q);
}

float isInk(vec4 t) {
    return (t.a > 0.5 && dot(t.rgb, vec3(0.299, 0.587, 0.114)) < inkLuma) ? 1.0 : 0.0;
}

// 1 when the swayed pixel at uv (colour `base`) catches light from direction `d` (see rim.glsl).
float lit(Image tex, vec2 uv, vec2 d, vec4 base, float phase) {
    if (isInk(base) > 0.5) {
        return 0.0;
    }
    vec4 n1 = swayed(tex, uv + d, phase);
    if (n1.a < 0.5) {
        return 1.0;
    }
    if (isInk(n1) > 0.5 && swayed(tex, uv + 2.0 * d, phase).a < 0.5) {
        return 1.0;
    }
    return 0.0;
}

// 1 when the swayed pixel is on the edge facing direction `d`, 0.5 one pixel further in, else 0 (see rim.glsl).
float edgeDepth(Image tex, vec2 uv, vec2 d, vec4 base, float phase) {
    if (isInk(base) > 0.5) {
        return 0.0;
    }
    if (lit(tex, uv, d, base, phase) > 0.5) {
        return 1.0;
    }
    vec4 n1 = swayed(tex, uv + d, phase);
    return (isInk(n1) < 0.5 && lit(tex, uv + d, d, n1, phase) > 0.5) ? 0.5 : 0.0;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    float phase = color.r * 6.2831853;
    vec4 base = swayed(tex, uv, phase);
    vec3 c = base.rgb;
    if (shadeStrength > 0.0 && base.a >= 0.5) {
        float s = max(edgeDepth(tex, uv, vec2(0.0, texel.y), base, phase) * shadeBottom, edgeDepth(tex, uv, vec2(-rimSide * texel.x, 0.0), base, phase) * shadeSideWeight);
        c *= mix(vec3(1.0), shadeColor, s * shadeStrength);
    }
    if (rimStrength > 0.0 && base.a >= 0.5) {
        float r = max(lit(tex, uv, vec2(0.0, -texel.y), base, phase) * rimTop, lit(tex, uv, vec2(rimSide * texel.x, 0.0), base, phase) * rimSideWeight);
        c += rimColor * (r * rimStrength);
    }
    return vec4(c * wetTint * mix(vec3(1.0), thirsty, color.g), base.a);
}
#endif
