@block vertexUniforms
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
@end

@block modelUniforms
layout(binding=2) uniform modelParams {
    mat4 model;
    mat4 normalModel;
};
@end

@block materialUniforms
layout(binding=3) uniform toonParams {
    vec4 toon;
};
@end

@block spriteUniforms
layout(binding=2) uniform spriteParams {
    vec4 grassColor;
    vec4 toon;
};
@end

@block lightUniforms
layout(binding=1) uniform lightParams {
    vec4 ambient;
    vec4 dirLight;
    vec4 dirColor;
    vec4 pointLight[4];
    vec4 pointColor[4];
};
@end

// The toon point light of the Lit and Billboard programs; `toon` is their material block's.
@block lightFunctions
vec3 pointLightAt(int i, vec3 position, vec3 normal, float normalWeight) {
    vec3 toLight = pointLight[i].xyz - position;
    float distance = length(toLight);
    float falloff = clamp(1.0 - distance / pointColor[i].a, 0.0, 1.0);
    float facing = mix(1.0, max(dot(normal, toLight / max(distance, 0.0001)), 0.0), normalWeight);
    float energy = falloff * falloff * facing * pointLight[i].w;
    float level = floor(energy * toon.x + 0.35) / toon.x;
    return pointColor[i].rgb * level;
}

// A wall by the fire: lit by the distance across the ground and the horizontal part of its
// normal, so a face turned to the fire is one colour top to bottom instead of rings around the
// point nearest the light (t3ssel8r's firelit pillars).
vec3 pointLightFlat(int i, vec3 position, vec3 normal) {
    vec2 toLight = pointLight[i].xz - position.xz;
    float distance = length(toLight);
    float falloff = clamp(1.0 - distance / pointColor[i].a, 0.0, 1.0);
    float facing = max(dot(normal.xz, toLight / max(distance, 0.0001)), 0.0);
    float energy = falloff * falloff * facing * pointLight[i].w;
    float level = floor(energy * toon.x + 0.35) / toon.x;
    return pointColor[i].rgb * level;
}
@end

@vs litVs
@include_block vertexUniforms
@include_block modelUniforms
in vec3 position;
in vec3 normal;
in vec4 color;
out vec3 worldPosition;
out vec3 worldNormal;
out vec4 baseColor;
out float depth01;
void main() {
    vec4 world = model * vec4(position, 1.0);
    worldPosition = world.xyz;
    worldNormal = mat3(normalModel) * normal;
    baseColor = color;
    gl_Position = viewProj * world;
    depth01 = gl_Position.z;
}
@end

@fs litFs
@include_block materialUniforms
@include_block lightUniforms
@include_block lightFunctions
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
// toon = (levels, flat walls, wrap, unused). Flat walls (> 0.5): faces steeper than ~37 deg
// take the point lights by ground distance (pointLightFlat). Wrap: the share of a point light
// a surface takes whatever its normal - a lawn is a mat of blades facing every way, not a
// surface. Both 0 is the plain toon light.
void main() {
    vec3 n = normalize(worldNormal);
    float lambert = step(0.35, dot(n, dirLight.xyz)) * dirLight.w;
    vec3 shaded = baseColor.rgb * (ambient.rgb + dirColor.rgb * vec3(lambert));
    vec3 points = vec3(0.0);
    bool flatWall = toon.y > 0.5 && abs(n.y) < 0.8;
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        points += flatWall ? pointLightFlat(i, worldPosition, n) : pointLightAt(i, worldPosition, n, 1.0 - toon.z);
    }
    fragColor = vec4(shaded + points, baseColor.a);
    fragNormal = vec4(n * 0.5 + 0.5, depth01);
}
@end

@block wind
// Wind, when cameraRight.w (the sway at a sprite's top, world units) is above 0; cameraUp.w is
// the time in seconds. Two waves travel across the ground and multiply into gusts; each sprite
// steps its own copy of the time at WIND_FPS, phase-shifted by a hash of its root, so the lawn
// moves in held poses like hand-animated pixel art rather than sliding. The bend grows with the
// square of the height, the root never moves. Emissive sprites (the flame) do not sway.
const float WIND_FPS = 8.0;
float windSway(vec3 root, float top) {
    float phase = fract(sin(dot(root.xz, vec2(12.9898, 78.233))) * 43758.5453);
    float t = floor(cameraUp.w * WIND_FPS + phase) / WIND_FPS;
    float a = sin(dot(root.xz, vec2(0.61, 0.35)) * 0.9 - t * 1.7);
    float b = sin(dot(root.xz, vec2(-0.28, 0.72)) * 0.37 - t * 0.63 + 1.3);
    float gust = clamp(a * b * 1.6 + 0.3, 0.0, 1.0);
    float idle = 0.2 * sin(t * 4.4 + phase * 6.2832);
    return (gust + idle) * cameraRight.w * top * top;
}
@end

@vs billboardVs
@include_block vertexUniforms
@include_block wind
in vec2 corner;
in vec4 root;
in vec4 shape;
out vec2 uv;
out vec3 rootPosition;
out float tint;
out float emissive;
out float depth01;

