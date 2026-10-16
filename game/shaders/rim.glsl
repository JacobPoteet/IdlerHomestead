// Rim light (#283): a warm line of light along the sun side of a sprite, on the golden afternoons of
// autumn. Drawn in place of the plain sprite (objects, the homesteader, the cat, hens and goats; crops and
// canopies get the same rim inside sway.glsl). A pixel is rim when its neighbour toward the sun is empty,
// or is the sprite's dark outline with empty beyond it: the light then sits on the first pixel inside the
// outline, as a pixel artist would paint it, and the outline stays dark. The top edge always catches some
// (the sun is up-screen, the way the shadows fall); the sunward side catches more as the sun gets low.
// The atlas has a transparent pixel between sprites, so a neighbour never belongs to another sprite.
// Sun lighting: every season a fainter light catches the sun side too, and the side away from the light
// (and the bottom edge) takes a cool form shade, one or two pixels deep inside the outline, so a sprite
// reads as a solid lit by the same sun that casts its shadow.

uniform vec2 texel;          // 1 / atlas size
uniform float rimStrength;   // 0..1 brightness added on a rim pixel (0 = off)
uniform vec3 rimColor;
uniform float rimSide;       // -1 or 1: the atlas x direction toward the sun (flipped for a mirrored sprite)
uniform float rimSideWeight; // 0..1 how much of the rim the sunward side gets
uniform float rimTop;        // 0..1 how much of the rim the top edge gets
uniform float inkLuma;       // brightness below which an opaque pixel counts as outline
uniform float shadeStrength; // 0..1 how far a pixel on the side away from the light goes toward shadeColor (0 = off)
uniform vec3 shadeColor;     // colour multiplier for that form shade (cool)
uniform float shadeSideWeight; // 0..1 how much shade the side away from the sun gets
uniform float shadeBottom;   // 0..1 how much shade the bottom edge gets (the sun is up-screen)

#ifdef PIXEL
float isInk(vec4 t) {
    return (t.a > 0.5 && dot(t.rgb, vec3(0.299, 0.587, 0.114)) < inkLuma) ? 1.0 : 0.0;
}

// 1 when the pixel at uv (opaque, colour `base`) catches light coming from direction `d`.
float lit(Image tex, vec2 uv, vec2 d, vec4 base) {
    if (isInk(base) > 0.5) {
        return 0.0;
    }
    vec4 n1 = Texel(tex, uv + d);
    if (n1.a < 0.5) {
        return 1.0;
    }
    if (isInk(n1) > 0.5 && Texel(tex, uv + 2.0 * d).a < 0.5) {
        return 1.0;
    }
    return 0.0;
}

// 1 when the pixel is on the edge facing direction `d`, 0.5 one pixel further in, else 0.
float edgeDepth(Image tex, vec2 uv, vec2 d, vec4 base) {
    if (isInk(base) > 0.5) {
        return 0.0;
    }
    if (lit(tex, uv, d, base) > 0.5) {
        return 1.0;
    }
    vec4 n1 = Texel(tex, uv + d);
    return (isInk(n1) < 0.5 && lit(tex, uv + d, d, n1) > 0.5) ? 0.5 : 0.0;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec4 base = Texel(tex, uv);
    if (base.a < 0.5 || (rimStrength <= 0.0 && shadeStrength <= 0.0)) {
        return base * color;
    }
    vec3 c = base.rgb;
    if (shadeStrength > 0.0) {
        float s = max(edgeDepth(tex, uv, vec2(0.0, texel.y), base) * shadeBottom, edgeDepth(tex, uv, vec2(-rimSide * texel.x, 0.0), base) * shadeSideWeight);
        c *= mix(vec3(1.0), shadeColor, s * shadeStrength);
    }
    float r = max(lit(tex, uv, vec2(0.0, -texel.y), base) * rimTop, lit(tex, uv, vec2(rimSide * texel.x, 0.0), base) * rimSideWeight);
    return vec4(c + rimColor * (r * rimStrength), base.a) * color;
}
#endif
