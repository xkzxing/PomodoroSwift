#include <metal_stdlib>
using namespace metal;

constant sampler gemLinear(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
constant sampler gemNearest(coord::normalized, address::clamp_to_edge, filter::nearest);
constant sampler gemProbeSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
constant float gemPi = 3.14159265359;

float2 gemRotate(float2 p, float angle) {
    float c = cos(angle), s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}
float3 gemBackground(texture2d<half> image, float2 point, float4 mapping) {
    return float3(image.sample(gemLinear, mapping.xy + point * mapping.zw).rgb);
}
float2 gemAtlasUV(float2 p, float layer) {
    return float2(p.x + 0.5, (p.y + 0.5 + layer) * 0.5);
}
float4 gemSurface(texture2d<half> data, float2 p, float layer) {
    if (any(abs(p) > 0.4995)) return 0;
    float4 sample = float4(data.sample(gemLinear, gemAtlasUV(p, layer)));
    float4 nearest = float4(data.sample(gemNearest, gemAtlasUV(p, layer)));
    float3 channels = sample.rgb / max(sample.a, 0.0001);
    float3 labels = nearest.rgb / max(nearest.a, 0.0001);
    return float4(channels.r * 0.1, round(labels.g * 16), channels.b, sample.a);
}
float3 gemNormal(texture2d<half> normals, float2 p, float layer) {
    float3 n = float3(normals.sample(gemLinear, gemAtlasUV(p, layer)).rgb) * 2 - 1;
    return normalize(float3(n.xy, max(0.025, n.z)));
}
// Captured linear HDR illumination plus the actual window background.
// Moving the object changes ray directions and intersections, not a UV decal.
float3 gemEnvironment(texture2d<half> image, texture2d<half> lightProbe, float3 surface, float3 ray,
                      float4 mapping, float4 scene) {
    float height = max(scene.w, 1.0), width = max(scene.z, 1.0);
    // A finite room dome gives environmental reflection parallax as the dial
    // moves. The HDR capture supplies continuous radiance, not painted streaks.
    float3 roomCenter = float3(width * 0.5, height * 0.5, height * 0.4);
    float3 direction = normalize(surface + ray * height * 2.2 - roomCenter);
    direction = float3(direction.x, -direction.y, direction.z);
    float2 uv = float2(atan2(direction.z, direction.x) / (2 * gemPi) + 0.63,
                       acos(clamp(direction.y, -1.0, 1.0)) / gemPi);
    float3 room = float3(lightProbe.sample(gemProbeSampler, uv).rgb);
    float distance = (height * 1.5 - surface.z) / max(0.12, abs(ray.z));
    float2 world = surface.xy + ray.xy * min(distance, height * 3.0);
    float3 photo = gemBackground(image, world - scene.xy, mapping);
    float3 current = gemBackground(image, surface.xy - scene.xy, mapping);
    float luminance = max(0.01, dot(current, float3(0.2126, 0.7152, 0.0722)));
    float3 colorAdaptation = mix(float3(1), sqrt(current / luminance), 0.22);
    return room * colorAdaptation * (0.50 + 0.50 * sqrt(luminance)) + photo * 0.32;

}
float3 gemFresnel(float cosine, float3 f0) {
    float a = 1 - saturate(cosine);
    return f0 + (1 - f0) * a * a * a * a * a;
}
float gemSmith(float cosine, float alpha) {
    float c = max(cosine, 0.0001);
    return 2 * c / (c + sqrt(alpha * alpha + (1 - alpha * alpha) * c * c));
}

// Integrate a GGX microfacet distribution against the environment. This replaces
// the old power-function highlights and additive white bands. Smith masking and
// wavelength-dependent Fresnel keep reflected / transmitted energy separate.
float3 gemReflection(texture2d<half> image, texture2d<half> lightProbe, float3 point, float3 n, float3 view,
                     float roughness, float3 f0, float4 mapping, float4 scene) {
    float3 tangent = normalize(abs(n.z) < 0.999 ? cross(float3(0, 0, 1), n) : float3(1, 0, 0));
    float3 bitangent = cross(n, tangent);
    float nv = max(dot(n, view), 0.001);
    float alpha = roughness * roughness;
    float3 radiance = 0;
    const float sequence[8] = {0.0625, 0.5625, 0.3125, 0.8125, 0.1875, 0.6875, 0.4375, 0.9375};
    for (int i = 0; i < 8; ++i) {
        float u = (float(i) + 0.5) / 8;
        float phi = 2 * gemPi * sequence[i];
        float cosine = sqrt((1 - u) / (1 + (alpha * alpha - 1) * u));
        float sine = sqrt(max(0.0, 1 - cosine * cosine));
        float3 h = normalize(tangent * (cos(phi) * sine) + bitangent * (sin(phi) * sine) + n * cosine);
        float vh = max(dot(view, h), 0.0);
        float3 ray = reflect(-view, h);
        float nl = dot(n, ray);
        if (nl <= 0 || vh <= 0) continue;
        float geometry = gemSmith(nv, alpha) * gemSmith(nl, alpha);
        float weight = geometry * vh / max(dot(n, h) * nv, 0.0001);
        radiance += gemEnvironment(image, lightProbe, point, ray, mapping, scene) * gemFresnel(vh, f0) * weight;
    }
    return radiance / 8;
}

struct GemPavilion {
    float2 center;
    float2 axes;
    float rotation;
    float depth;
};
GemPavilion gemPavilionAt(float2 p) {
    GemPavilion result;
    float radius = length(p);
    float divisions = radius > 0.35 ? 18.0 : radius > 0.27 ? 12.0 : 8.0;
    float index = floor((atan2(p.x, -p.y) + gemPi / divisions) / (2 * gemPi / divisions));
    float best = 1e6;
    for (int offset = -1; offset <= 1; ++offset) {
        float angle = (index + offset) * 2 * gemPi / divisions;
        float2 local = gemRotate(p, -angle);
        float2 center = radius > 0.35 ? float2(0.018, -0.418) : radius > 0.27 ? float2(0, -0.328) : float2(0, -0.078);
        float2 axes = radius > 0.35 ? float2(0.130, 0.100) : radius > 0.27 ? float2(0.032, 0.062) : float2(0.043, 0.065);
        float2 q = (local - center) / axes;
        float score = dot(q, q);
        if (score < best) {
            best = score;
            result.center = gemRotate(center, angle); result.axes = axes; result.rotation = angle;
            result.depth = radius > 0.35 ? 0.044 : 0.025;
        }
        if (radius > 0.35) {
            center = float2(-0.076, -0.452); axes = float2(0.028, 0.029);
            q = (local - center) / axes;
            score = dot(q, q);
            if (score < best) {
                best = score;
                result.center = gemRotate(center, angle); result.axes = axes; result.rotation = angle; result.depth = 0.022;
            }
        }
    }
    return result;
}

// Trace refraction through the crown and a sixteen-plane pavilion. The rear
// facets are geometry: they redirect rays, including total internal reflection.
// No triangle colors or white facets are painted on the visible front surface.
float3 gemCutTransmission(texture2d<half> background, texture2d<half> lightProbe, texture2d<half> normals, texture2d<half> data,
                           float2 p, float z, float3 n, float3 view, float3 absorption,
                           float diameter, float4 mapping, float4 scene, float material) {
    GemPavilion gem = gemPavilionAt(p);
    float3 ray = refract(-view, n, 1 / 1.62);
    float3 point = float3(p, z - 0.0001);
    float3 throughput = 1;
    float3 result = 0;
    const float base = 0.009;
    for (int bounce = 0; bounce < 6; ++bounce) {
        float distance = 1e4;
        float3 outward;
        if (ray.z < 0) {
            float2 local = gemRotate(point.xy - gem.center, -gem.rotation);
            float2 direction = gemRotate(ray.xy, -gem.rotation);
            for (int facet = 0; facet < 16; ++facet) {
                float a = (float(facet) + 0.5) * gemPi / 8;
                float2 slope = float2(cos(a), sin(a)) / gem.axes * gem.depth;
                float denominator = ray.z - dot(direction, slope);
                float t = (base - gem.depth + dot(local, slope) - point.z) / denominator;
                if (denominator < -0.0001 && t > 0.0001 && t < distance) {
                    distance = t;
                    outward = normalize(float3(gemRotate(slope, gem.rotation), -1));
                }
            }
        } else {
            distance = max(0.0001, (z - point.z) / max(ray.z, 0.05));
            for (int iteration = 0; iteration < 3; ++iteration) {
                float2 hit = point.xy + ray.xy * distance;
                float4 top = gemSurface(data, hit, 0);
                if (top.g == material) distance = max(0.0001, (top.r - point.z) / max(ray.z, 0.05));
            }
            float2 hit = point.xy + ray.xy * distance;
            float4 top = gemSurface(data, hit, 0);
            outward = top.g == material ? gemNormal(normals, hit, 0) : n;
        }
        if (distance > 0.25) break;
        point += ray * distance;
        throughput *= exp(-absorption * distance * 36);
        float cosine = saturate(dot(ray, outward));
        float3 exitRay = refract(ray, -outward, 1.62);
        bool internal = dot(exitRay, exitRay) < 0.01;
        float reflectance = internal ? 1.0 : gemFresnel(cosine, float3(0.055)).r;
        if (!internal) {
            float3 radiance;
            float2 localPosition = point.xy * diameter + float2(diameter * 0.5);
            if (exitRay.z > 0) {
                float3 world = float3(scene.xy + localPosition, point.z * diameter);
                radiance = gemEnvironment(background, lightProbe, world, exitRay, mapping, scene);
            } else {
                float2 behind = localPosition + exitRay.xy / max(0.12, -exitRay.z) * diameter * 0.045;
                radiance = gemBackground(background, behind, mapping);
            }
            result += throughput * (1 - reflectance) * radiance;
        }
        throughput *= reflectance;
        ray = reflect(ray, -outward);
        point += ray * 0.00015;
    }
    float2 originalPosition = p * diameter + float2(diameter * 0.5);
    result += throughput * gemBackground(background, originalPosition, mapping) * exp(-absorption * 1.8);
    return result;
}

float3 gemToneMap(float3 color) {
    // Filmic shoulder in linear light; prevents white highlights clipping into
    // harsh flat patches while retaining colored specular response in gold.
    float3 x = max(color * 0.86, 0.0);
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

half4 gemstoneSculpture(float2 position, half4 input,
                                        float2 size, texture2d<half> background, texture2d<half> lightProbe,
                                        float4 mapping, float4 scene,
                                        texture2d<half> normals, texture2d<half> data,
                                        float handAngle, float renderMode) {
    float diameter = min(size.x, size.y);
    float2 p = (position - size * 0.5) / diameter;
    float4 fixed = gemSurface(data, p, 0);
    float2 handP = gemRotate(p, -handAngle);
    float4 hand = gemSurface(data, handP, 1);
    bool isHand = hand.a > 0.05 && hand.r > fixed.r;
    float4 surfaceData = isHand ? hand : fixed;
    float coverage = surfaceData.a;
    if (coverage < 0.002) return half4(0);
    float3 n = gemNormal(normals, isHand ? handP : p, isHand ? 1 : 0);
    if (isHand) n.xy = gemRotate(n.xy, handAngle);
    int material = int(surfaceData.g);
    bool gold = material == 1;
    bool opal = material == 2 || material == 8;
    float z = surfaceData.r;
    float3 point = float3(scene.xy + position, z * diameter);
    float3 camera = float3(scene.z * 0.5, scene.w * 0.45, max(scene.w, size.y) * 1.5);
    float3 view = normalize(camera - point);
    float nv = max(dot(n, view), 0.001);
    float3 dx = dfdx(n), dy = dfdy(n);
    float variance = min(0.09, (dot(dx, dx) + dot(dy, dy)) * 0.10);
    float roughness = sqrt((gold ? 0.17 * 0.17 : opal ? 0.14 * 0.14 : 0.15 * 0.15) + variance);
    float3 f0 = gold ? float3(0.99, 0.62, 0.17) : float3(0.055);
    float3 reflected = gemReflection(background, lightProbe, point, n, view, roughness, f0, mapping, scene);
    float3 color;
    if (gold) {
        color = reflected * (0.64 + 0.36 * surfaceData.b);
    } else if (material == 9) {
        // Keep the compatibility hand legible on the same bright glass face.
        color = float3(0.004, 0.012, 0.022) + reflected * 0.48;
    } else {
        float3 absorption = float3(0.015, 0.010, 0.006);
        if (material == 4) absorption = float3(3.10, 1.15, 0.045);
        if (material == 5) absorption = float3(2.40, 0.22, 0.28);
        if (material == 6) absorption = float3(0.020, 0.85, 2.65);
        if (material == 7) absorption = float3(0.025, 1.85, 1.95);
        float thickness = material == 8 ? 0.032 : isHand ? 0.012 : material == 2 ? 0.020 : max(z - 0.007, 0.008);
        float3 transmitted;
        if (!opal) {
            transmitted = gemCutTransmission(background, lightProbe, normals, data, p, z, n, view, absorption,
                                               diameter, mapping, scene, surfaceData.g);
        } else {
            float3 insideRay = refract(-view, n, 1 / 1.62);
            float2 offset = insideRay.xy / max(0.15, -insideRay.z) * thickness * diameter * 1.7;
            transmitted.r = gemBackground(background, position + offset * 1.035, mapping).r;
            transmitted.g = gemBackground(background, position + offset, mapping).g;
            transmitted.b = gemBackground(background, position + offset * 0.965, mapping).b;
            transmitted *= exp(-absorption * thickness * 36);
        }
        if (opal) {
            float spread = diameter * (material == 8 ? 0.018 : 0.038);
            float3 blur = (gemBackground(background, position + float2(spread, 0), mapping)
                         + gemBackground(background, position + float2(-spread * 0.5, spread * 0.86), mapping)
                         + gemBackground(background, position + float2(-spread * 0.5, -spread * 0.86), mapping)) / 3;
            float3 milk = float3(0.63, 0.73, 0.74);
            transmitted = mix(transmitted, blur * 0.35 + milk * 0.65, material == 8 ? 0.65 : 0.72);
            float phase = (1 - nv) * 12 + z * 180;
            float3 film = 0.5 + 0.5 * cos(phase + float3(0, 2.1, 4.2));
            transmitted += film * (material == 8 ? 0.10 : 0.020);
        }
        color = transmitted * (1 - gemFresnel(nv, float3(0.055))) + reflected;
        color *= 0.76 + surfaceData.b * 0.24;
        if (!isHand && material != 8) {
            float2 shadowP = gemRotate(p - float2(0.005, 0.008), -handAngle);
            float4 blocker = gemSurface(data, shadowP, 1);
            if (blocker.r > z + 0.006) color *= 1 - 0.28 * blocker.a;
        }
    }
    if (renderMode > 1.5) color = reflected;
    if (renderMode > 0.5 && renderMode < 1.5) return half4(half3(n * 0.5 + 0.5) * half(coverage), half(coverage));
    color = gemToneMap(color);
    return half4(half3(color) * half(coverage), half(coverage));
}

struct GemstoneVertexOut {
    float4 position [[position]];
    float2 uv;
};
struct GemstoneUniforms {
    float4 sizeAndAngle;
    float4 mapping;
    float4 scene;
};
vertex GemstoneVertexOut gemstoneVertex(uint id [[vertex_id]]) {
    const float2 uv[4] = {float2(0, 0), float2(0, 1), float2(1, 0), float2(1, 1)};
    GemstoneVertexOut out;
    out.position = float4(uv[id].x * 2 - 1, 1 - uv[id].y * 2, 0, 1);
    out.uv = uv[id];
    return out;
}
fragment half4 gemstoneFragment(GemstoneVertexOut in [[stage_in]], constant GemstoneUniforms &u [[buffer(0)]],
                                texture2d<half> background [[texture(0)]], texture2d<half> normals [[texture(1)]],
                                texture2d<half> data [[texture(2)]], texture2d<half> lightProbe [[texture(3)]]) {
    // Four spatial samples antialias thin filigree and specular boundaries.
    // This is deterministic; moving the clock does not introduce temporal noise.
    float2 dx = dfdx(in.uv) * 0.25;
    float2 dy = dfdy(in.uv) * 0.25;
    half4 color = 0;
    for (int y = -1; y <= 1; y += 2) {
        for (int x = -1; x <= 1; x += 2) {
            float2 uv = in.uv + float(x) * dx + float(y) * dy;
            color += gemstoneSculpture(uv * u.sizeAndAngle.xy, half4(1), u.sizeAndAngle.xy,
                background, lightProbe, u.mapping, u.scene, normals, data, u.sizeAndAngle.z, u.sizeAndAngle.w);
        }
    }
    return color * 0.25h;
}