void main() {
    float sway = 0.0;
    if (cameraRight.w > 0.0 && shape.w < 0.5) {
        sway = windSway(root.xyz, corner.y);
    }
    vec3 p = root.xyz + cameraRight.xyz * (corner.x * shape.x + sway) + cameraUp.xyz * (corner.y * shape.y);
    gl_Position = viewProj * vec4(p, 1.0);
    depth01 = gl_Position.z;
    uv = vec2((corner.x + 0.5 + root.w) * 0.25, 1.0 - corner.y);
    rootPosition = root.xyz;
    tint = shape.z;
    emissive = shape.w;
}
@end

@fs billboardFs
@include_block spriteUniforms
@include_block lightUniforms
@include_block lightFunctions
layout(binding=0) uniform texture2D spriteTexture;
layout(binding=0) uniform sampler spriteSampler;
in vec2 uv;
in vec3 rootPosition;
in float tint;
in float emissive;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
void main() {
    vec4 texel = texture(sampler2D(spriteTexture, spriteSampler), uv);
    if (texel.a < 0.5) {
        discard;
    }
    // toon = (levels, normal weight, at root, unused): with both 0 a sprite takes the light a
    // quarter unit above its root from every side. A normal weight lights it as a surface facing
    // up, and "at root" (> 0.5) samples the root itself - together they match a lawn lit with
    // the lit program's wrap, so a clump is the colour of the ground it stands on.
    vec3 points = vec3(0.0);
    float lift = toon.z > 0.5 ? 0.0 : 0.25;
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        points += pointLightAt(i, rootPosition + vec3(0.0, lift, 0.0), vec3(0.0, 1.0, 0.0), toon.y);
    }
    vec3 grass = grassColor.rgb * texel.r * tint + points;
    fragColor = vec4(mix(grass, texel.rgb, emissive), 0.0);
    fragNormal = vec4(0.5, 1.0, 0.5, depth01);
}
@end

@vs fullscreenVs
in vec2 position;
void main() {
    gl_Position = vec4(position, 0.5, 1.0);
}
@end

@block noiseFunctions
float hash21(vec2 cell, float salt) {
    return fract(sin(dot(cell, vec2(127.1, 311.7)) + salt * 74.7) * 43758.5453);
}

float valueNoise(vec2 p, float salt) {
    vec2 i = floor(p);
    vec2 f = p - i;
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i, salt);
    float b = hash21(i + vec2(1.0, 0.0), salt);
    float c = hash21(i + vec2(0.0, 1.0), salt);
    float d = hash21(i + vec2(1.0, 1.0), salt);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
@end

@fs postFs
// Outline from depth + normal edges, fog by depth, then palette quantization through a LUT:
// one pass, because the palette only needs this pixel's outlined color (docs/VOID3D.md, M3).
@image_sample_type depthTexture unfilterable_float
@sampler_type depthSampler nonfiltering
layout(binding=0) uniform texture2D colorTexture;
layout(binding=1) uniform texture2D normalTexture;
layout(binding=2) uniform texture2D depthTexture;
layout(binding=3) uniform texture2D paletteTexture;
layout(binding=0) uniform sampler pointSampler;
layout(binding=1) uniform sampler depthSampler;
layout(binding=0) uniform postParams {
    vec4 edge;
    vec4 fog;
    vec4 fogColor;
    vec4 features;
    vec4 depthUnpack;
    vec4 colorAdjust;
    vec4 glow;
    vec4 glowShape;
    vec4 glowColor;
    vec4 glowMist;
    vec4 glowVeil;
    vec4 glowFlat;
};
out vec4 fragColor;
@include_block noiseFunctions

vec4 fetchNormal(ivec2 p, ivec2 size) {
    return texelFetch(sampler2D(normalTexture, pointSampler), clamp(p, ivec2(0, 0), size - ivec2(1, 1)), 0);
}

// features.z picks the depth: the scene's depth attachment, unpacked to the depth the scene
// shaders write, or the 8-bit copy they pack into the normal target's alpha.
float depthAt(vec4 normal, ivec2 p, ivec2 size) {
    float depth = normal.w;
    if (features.z > 0.5) {
        ivec2 q = clamp(p, ivec2(0, 0), size - ivec2(1, 1));
        float stored = texelFetch(sampler2D(depthTexture, depthSampler), q, 0).r;
        depth = stored * depthUnpack.x + depthUnpack.y;
    }
    return depth;
}

// features.w levels per channel; the LUT is levels * levels wide, red + blue * levels across,
// green down (palette.ms).
vec3 paletteColor(vec3 rgb) {
    int levels = int(features.w);
    ivec3 q = ivec3(clamp(rgb, 0.0, 1.0) * float(levels - 1) + 0.5);
    ivec2 cell = ivec2(q.r + q.b * levels, q.g);
    return texelFetch(sampler2D(paletteTexture, pointSampler), cell, 0).rgb;
}

// A point light seen through thin fog (glow.w > 0): the light the fog scatters toward the camera
// along this pixel's ray, from the ray's start to the surface it hits. Orthographic rays are
// parallel, so the ray passes the light at `across` (texels from the light's own, times metres
// per texel) and the surface sits `t1` metres past it; the in-scatter of a 1/r^2 light softened by
// glowShape.z is then (atan(t1 / D) + pi/2) / D, scaled to 1 at the light. A surface in front of
// the light (t1 < 0) takes less of it than the ground behind, which is what puts the glow in
// the air. Faded to 0 from half glowColor.w to glowColor.w metres; banded into glowShape.w steps.
//   glow       light's texel x, y (the target's row order), its depth (0..1), strength
//   glowShape  metres per texel, metres per unit of depth, softening (m), bands (0: smooth)
//   glowColor  colour, reach (m)
//   glowMist   the fog's patches: noise cell (m), how much they thin and thicken it (0..1), the
//              drift so far (m, across and up the screen)
//   glowVeil   the mist over the whole frame: colour, amount (0: none), thinned and thickened by
//              the same patches and rounded to thirds of the amount
//   glowFlat   the night seen through the fog: colours darker than ~0.13 luma pulled toward
//              this colour by w (0: none), so the unlit ground keeps its shape but loses contrast
vec3 nightFlat(vec3 rgb) {
    if (glowFlat.w <= 0.0) {
        return rgb;
    }
    float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    // only the moonlit night steps: the firelight's faint outer bands keep their reach
    float dark = 1.0 - smoothstep(0.10, 0.16, luma);
    return mix(rgb, mix(rgb, glowFlat.rgb, glowFlat.w), dark);
}

float mistNoise(ivec2 p) {
    if (glowMist.x <= 0.0) {
        return 0.5;
    }
    vec2 across = (vec2(p) + 0.5 - glow.xy) * glowShape.x;
    vec2 q = (across + glowMist.zw) / glowMist.x;
    return valueNoise(q, 41.0) * 0.6 + valueNoise(q * 2.3, 42.0) * 0.4;
}

vec3 mistVeil(vec3 rgb, float n) {
    if (glowVeil.w <= 0.0) {
        return rgb;
    }
    float step = glowVeil.w / 3.0;
    float v = glowVeil.w * max(1.0 + glowMist.y * (n * 2.0 - 1.0), 0.0);
    return mix(rgb, glowVeil.rgb, floor(v / step + 0.5) * step);
}

float fireGlow(ivec2 p, float depth, float n) {
    if (glow.w <= 0.0) {
        return 0.0;
    }
    vec2 across = (vec2(p) + 0.5 - glow.xy) * glowShape.x;
    float d = length(across);
    float soft = glowShape.z;
    float reach = sqrt(d * d + soft * soft);
    float t1 = (depth - glow.z) * glowShape.y;
    float s = (atan(t1 / reach) + 1.5707963) / reach * soft * 0.31830989;
    s *= 1.0 - smoothstep(glowColor.w * 0.5, glowColor.w, d);
    s *= 1.0 + glowMist.y * (n * 2.0 - 1.0);
    if (glowShape.w > 0.0) {
        s = floor(s * glowShape.w) / glowShape.w;
    }
    return s * glow.w;
}

void main() {
    ivec2 size = textureSize(sampler2D(colorTexture, pointSampler), 0);
    ivec2 p = ivec2(gl_FragCoord.xy);
    vec4 color = texelFetch(sampler2D(colorTexture, pointSampler), p, 0);
    vec4 center = fetchNormal(p, size);
    float centerDepth = depthAt(center, p, size);
    vec3 rgb = color.rgb;
    if (features.x > 0.5) {
        vec3 n = center.xyz * 2.0 - 1.0;
        float depthEdge = 0.0;
        float normalEdge = 0.0;
        ivec2 offsets[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
        for (int i = 0; i < 4; i++) {
            vec4 neighbor = fetchNormal(p + offsets[i], size);
            float depthDelta = depthAt(neighbor, p + offsets[i], size) - centerDepth;
            if (depthDelta > edge.x) {
                depthEdge = 1.0;
            }
            vec3 nq = neighbor.xyz * 2.0 - 1.0;
            if (abs(depthDelta) < edge.x && dot(n, nq) < edge.y && n.y > nq.y + 0.1) {
                normalEdge = 1.0;
            }
        }
        rgb = mix(rgb, rgb * edge.z, depthEdge * color.a);
        rgb = mix(rgb, rgb * edge.w + vec3(0.02), normalEdge * color.a * (1.0 - depthEdge));
    }
    float haze = smoothstep(fog.x, fog.y, centerDepth) * fog.z;
    rgb = mix(rgb, fogColor.rgb, haze);
    float mist = mistNoise(p);
    rgb = nightFlat(rgb);
    rgb = mistVeil(rgb, mist);
    rgb += glowColor.rgb * fireGlow(p, centerDepth, mist);
    if (colorAdjust.x != 0.0) {
        float luma = dot(rgb, vec3(0.212671, 0.71516, 0.072169));
        float keep = colorAdjust.x + 1.0;
        rgb = rgb * keep + vec3(luma * (1.0 - keep));
    }
    if (features.y > 0.5) {
        rgb = paletteColor(rgb);
    }
    fragColor = vec4(rgb, 1.0);
}
@end

@fs blitFs
layout(binding=0) uniform texture2D sceneTexture;
layout(binding=0) uniform sampler pointSampler;
layout(binding=0) uniform blitParams {
    vec4 pixel;
};
out vec4 fragColor;
// pixel = (scale, scale, offset x, offset y) in framebuffer pixels (blit.ms). Alpha is 1 so
// that blitting the scene color directly (no post stage) never shows through the surface.
void main() {
    ivec2 size = textureSize(sampler2D(sceneTexture, pointSampler), 0);
    ivec2 p = ivec2(floor((gl_FragCoord.xy + pixel.zw) / pixel.x));
    vec4 texel = texelFetch(sampler2D(sceneTexture, pointSampler), clamp(p, ivec2(0, 0), size - ivec2(1, 1)), 0);
    fragColor = vec4(texel.rgb, 1.0);
}
@end

@vs particleVs
@include_block vertexUniforms
in vec2 corner;
in vec4 root;
in vec4 color;
out vec4 particleColor;
out float depth01;
void main() {
    vec3 p = root.xyz + cameraRight.xyz * (corner.x * root.w) + cameraUp.xyz * (corner.y * root.w);
    gl_Position = viewProj * vec4(p, 1.0);
    depth01 = gl_Position.z;
    particleColor = color;
}
@end

@fs particleFs
// PENDING3D: particle-alpha-tested
in vec4 particleColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
void main() {
    if (particleColor.a < 0.5) {
        discard;
    }
    fragColor = vec4(particleColor.rgb, 0.0);
    fragNormal = vec4(0.5, 1.0, 0.5, depth01);
}
@end

// ---- Ramp programs ----
// LitRamp and BillboardRamp colour by lookup instead of by light: the light at a point is cut into
// a band index, and the colour is that index on the material's row of a ramp texture (one row per
// material, dark to light: the night steps, then one colour per fire band). A hand-picked ramp
// per material is how a pixel artist shades - the fire turns grass purple, then rose, then orange,
// which adding an orange light onto a blue base never gives. It is the grass lab's shade()
// (t3ssel8r-lab scripts/grass_lab.py) on the GPU. Both read the light block as Lit does.
//
// The five ramp vectors, LitRamp's material block (binding=3); BillboardRamp carries the same five
// at the head of its vertex block and hands them to its fragment stage.
//   rampRow       row, top row + 1 (0: none), level offset, then LitRamp: a vertex red above
//                 this is one step up (0: off) / BillboardRamp: light jitter
//   rampBands     night steps, fire bands, first band, band step
//   rampLight     falloff power, flat walls (1: steep faces, 2: every face), wrap, then
//                 BillboardRamp: a sprite's own steps up show only in firelight (> 0.5)
//   rampMoon      moon band cuts on n.l (two), then LitRamp: walls take the fire at their
//                 object's origin (> 0.5: one colour per face), unused
//   rampVignette  radii (1 = frame corner) that take one step each (three), on
@block rampUniforms
layout(binding=3) uniform rampParams {
    vec4 rampRow;
    vec4 rampBands;
    vec4 rampLight;
    vec4 rampMoon;
    vec4 rampVignette;
    vec4 rampFar;
    vec4 rampPatch;
    vec4 rampWalker;
};
@end

// Needs rampRow .. rampVignette and rampFar in scope (uniforms or globals), the light block, and
// shadowTexture + shadowSampler: the fire's shadows, seen from above (rampMoon.w > 0: the map is a
// square of that half-size in metres centred on the world origin, where the fire is; red is the
// share of the fire that reaches the ground there, 1 lit, 0 behind a pillar).
//   rampFar  x: the far tail's reach, times the light's radius (0: no tail); y: the tail's energy
//            at the fire (the tail is the video's dim magenta glow past the lit core, measured at
//            ~2.6x its radius); z: a wall's gain on the firelight (0: 1); w > 0.5: a sprite's own
//            steps count only in firelight, so in the dark it is the lawn's colour
//   rampMoon.z on a sprite, or above 1.5 on a lit surface that is not a wall: its fire bands
//            taken that many at a time (rampShade `merge`)
//   rampPatch  after Dylearn's grass (youtube OxsuWDtjuGw): x the colour patches' noise cell in
//            metres (0: none), sampled in world space so a clump and the ground under it agree;
//            below y a patch is a step down, above z a step up; w the hybrid toon gradient, the
//            share of a band over which one band blends into the next (0: hard cuts)
//   rampWalker  the walker as a standing cylinder: x, z its centre, z its radius (0: none), w the
//            world height of its top. It hides the fire from what lies behind it (the line from the
//            light passes through it below its top), and the ground within 1.15 radii of it is a
//            step darker (a contact shadow), so it stands on the grass instead of floating.
// Needs noiseFunctions in scope too.

@block rampFunctions

// The fire at a point: each point light's power, times its falloff to its radius raised to
// rampLight.x, times how the point faces it. A wall (flat) faces it across the ground only;
// anything else by n.l softened a quarter and wrapped by rampLight.z.
// rampLight.x < 0: the falloff as the eye takes it, linear in log distance: full within
// -rampLight.x metres of the light, nothing at `radius` (a fire's light drops as 1/r^2 and the
// eye reads brightness about logarithmically: a small bright pool, a quick fall, a long faint tail).
float fallShape(float distance, float radius) {
    if (rampLight.x < 0.0) {
        float full = -rampLight.x;
        return clamp(1.0 - log(max(distance, full) / full) / log(max(radius / full, 1.0001)), 0.0, 1.0);
    }
    return pow(clamp(1.0 - distance / radius, 0.0, 1.0), rampLight.x);
}

float rampFall(float distance, float radius) {
    float core = fallShape(distance, radius);
    if (rampFar.x <= 0.0) {
        return core;
    }
    float tail = rampFar.y * fallShape(distance, radius * rampFar.x);
    return max(core, tail);
}

float fireReach(vec3 position) {
    if (rampMoon.w <= 0.0) {
        return 1.0;
    }
    vec2 uv = position.xz / (2.0 * rampMoon.w) + 0.5;
    return texture(sampler2D(shadowTexture, shadowSampler), uv).r;
}

float walkerBlocks(vec3 position, vec3 light) {
    if (rampWalker.z <= 0.0) {
        return 0.0;
    }
    vec2 from = light.xz;
    vec2 seg = position.xz - from;
    float len2 = max(dot(seg, seg), 0.000001);
    float t = clamp(dot(rampWalker.xy - from, seg) / len2, 0.0, 1.0);
    float miss = length(from + seg * t - rampWalker.xy);
    float behind = step(0.02, t) * step(t, 0.98) * step(rampWalker.z * 1.05, length(position.xz - rampWalker.xy));
    float height = light.y + (position.y - light.y) * t;
    return behind * step(height, rampWalker.w) * (1.0 - smoothstep(rampWalker.z * 0.85, rampWalker.z * 1.1, miss));
}

float walkerContact(vec2 xz) {
    return (rampWalker.z > 0.0 && length(xz - rampWalker.xy) < rampWalker.z * 1.15) ? 1.0 : 0.0;
}

float rampFire(vec3 position, vec3 normal, bool wall) {
    float energy = 0.0;
    float reach = fireReach(position) * (1.0 - walkerBlocks(position, pointLight[0].xyz));
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        vec3 toLight = pointLight[i].xyz - position;
        if (wall) {
            // rampLight.w > 0: walls take the fire at that fixed radius, so a flickering reach
            // does not make whole faces jump a band (the lit ramp's spare lane; sprites have
            // no walls).
            float across = length(toLight.xz);
            float fall = rampFall(across, rampLight.w > 0.0 ? rampLight.w : pointColor[i].a);
            float gain = rampFar.z > 0.0 ? rampFar.z : 1.0;
            energy += gain * pointLight[i].w * fall * max(dot(normal.xz, toLight.xz / max(across, 0.0001)), 0.0);
        } else {
            float distance = length(toLight);
            float fall = rampFall(distance, pointColor[i].a);
            float facing = clamp((dot(normal, toLight / max(distance, 0.0001)) + 0.25) / 1.25, 0.0, 1.0);
            energy += pointLight[i].w * fall * mix(facing, 1.0, rampLight.z);
        }
    }
    return energy * reach;
}

// The ramp index: the fire's band above the night steps, or the moon's band below them; then
// the level offset and the banded vignette at `screen` (clip space).
float patchStep(vec2 xz) {
    if (rampPatch.x <= 0.0) {
        return 0.0;
    }
    float n = valueNoise(xz / rampPatch.x, 31.0) * 0.65 + valueNoise(xz / (rampPatch.x * 0.37), 32.0) * 0.35;
    return n < rampPatch.y ? -1.0 : (n > rampPatch.z ? 1.0 : 0.0);
}

// The ramp level of fire band `band` (0: none) on a surface whose night step is `night`: each band
// one step up from it, so the light's rim climbs out of the dark a step at a time (from the top
// night step it is the ramp's first fire colour).
int bandLevel(int band, int night) {
    if (band <= 0) {
        return night;
    }
    return max(night + band, int(rampBands.x + 0.5) - 3 + band);
}

vec3 rampColor(texture2D ramp, sampler rampSampler, int row, int level);

// The colour: the moon's night step, the fire's band over it, the level offset and the banded
// vignette at `screen` (clip space). Band b holds the light from FIRST + (b - 1) * STEP to
// FIRST + b * STEP; with rampPatch.w > 0 the two colours either side of a cut blend over that
// share of a band (Dylearn's hybrid toon shading), so a lit edge fades instead of snapping.
// `merge` > 1 takes the fire's bands that many at a time (a clump: a rosette is about a band
// wide, so with every band each one came out a different colour and the grass read as a mosaic).
vec3 rampShade(texture2D ramp, sampler rampSampler, int row, float fire, vec3 normal, vec2 screen, float offset, float merge) {
    float moon = clamp(dot(normal, dirLight.xyz), 0.0, 1.0);
    int night = int(moon > rampMoon.x) + int(moon > rampMoon.y);
    float radius = length(screen) * 0.70710678;
    int vignette = int(radius > rampVignette.x) + int(radius > rampVignette.y) + int(radius > rampVignette.z);
    int shift = int(floor(offset + 0.5)) - vignette * int(rampVignette.w > 0.5);
    int bands = int(rampBands.y + 0.5);
    float x = (fire - rampBands.z) / (rampBands.w * max(merge, 1.0));
    int widened = int(max(merge, 1.0) + 0.5);
    int band = clamp(int(ceil(x)) * widened, 0, bands);
    vec3 color = rampColor(ramp, rampSampler, row, bandLevel(band, night) + shift);
    float g = rampPatch.w;
    if (g > 0.0) {
        float cut = floor(x + 0.5);
        float d = x - cut;
        if (abs(d) < 0.5 * g && cut >= 0.0 && cut * float(widened) < float(bands)) {
            int below = int(cut);
            vec3 low = rampColor(ramp, rampSampler, row, bandLevel(min(below * widened, bands), night) + shift);
            vec3 high = rampColor(ramp, rampSampler, row, bandLevel(min((below + 1) * widened, bands), night) + shift);
            color = mix(low, high, smoothstep(-0.5 * g, 0.5 * g, d));
        }
    }
    return color;
}

vec3 rampColor(texture2D ramp, sampler rampSampler, int row, int level) {
    ivec2 size = textureSize(sampler2D(ramp, rampSampler), 0);
    ivec2 cell = ivec2(clamp(level, 0, size.x - 1), clamp(row, 0, size.y - 1));
    return texelFetch(sampler2D(ramp, rampSampler), cell, 0).rgb;
}
@end

@vs litRampVs
@include_block vertexUniforms
@include_block modelUniforms
in vec3 position;
in vec3 normal;
in vec4 color;
out vec3 worldPosition;
out vec3 worldNormal;
out float mark;
out vec2 screen;
out float depth01;
flat out vec3 objectOrigin;
void main() {
    vec4 world = model * vec4(position, 1.0);
    worldPosition = world.xyz;
    objectOrigin = (model * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    worldNormal = mat3(normalModel) * normal;
    mark = color.r;
    gl_Position = viewProj * world;
    screen = gl_Position.xy;
    depth01 = gl_Position.z;
}
@end

// rampRow.y > 0: faces within ~37 deg of up take row rampRow.y - 1 (a stone's top). rampLight.y
// > 0.5: steeper faces are walls (rampFire); > 1.5: every face is (logs, as the lab lights wood).
// rampMoon.z > 0.5: a wall takes the fire at its object's origin, so a flat face is one colour
// from edge to edge (the node's translation is that origin; the mesh is modelled around it). rampRow.w > 0: where the vertex colour's red is
// above it the surface is one step up (a lawn's long-grass patches, painted into the mesh).
@fs litRampFs
@include_block lightUniforms
@include_block rampUniforms
layout(binding=2) uniform texture2D shadowTexture;
layout(binding=1) uniform sampler shadowSampler;
@include_block noiseFunctions
@include_block rampFunctions
layout(binding=0) uniform texture2D rampTexture;
layout(binding=0) uniform sampler rampSampler;
in vec3 worldPosition;
in vec3 worldNormal;
in float mark;
in vec2 screen;
in float depth01;
flat in vec3 objectOrigin;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
void main() {
    vec3 n = normalize(worldNormal);
    bool top = n.y > 0.8;
    float marked = (rampRow.w > 0.0 && mark > rampRow.w) ? 1.0 : 0.0;
    bool wall = rampLight.y > 1.5 || (rampLight.y > 0.5 && abs(n.y) < 0.8);
    int row = (rampRow.y > 0.5 && top) ? int(rampRow.y + 0.5) - 1 : int(rampRow.x + 0.5);
    vec3 lightAt = (wall && rampMoon.z > 0.5) ? objectOrigin : worldPosition;
    float fire = rampFire(lightAt, n, wall);
    // Patches only in the firelight, as the grass's (billboardRampFs).
    float patchSteps = wall ? 0.0 : (fire > rampBands.z ? patchStep(worldPosition.xz) : 0.0) - walkerContact(worldPosition.xz);
    vec3 shaded = rampShade(rampTexture, rampSampler, row, fire, n, screen, rampRow.z + marked + patchSteps,
        (!wall && rampMoon.z > 1.5) ? rampMoon.z : 1.0);
    fragColor = vec4(shaded, 1.0);
    fragNormal = vec4(n * 0.5 + 0.5, depth01);
}
@end

// BillboardRamp's vertex block (binding=3): the five ramp vectors, then the wind and a walker.
// The wind is Dylearn's (youtube OxsuWDtjuGw) as the grass lab runs it: two value noises
// scrolling downwind, their directions spread by +-windA.z and their scale and speed apart by
// pi, multiplied into gusts; each sprite holds its pose for 1/fps s, its frames shifted by a hash
// of its root; a gust along the view is a fake perspective (the tips widen towards the camera).
// A walker parts the sprites around it and flattens them. Sway and perspective are rounded to
// whole texels and thirds, as the lab's tables are drawn.
//   windA  direction (x, z, unit), spread (rad), amplitude (share of the full sway)
//   windB  noise cell (m), speed (m/s), gain, bias: gust = clamp(n1 * n2 * gain + bias, 0, 1)
//   windC  sway at a full gust (texels), idle wiggle (texels), wiggle (Hz), poses per second
//   windD  perspective at a full gust, metres per texel (0: no wind), walker radius (0: none),
//          walker falloff exponent
//   windE  walker x, z, push (texels), flattening (share of the height)
@block spriteRampUniforms
layout(binding=3) uniform spriteRampParams {
    vec4 spriteRow;
    vec4 spriteBands;
    vec4 spriteLight;
    vec4 spriteMoon;
    vec4 spriteVignette;
    vec4 windA;
    vec4 windB;
    vec4 windC;
    vec4 windD;
    vec4 windE;
    vec4 spriteFar;
    vec4 spritePatch;
    vec4 spriteAccent;
    vec4 walkerFeet[2];
    vec4 walkerTrail[3];
    vec4 walkerTrailWeight[2];
    vec4 spriteWalker;
};
@end

@vs billboardRampVs
@include_block vertexUniforms
@include_block spriteRampUniforms
@include_block noiseFunctions
in vec2 corner;
in vec4 root;
in vec4 shape;
out vec2 uv;
out vec3 rootPosition;
out float offset;
out float emissive;
out vec2 screen;
out float depth01;
flat out vec4 vRampRow;
flat out vec4 vRampBands;
flat out vec4 vRampLight;
flat out vec4 vRampMoon;
flat out vec4 vRampVignette;
flat out vec4 vRampFar;
flat out vec4 vRampPatch;
flat out vec4 vRampWalker;
flat out float accentSteps;
flat out float tipShare;


vec2 turned(vec2 v, float angle) {
    return vec2(v.x * cos(angle) - v.y * sin(angle), v.x * sin(angle) + v.y * cos(angle));
}

float gustAt(vec2 at, float t) {
    vec2 d1 = turned(windA.xy, windA.z);
    vec2 d2 = turned(windA.xy, -windA.z);
    float scale2 = windB.x / 1.5707963;
    float speed2 = windB.y * 0.8490790;              // pi / 3.7
    float n1 = valueNoise((at - d1 * windB.y * t) / windB.x, 11.0);
    float n2 = valueNoise((at - d2 * speed2 * t) / scale2, 12.0);
    return clamp(n1 * n2 * windB.z + windB.w, 0.0, 1.0);
}

void main() {
    vec2 right = normalize(cameraRight.xz);
    vec2 toward = vec2(-right.y, right.x);           // the camera's side of the ground
    float swayTexels = 0.0;
    float persp = 0.0;
    float height = 1.0;
    if (windD.y > 0.0 && shape.w < 0.5) {
        float phase = hash21(root.xz, 7.0);
        float t = (floor(cameraUp.w * windC.w + phase) - phase) / windC.w;
        float gust = gustAt(root.xz, t);
        swayTexels = windA.w * (gust * windC.x * dot(windA.xy, right)
            + windC.y * sin(6.2831853 * (windC.z * t + hash21(root.xz, 8.0))));
        persp = -windA.w * gust * windD.x * dot(windA.xy, toward);
        if (windD.z > 0.0) {
            // The walker parts the grass from its body (windE.xy, windD.z), each of its four feet
            // (walkerFeet, walkerTrailWeight[1].z reach) and the last places it passed
            // (walkerTrail, faded by walkerTrailWeight; walkerTrailWeight[1].w reach), so a path
            // stays pressed behind it and springs back; the strongest push wins.
            float bestPush = 0.0;
            vec2 bestAway = vec2(0.0, 1.0);
            for (int k = 0; k < 11; k++) {
                vec2 at;
                float reach;
                float weight;
                if (k == 0) {
                    at = windE.xy; reach = windD.z; weight = 1.0;
                } else if (k < 5) {
                    int f = k - 1;
                    at = f < 2 ? (f == 0 ? walkerFeet[0].xy : walkerFeet[0].zw) : (f == 2 ? walkerFeet[1].xy : walkerFeet[1].zw);
                    reach = walkerTrailWeight[1].z; weight = 1.0;
                } else {
                    int i = k - 5;
                    vec4 pair = i < 2 ? walkerTrail[0] : (i < 4 ? walkerTrail[1] : walkerTrail[2]);
                    at = (i % 2 == 0) ? pair.xy : pair.zw;
                    vec4 w = walkerTrailWeight[0];
                    weight = i == 0 ? w.x : (i == 1 ? w.y : (i == 2 ? w.z : (i == 3 ? w.w
                        : (i == 4 ? walkerTrailWeight[1].x : walkerTrailWeight[1].y))));
                    reach = walkerTrailWeight[1].w;
                }
                if (reach <= 0.0 || weight <= 0.0) {
                    continue;
                }
                vec2 away = root.xz - at;
                float distance = length(away) + 0.000001;
                float pushed = weight * pow(clamp(1.0 - distance / reach, 0.0, 1.0), windD.w);
                if (pushed > bestPush) {
                    bestPush = pushed;
                    bestAway = away / distance;
                }
            }
            swayTexels += bestPush * windE.z * dot(bestAway, right);
            persp -= bestPush * windD.x * dot(bestAway, toward);
            height = 1.0 - windE.w * bestPush;
        }
        swayTexels = clamp(floor(swayTexels + 0.5), -3.0, 3.0);
        persp = windD.x * clamp(floor(persp / max(windD.x, 0.0001) + 0.5), -1.0, 1.0);
    }
    // Dylearn's accent grass: a hashed share of the sprites (spriteAccent.x) stands taller
    // (times .y) and a few steps lighter (.z).
    bool accent = spriteAccent.x > 0.0 && hash21(root.xz, 5.0) < spriteAccent.x;
    height *= accent ? spriteAccent.y : 1.0;
    accentSteps = accent ? spriteAccent.z : 0.0;
    tipShare = spriteAccent.w;
    float up = corner.y;
    // spriteRow.y > 0: every sprite turned by up to that many radians either way about its
    // middle, and half of them mirrored, hashed on the root so a clump keeps its pose: the
    // rosettes do not all stand the same way up (user, 2026-10-01).
    float spin = 0.0;
    float mirror = 1.0;
    if (spriteRow.y > 0.0) {
        spin = (hash21(root.xz, 9.0) * 2.0 - 1.0) * spriteRow.y;
        mirror = hash21(root.xz, 10.0) < 0.5 ? -1.0 : 1.0;
    }
    float ox = corner.x * shape.x * (1.0 + persp * up);
    float oy = (up - 0.5) * shape.y * height;
    float turnCos = cos(spin);
    float turnSin = sin(spin);
    float across = ox * turnCos - oy * turnSin + swayTexels * windD.y * up * up;
    float lift = ox * turnSin + oy * turnCos + 0.5 * shape.y * height;
    vec3 p = root.xyz + cameraRight.xyz * across + cameraUp.xyz * lift;
    gl_Position = viewProj * vec4(p, 1.0);
    screen = gl_Position.xy;
    depth01 = gl_Position.z;
    uv = vec2((mirror * corner.x + 0.5 + root.w) * 0.25, 1.0 - corner.y);
    rootPosition = root.xyz;
    offset = shape.z;
    emissive = shape.w;
    vRampRow = spriteRow;
    vRampBands = spriteBands;
    vRampLight = spriteLight;
    vRampMoon = spriteMoon;
    vRampVignette = spriteVignette;
    vRampFar = spriteFar;
    vRampPatch = spritePatch;
    vRampWalker = spriteWalker;
}
@end

// One colour per sprite: the ramp at its root, lit as ground facing up (so a clump is the colour
// of the lawn it stands on), nudged by up to rampRow.w of light by a hash of the root so a light
// edge is a band of mixed clumps. shape.z is the sprite's own steps (rampLight.w > 0.5: the steps
// up only in firelight). Emissive sprites (the flame) keep their texels.
@fs billboardRampFs
@include_block lightUniforms
layout(binding=0) uniform texture2D spriteTexture;
layout(binding=1) uniform texture2D spriteRamp;
layout(binding=2) uniform texture2D shadowTexture;
layout(binding=0) uniform sampler spriteSampler;
layout(binding=1) uniform sampler shadowSampler;
in vec2 uv;
in vec3 rootPosition;
in float offset;
in float emissive;
in vec2 screen;
in float depth01;
flat in vec4 vRampRow;
flat in vec4 vRampBands;
flat in vec4 vRampLight;
flat in vec4 vRampMoon;
flat in vec4 vRampVignette;
flat in vec4 vRampFar;
flat in vec4 vRampPatch;
flat in vec4 vRampWalker;
flat in float accentSteps;
flat in float tipShare;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
vec4 rampRow;
vec4 rampBands;
vec4 rampLight;
vec4 rampMoon;
vec4 rampVignette;
vec4 rampFar;
vec4 rampPatch;
vec4 rampWalker;
@include_block noiseFunctions
@include_block rampFunctions
void main() {
    rampRow = vRampRow;
    rampBands = vRampBands;
    rampLight = vRampLight;
    rampMoon = vRampMoon;
    rampVignette = vRampVignette;
    rampFar = vRampFar;
    rampPatch = vRampPatch;
    rampWalker = vRampWalker;
    vec4 texel = texture(sampler2D(spriteTexture, spriteSampler), uv);
    if (texel.a < 0.5) {
        discard;
    }
    vec3 up = vec3(0.0, 1.0, 0.0);
    float fire = rampFire(rootPosition, up, false);
    bool lit = fire > rampBands.z;
    float nudge = fract(sin(dot(rootPosition.xz, vec2(39.3468, 11.1353))) * 24634.6345) - 0.5;
    fire += lit ? nudge * 2.0 * rampRow.w : 0.0;
    float steps = (rampLight.w > 0.5 && !lit) ? min(offset, 0.0) : offset;
    if (rampFar.w > 0.5 && !lit) {
        steps = 0.0;
    }
    // Patches, accents and tips are colour the eye only finds in the firelight: in the moonlit
    // dark (and the fog) the grass is one tone, its shape left to the moon's steps.
    steps += (lit ? accentSteps + patchStep(rootPosition.xz) : 0.0) - walkerContact(rootPosition.xz);
    // spriteAccent.w: the top share of the sprite is a step lighter, so where blades overlap
    // their tips draw light strokes over the grass below instead of the ground showing through.
    steps += (lit && uv.y < tipShare) ? 1.0 : 0.0;
    vec3 shaded = rampShade(spriteRamp, spriteSampler, int(rampRow.x + 0.5), fire, up, screen, rampRow.z + steps, rampMoon.z);
    fragColor = vec4(mix(shaded, texel.rgb, emissive), 0.0);
    fragNormal = vec4(0.5, 1.0, 0.5, depth01);
}
@end

@program lit litVs litFs
@program billboard billboardVs billboardFs
@program post fullscreenVs postFs
@program blit fullscreenVs blitFs
@program particle particleVs particleFs
@program litRamp litRampVs litRampFs
@program billboardRamp billboardRampVs billboardRampFs
