#include <metal_stdlib>
#include <metal_raytracing>
#include "GemstoneDielectric.h"
using namespace metal;
using namespace raytracing;

constant float jewelPi = 3.14159265358979;
constant sampler jewelPhoto(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
struct JewelVertex { float3 position; float3 normal; };
struct JewelUniforms { float4 sizeAndAngle; float4 mapping; float4 scene; float4 camera; float4 lighting; uint4 cache; uint4 visibility; };
struct JewelRaster { float4 position [[position]]; float2 uv; };
struct JewelHit { float distance; float3 point; float3 normal; float3 geometricNormal; uint material; uint boundary; bool valid; };
#define JEWEL_SCENE_ARGS primitive_acceleration_structure body, primitive_acceleration_structure hand, device const JewelVertex *bodyVertices, device const uint *bodyMaterials, device const JewelVertex *handVertices, device const uint *handMaterials, texture3d<half> illumination, constant JewelUniforms &u, thread uint4 &handInfluence
#define JEWEL_SCENE body, hand, bodyVertices, bodyMaterials, handVertices, handMaterials, illumination, u, handInfluence
constant float3 jewelFieldMin=float3(-0.54,-0.54,-0.09);
constant float3 jewelFieldMax=float3(0.54,0.54,0.18);
constant uint3 jewelFieldSize=uint3(128,128,32);
constant float jewelPhotonScale=268435456.0;
constant sampler jewelFieldSampler(coord::normalized,address::clamp_to_zero,filter::linear);

float2 jewelRotate(float2 p, float angle) {
    return float2(cos(angle) * p.x - sin(angle) * p.y, sin(angle) * p.x + cos(angle) * p.y);
}
float3 jewelEye(constant JewelUniforms &u) {
    float diameter = min(u.sizeAndAngle.x, u.sizeAndAngle.y);
    return float3((u.scene.zw * float2(0.5, 0.45) - u.scene.xy - u.sizeAndAngle.xy * 0.5) / diameter + u.camera.xy,
                  max(1.7, u.scene.w / diameter * 1.45));
}

// A conservative angular visibility mask for the complete swept hand volume.
// It follows the same primary, reflected, refracted and shadow rays as shading;
// affected pixels can therefore lie outside the visible arm's rectangle.
uint jewelMaskWord(int first,int end,int word) {
    int lo=clamp(first-word*32,0,32),hi=clamp(end-word*32,0,32);
    if(hi<=lo) return 0;
    return (0xffffffffu >> (32-(hi-lo))) << lo;
}
uint4 jewelHandRayMask(ray r, float stop) {
    float lo=r.min_distance, hi=min(stop,r.max_distance);
    if (abs(r.direction.z)<0.000001) {
        if (r.origin.z<0.083 || r.origin.z>0.116) return 0;
    } else {
        float a=(0.083-r.origin.z)/r.direction.z;
        float b=(0.116-r.origin.z)/r.direction.z;
        lo=max(lo,min(a,b)); hi=min(hi,max(a,b));
    }
    float a=dot(r.direction.xy,r.direction.xy);
    float b=dot(r.origin.xy,r.direction.xy);
    float c=dot(r.origin.xy,r.origin.xy)-0.362*0.362;
    if (a<0.00000001) { if(c>0) return 0; }
    else {
        float discriminant=b*b-a*c;
        if(discriminant<0) return 0;
        float root=sqrt(discriminant);
        lo=max(lo,(-b-root)/a); hi=min(hi,(-b+root)/a);
    }
    if(hi<lo) return 0;
    float2 p=r.origin.xy+r.direction.xy*lo;
    float2 q=r.origin.xy+r.direction.xy*hi;
    float closest=a<0.00000001 ? lo : clamp(-b/a,lo,hi);
    float radius=length(r.origin.xy+r.direction.xy*closest);
    if(radius<0.020) return uint4(0xffffffffu);
    float first=atan2(p.x,-p.y), last=atan2(q.x,-q.y);
    float arc=atan2(sin(last-first),cos(last-first));
    float middle=first+arc*0.5;
    // Include the widest blade, its off-centre shaft and each bin's extent.
    float lateral=min(0.12+0.012/radius,asin(min(1.0,0.030/radius)));
    float extent=abs(arc)*0.5+lateral+jewelPi/128;
    // A wrapped interval is at most two contiguous bit ranges. Construct its
    // four words directly instead of evaluating trigonometry for every bin.
    int firstBin=int(ceil((middle-extent)*128/(2*jewelPi)-0.5));
    int lastBin=int(floor((middle+extent)*128/(2*jewelPi)-0.5));
    int count=lastBin-firstBin+1;
    if(count>=128) return uint4(0xffffffffu);
    if(count<=0) return uint4(0);
    int start=((firstBin%128)+128)%128,end=start+count;
    uint4 mask=0;
    for(int i=0;i<4;++i) {
        mask[i]=jewelMaskWord(start,min(end,128),i);
        if(end>128) mask[i]|=jewelMaskWord(0,end-128,i);
    }
    return mask;
}

JewelHit jewelIntersect(ray r, JEWEL_SCENE_ARGS) {
    intersector<triangle_data> query;
    query.assume_geometry_type(geometry_type::triangle);
    query.force_opacity(forced_opacity::opaque);
    auto a = query.intersect(r, body);
    bool cacheBuild=u.cache.x==1;
    if(cacheBuild) handInfluence|=jewelHandRayMask(r,a.type==intersection_type::none ? r.max_distance : a.distance);
    ray localRay = r;
    localRay.origin.xy = jewelRotate(r.origin.xy, -u.sizeAndAngle.z);
    localRay.direction.xy = jewelRotate(r.direction.xy, -u.sizeAndAngle.z);
    // The hand cannot win behind the nearest fixed surface. The conservative
    // local box includes its gold rim as well as the enamel blade and shaft.
    // Its bounds are covered by the mesh regression test.
    localRay.max_distance=a.type==intersection_type::none ? r.max_distance : min(r.max_distance,a.distance);
    float3 inverse=1/localRay.direction;
    float3 t0=(float3(-0.030,-0.360,0.083)-localRay.origin)*inverse;
    float3 t1=(float3( 0.030, 0.000,0.116)-localRay.origin)*inverse;
    float3 near=min(t0,t1),far=max(t0,t1);
    float enter=max(localRay.min_distance,max(near.x,max(near.y,near.z)));
    float leave=min(localRay.max_distance,min(far.x,min(far.y,far.z)));
    bool queryHand=!cacheBuild && leave>=enter;
    intersection_result<triangle_data> b=a;
    bool chooseHand=false;
    if(queryHand) {
        b=query.intersect(localRay,hand);
        chooseHand=b.type!=intersection_type::none;
    }
    JewelHit hit;
    hit.valid = chooseHand || a.type != intersection_type::none;
    if (!hit.valid) return hit;
    uint index = chooseHand ? b.primitive_id : a.primitive_id;
    float2 barycentric = chooseHand ? b.triangle_barycentric_coord : a.triangle_barycentric_coord;
    device const JewelVertex *v = chooseHand ? handVertices : bodyVertices;
    JewelVertex v0 = v[index * 3], v1 = v[index * 3 + 1], v2 = v[index * 3 + 2];
    float3 weights = float3(1 - barycentric.x - barycentric.y, barycentric.x, barycentric.y);
    hit.distance = chooseHand ? b.distance : a.distance;
    hit.point = r.origin + r.direction * hit.distance;
    hit.normal = normalize(v0.normal * weights.x + v1.normal * weights.y + v2.normal * weights.z);
    hit.geometricNormal = normalize(cross(v1.position - v0.position, v2.position - v0.position));
    if (chooseHand) {
        hit.normal.xy = jewelRotate(hit.normal.xy, u.sizeAndAngle.z);
        hit.geometricNormal.xy = jewelRotate(hit.geometricNormal.xy, u.sizeAndAngle.z);
    }
    hit.boundary = chooseHand ? handMaterials[index] : bodyMaterials[index];
    hit.material = hit.boundary & 255u;
    return hit;
}
ray jewelRay(float3 origin, float3 direction) {
    ray r;
    r.origin = origin; r.direction = normalize(direction); r.min_distance = 0.00008; r.max_distance = 20;
    return r;
}
float jewelPhotoLod(texture2d<half> photo,float requested,constant JewelUniforms &u) {
    float2 visible=float2(photo.get_width(),photo.get_height())*u.mapping.zw*u.scene.zw;
    float correction=log2(max(1.0,max(visible.x,visible.y))/2048.0);
    return max(0.0,requested+correction);
}
float3 jewelBackground(texture2d<half> photo, float3 point, float3 direction, constant JewelUniforms &u, float blur = 0) {
    float t = (-0.19 - point.z) / min(-0.001, direction.z);
    float3 hit = point + direction * max(t, 0.0);
    float3 eye = jewelEye(u);
    // The flat photographic plane is calibrated to the unbent camera ray. A
    // straight ray therefore reproduces the exact window background position.
    float2 projected = eye.xy + (hit.xy - eye.xy) * eye.z / (eye.z - hit.z);
    float2 pixels = projected * min(u.sizeAndAngle.x, u.sizeAndAngle.y) + u.sizeAndAngle.xy * 0.5;
    return float3(photo.sample(jewelPhoto, u.mapping.xy + pixels * u.mapping.zw, level(blur > 0 ? jewelPhotoLod(photo,blur,u) : 0)).rgb);
}
float3 jewelLiftTransmission(float3 color,float strength) {
    float luminance=dot(color,float3(0.2126,0.7152,0.0722));
    if(luminance<=0.000001 || luminance>=1 || strength<=0) return color;
    // Monotonic, bounded shadow exposure. Black stays black, white stays white,
    // and a shared RGB multiplier preserves the photograph's colour ratios.
    float lifted=(1-exp(-3.5*luminance))/(1-exp(-3.5));
    return color*mix(1.0,lifted/luminance,saturate(strength));
}
float3 jewelTransmittedBackground(texture2d<half> photo,float3 point,float3 direction,
    constant JewelUniforms &u,float blur=0) {
    return jewelLiftTransmission(jewelBackground(photo,point,direction,u,blur),u.lighting.y);
}
float2 jewelReflectionUV(float3 point,float3 direction,constant JewelUniforms &u) {
    direction=normalize(direction);
    float diameter=min(u.sizeAndAngle.x,u.sizeAndAngle.y);
    // A single photograph supplies a local proxy for the surroundings. The
    // bounded directional projection stays finite at grazing angles; actual
    // surface normals and rear cuts determine the reflected direction.
    float2 travel=float2(-direction.x,direction.y)/(1+abs(direction.z))*0.72*u.scene.zw;
    float2 pixel=point.xy*diameter+u.sizeAndAngle.xy*0.5+travel;
    float2 uv=u.mapping.xy+pixel*u.mapping.zw;
    // Mirror continuation avoids a clamped edge turning into a flat stripe.
    return 1-abs(fract(uv*0.5)*2-1);
}
float3 jewelPhotoEnvironment(texture2d<half> photo,float3 point,float3 direction,float lod,constant JewelUniforms &u) {
    float2 uv=jewelReflectionUV(point,direction,u);
    return float3(photo.sample(jewelPhoto,uv,level(jewelPhotoLod(photo,1.0+lod*2.5,u))).rgb);
}
float jewelPhotoLobe(float3 direction,float3 room,float3 center,float power,float lod) {
    float filteredPower=power/(1+0.25*lod*lod);
    return pow(max(0.0,dot(direction,normalize(center-room))),filteredPower)
        *(filteredPower+1)/(power+1);
}
float3 jewelEnvironment(texture2d<half> photo,float3 point,float3 direction,float lod,constant JewelUniforms &u,bool polishedGold=false) {
    float3 source=jewelPhotoEnvironment(photo,point,direction,lod,u);
    float3 average=float3(photo.sample(jewelPhoto,float2(0.5),level(float(photo.get_num_mip_levels()-1))).rgb);
    float mean=dot(average,float3(0.2126,0.7152,0.0722));
    // A bounded, image-wide exposure preserves photographic contrast while
    // keeping reflective rims legible against the darkest backgrounds.
    float exposure=clamp(sqrt(0.20/max(mean,0.0125)),1.0,4.0);
    // A display-range photo has compressed the radiance of bright surroundings.
    // Restore bounded daylight headroom to reflections using its own colour;
    // direct background transmission keeps the original photographic exposure.
    exposure*=1.0+1.2*smoothstep(0.06,0.40,mean);
    float diameter=min(u.sizeAndAngle.x,u.sizeAndAngle.y);
    float2 translation=(u.scene.xy+u.sizeAndAngle.xy*0.5-u.scene.zw*0.5)/max(diameter,1.0);
    float3 room=point+float3(translation,0);
    direction=normalize(direction);
    // A photograph cannot supply the unseen surroundings or their HDR range.
    // Compact lobes recover shape cues using only the warped photograph's
    // radiance. Even with exposure compensation, black emits no light.
    float key=jewelPhotoLobe(direction,room,float3(-0.85,-1.2,1.6),110,lod);
    float rim=jewelPhotoLobe(direction,room,float3(1.25,0.1,1.2),160,lod);
    float accent=jewelPhotoLobe(direction,room,float3(-0.3,0.9,1.8),240,lod);
    float3 reflected=source*exposure*(0.80+4.0*key+3.0*rim+4.0*accent);
    if(polishedGold) {
        // Recover the compact bright reflections lost in a display-range
        // photograph. Curved metal normals select the lit portions; no time,
        // screen-space stripes or additional emissive geometry are involved.
        // The broader shoulder gives each small glint a readable falloff.
        float shoulder=jewelPhotoLobe(direction,room,float3(-0.85,-1.2,1.6),32,lod);
        float edge=jewelPhotoLobe(direction,room,float3(1.25,0.1,1.2),52,lod);
        // The photographed light sources are often clipped or out of frame.
        // Estimate their missing radiance from the photograph's mean colour,
        // with partial chromatic adaptation. This bounded artistic estimate
        // still goes dark with a black photo and travels through the actual
        // reflected interfaces, including neighbouring coloured crystals.
        float3 lightColor=mix(average,float3(mean),0.65);
        reflected+=lightColor*exposure*(12.0*shoulder+8.0*edge+28.0*key+18.0*rim+22.0*accent);
    }
    return reflected;
}
float3 jewelSchlick(float cosine, float3 f0) {
    float t = 1 - saturate(cosine), t2 = t * t;
    return f0 + (1 - f0) * t2 * t2 * t;
}
float3 jewelEmissionRadiance(uint material) {
    if(material==14) return float3(2.0,26,34)*320;
    if(material==15) return float3(1.2,6,32)*320;
    if(material==16) return float3(32,0.08,0.6)*32;
    if(material==18) return float3(4.2,2.15,0.55);
    if(material==19) return float3(0.12,1.65,2.4);
    if(material==20) return float3(2.4,1.45,0.48);
    return float3(1,0.38,0.055);
}
float jewelSourceGradient(uint material,float3 point) {
    // One broad, continuous sweep across the dial; no repeating light bands.
    return material==18 ? 1+0.34*clamp(-1.35*point.x-point.y,-1.0,1.0) : 1;
}
float jewelHandLightGain(constant JewelUniforms &u) {
    // The moving focal point retains a daylight floor and strengthens at night.
    return 0.55+1.10*sqrt(saturate(u.lighting.x));
}
float3 jewelSurfaceEmission(JewelHit hit,float3 view,constant JewelUniforms &u) {
    if((hit.boundary&jewelEmissionFlag)==0) return float3(0);
    float facing=abs(dot(hit.normal,view));
    if(hit.material==18) return jewelEmissionRadiance(18)*jewelSourceGradient(18,hit.point)*(0.15+0.85*facing*facing*facing)*u.lighting.x;
    if(hit.material==19) {
        float2 local=jewelRotate(hit.point.xy,-u.sizeAndAngle.z);
        float along=clamp((-local.y-0.012)/0.339,0.0,1.0);
        float center=sin(along*2*jewelPi)*0.006;
        float across=abs(local.x-center)/0.0105;
        float shape=1-smoothstep(0.05,1.0,across);
        // Soft source shoulders keep the transmitted crown from becoming a
        // flat strip of clipped colour. The profile moves with the real hand.
        return jewelEmissionRadiance(19)*(0.18+0.82*shape*shape)*jewelHandLightGain(u);
    }
    if(hit.material==20) {
        float2 local=jewelRotate(hit.point.xy,-u.sizeAndAngle.z);
        float along=0.82+0.28*smoothstep(0.06,0.33,-local.y);
        return jewelEmissionRadiance(20)*along*(0.28+0.72*facing*facing*facing)*jewelHandLightGain(u);
    }
    if(hit.material==1 || hit.material==11)
        return float3(1.0,0.38,0.055)*(0.10+1.30*facing*facing*facing)*u.lighting.x;
    if(hit.material>=14 && hit.material<=16) return jewelEmissionRadiance(hit.material)*u.lighting.x;
    return float3(0);
}
float3 jewelLocalLight(texture3d<half> illumination,float3 point,constant JewelUniforms &u) {
    if(illumination.get_width()==1) return float3(0);
    return float3(illumination.sample(jewelFieldSampler,(point-jewelFieldMin)/(jewelFieldMax-jewelFieldMin)).rgb)*u.lighting.x;
}
float jewelSmith(float cosine, float alpha) {
    float c = max(cosine, 0.001);
    return 2 * c / (c + sqrt(alpha * alpha + (1 - alpha * alpha) * c * c));
}
float3 jewelSpecular(texture2d<half> photo, JewelHit hit, float3 view, float3 f0, float roughness, constant JewelUniforms &u,bool polishedGold=false) {
    float3 n = hit.normal;
    if (dot(n, view) < 0) n = -n;
    float3 tangent = normalize(abs(n.z) < 0.999 ? cross(float3(0, 0, 1), n) : float3(1, 0, 0));
    float3 bitangent = cross(n, tangent);
    float nv = max(0.001, dot(n, view));
    float alpha = roughness * roughness;
    if (roughness < 0.12) {
        // The polished lobe is narrower than the already filtered environment.
        // Its mirror-limit evaluation avoids eight nearly identical lookups
        // per metal edge and crystal interface while the view is being moved.
        float visibility=jewelSmith(nv,alpha);
        return jewelEnvironment(photo,hit.point,reflect(-view,n),roughness*2.5,u,polishedGold)
            *jewelSchlick(nv,f0)*visibility*visibility;
    }
    float3 total = 0;
    const float sequence[8] = {0.0625,0.5625,0.3125,0.8125,0.1875,0.6875,0.4375,0.9375};
    for (int i = 0; i < 8; ++i) {
        float xi = (float(i) + 0.5) / 8, phi = sequence[i] * 2 * jewelPi;
        float c = sqrt((1 - xi) / (1 + (alpha * alpha - 1) * xi));
        float s = sqrt(max(0.0, 1 - c * c));
        float3 h = normalize(tangent * cos(phi) * s + bitangent * sin(phi) * s + n * c);
        float3 direction = reflect(-view, h);
        float nl = dot(n, direction), vh = max(dot(view, h), 0.0);
        if (nl <= 0 || vh <= 0) continue;
        float weight = jewelSmith(nv, alpha) * jewelSmith(nl, alpha) * vh / max(dot(n, h) * nv, 0.001);
        total += jewelEnvironment(photo, hit.point, direction, roughness * 2.5, u) * jewelSchlick(vh, f0) * weight;
    }
    return total / 8;
}
float3 jewelGoldBase(texture2d<half> photo, JewelHit hit, float3 view, JEWEL_SCENE_ARGS) {
    float3 specular = jewelSpecular(photo, hit, view, (hit.material == 11 ? float3(0.16,0.06,0.016) : float3(1.0,0.74,0.30)), hit.material == 11 ? 0.26 : 0.075, u,hit.material!=11);
    float3 n = dot(hit.normal, view) > 0 ? hit.normal : -hit.normal;
    // Actual near-field visibility gives contact depth under claws and bezels.
    ray reflectionRay = jewelRay(hit.point + n * 0.00015, reflect(-view, n));
    JewelHit blocker = jewelIntersect(reflectionRay, JEWEL_SCENE);
    float visibility = blocker.valid && blocker.distance < 0.04 ? 0.60 : 1.0;
    float3 tint=hit.material==11 ? float3(0.16,0.06,0.016) : float3(1,0.67,0.21);
    return specular * visibility+jewelSurfaceEmission(hit,view,u)
        +jewelLocalLight(illumination,hit.point,u)*tint*(hit.material==11 ? 0.32 : 0.06);
}

float3 jewelEnamel(texture2d<half> photo, JewelHit hit, float3 view, constant JewelUniforms &u) {
    float3 illumination = jewelEnvironment(photo, hit.point, hit.normal, 4, u);
    float3 pigment = hit.material == 10 ? float3(0.005, 0.095, 0.12) : float3(0.004, 0.012, 0.022);
    float3 coating = jewelSpecular(photo, hit, view, float3(0.04), 0.21, u);
    // Opaque enamel provides the stable contrast; its coating still reflects
    // the background. No photographic detail is transmitted through the arm.
    return pigment * (0.60 + illumination * 0.50) + coating * 0.48;
}
float jewelHandShadow(float3 point, primitive_acceleration_structure hand, constant JewelUniforms &u, thread uint4 &handInfluence) {
    float2 local = jewelRotate(point.xy, -u.sizeAndAngle.z);
    if (u.cache.x!=1 && (abs(local.x) > 0.09 || local.y < -0.38 || local.y > 0.09)) return 0;
    intersector<triangle_data> query;
    query.assume_geometry_type(geometry_type::triangle);
    query.force_opacity(forced_opacity::opaque);
    float shadow = 0;
    for (int sample = 0; sample < 2; ++sample) {
        float spread = sample == 0 ? -0.06 : 0.06;
        ray light = jewelRay(point + float3(0, 0, 0.0003), float3(-0.16 + spread, -0.20 - spread, 1.0));
        light.max_distance = 0.3;
        if(u.cache.x==1) { handInfluence|=jewelHandRayMask(light,light.max_distance); continue; }
        light.origin.xy = jewelRotate(light.origin.xy, -u.sizeAndAngle.z);
        light.direction.xy = jewelRotate(light.direction.xy, -u.sizeAndAngle.z);
        auto hit = query.intersect(light, hand);
        if (hit.type != intersection_type::none) shadow += 0.5;
    }
    return shadow;
}

float jewelMountContact(float3 point, primitive_acceleration_structure body, device const uint *materials) {
    float radius=length(point.xy);
    float a=round(atan2(point.x,-point.y)/(jewelPi/6))*(jewelPi/6);
    float2 mount=float2(sin(a),-cos(a))*0.266;
    if(radius<0.312 && distance(point.xy,mount)>0.022) return 1;
    // A short ray only reaches the fixed setting, below the moving hand.
    // Glass is not treated as an opaque contact-shadow blocker.
    ray light=jewelRay(point+float3(0,0,0.0003),float3(-0.5,-0.65,0.8));
    light.max_distance=0.018;
    intersector<triangle_data> query;
    query.assume_geometry_type(geometry_type::triangle);
    query.force_opacity(forced_opacity::opaque);
    auto hit=query.intersect(light,body);
    if(hit.type==intersection_type::none) return 1;
    uint material=materials[hit.primitive_id]&255u;
    if(material!=1 && material!=11 && material!=8) return 1;
    return 1-0.18*(1-smoothstep(0.001,0.018,hit.distance));
}

float3 jewelOpalTint(JewelHit hit, float3 view) {
    float cosine=abs(dot(hit.normal,view));
    float transmitted=sqrt(max(0.0,1-(1-cosine*cosine)/(1.38*1.38)));
    // A smooth coating thickness varies with the carved crystal. Three visible
    // wavelengths give restrained, angle-dependent pearl colour without a map.
    float thickness=0.38+0.075*sin(hit.point.x*45+hit.point.y*18)
        +0.060*sin(hit.point.y*53-hit.point.x*15+hit.point.z*32);
    float3 phase=4*jewelPi*1.38*thickness*transmitted/float3(0.650,0.530,0.460);
    return 0.94+0.06*cos(phase);
}

float3 jewelCrystalScattering(texture2d<half> photo,JewelHit hit,float3 direction,constant JewelUniforms &u) {
    float3 n=dot(hit.normal,direction)<0 ? hit.normal : -hit.normal;
    // Opal redistributes transmitted light instead of replacing a bright
    // background with a dim, lossy reflection from the front of the clock.
    float3 transmitted=direction.z<-0.05 ? jewelTransmittedBackground(photo,hit.point,direction,u,5.5)
        : jewelPhotoEnvironment(photo,hit.point,direction,4,u);
    return transmitted*0.85+jewelPhotoEnvironment(photo,hit.point,n,4,u)*0.15;
}

float3 jewelPearl(JewelHit hit, float3 view, texture2d<half> photo,texture3d<half> illumination, constant JewelUniforms &u);

JewelMedia jewelStartingMedia(ray r,JewelHit hit) {
    JewelMedia media=jewelEmptyMedia();
    if(hit.valid && jewelTransparent(hit.material) && dot(r.direction,hit.geometricNormal)>0)
        jewelCrossMedium(media,hit.boundary,false);
    return media;
}
void jewelAbsorbSegment(float distance,JewelMedia media,JewelHit hit,float3 direction,
                        texture2d<half> photo,texture3d<half> illumination,constant JewelUniforms &u,
                        thread float3 &sum,thread float3 &throughput) {
    uint material=jewelMediumMaterial(media);
    if(material==0) return;
    float3 local=(jewelLocalLight(illumination,hit.point-direction*distance*0.25,u)
        +jewelLocalLight(illumination,hit.point-direction*distance*0.75,u))*0.5;
    if(material==2) {
        float scatter=1-exp(-distance*18.0);
        sum+=throughput*(jewelCrystalScattering(photo,hit,direction,u)+local)*scatter;
        throughput*=1-scatter;
    }
    bool colored=(material>=4 && material<=7) || material==12;
    if(colored) {
        float3 tint=material==4 ? float3(0.006,0.11,1.0)
            : material==5 ? float3(0.006,0.70,0.75)
            : material==6 ? float3(1.0,0.36,0.02)
            : material==12 ? float3(1.0,0.2,0.4) : float3(1.0,0.025,0.06);
        float scatter=0.018*(1-exp(-distance*40));
        float3 light=jewelEnvironment(photo,hit.point,normalize(float3(-0.2,-0.35,1)),4,u);
        sum+=throughput*(tint*light+local)*scatter;
        throughput*=1-scatter;
    }
    if(material==13) {
        float scatter=1-exp(-distance*0.20);
        sum+=throughput*local*scatter;throughput*=1-scatter;
    }
    throughput*=jewelTransmission(material,distance,u.sizeAndAngle.w);
}
float3 jewelEscapedLight(ray r,texture2d<half> photo,constant JewelUniforms &u,float blur,bool polishedGold=false) {
    return r.direction.z<0 ? jewelTransmittedBackground(photo,r.origin,r.direction,u,blur)
                           : jewelEnvironment(photo,r.origin,r.direction,0,u,polishedGold);
}
float3 jewelExitLightKnown(ray r,JewelHit firstHit,JewelMedia media,texture2d<half> photo,
                          JEWEL_SCENE_ARGS,float backgroundBlur,bool polishedGold=false) {
    float3 sum=0,throughput=1;
    // All transparent neighbours use their actual front/rear interfaces and
    // medium history, including differently coloured overlapping crystals.
    for(int boundary=0;boundary<8;++boundary) {
        JewelHit hit=boundary==0 ? firstHit : jewelIntersect(r,JEWEL_SCENE);
        if(!hit.valid) return sum+throughput*jewelEscapedLight(r,photo,u,backgroundBlur,polishedGold);
        jewelAbsorbSegment(hit.distance,media,hit,r.direction,photo,illumination,u,sum,throughput);
        if(jewelSourceMaterial(hit.material)) return sum+throughput*jewelSurfaceEmission(hit,-r.direction,u);
        if(jewelGoldMaterial(hit.material)) return sum+throughput*jewelGoldBase(photo,hit,-r.direction,JEWEL_SCENE);
        if(hit.material==9 || hit.material==10) return sum+throughput*jewelEnamel(photo,hit,-r.direction,u);
        if(hit.material==8) return sum+throughput*jewelPearl(hit,-r.direction,photo,illumination,u);
        JewelInterface crossing=jewelResolveInterface(media,hit.boundary,r.direction,hit.normal,hit.geometricNormal);
        if(!crossing.valid) return sum;
        if(crossing.fresnel>=0.99999) {
            r=jewelRay(hit.point+crossing.reflection*0.00012,crossing.reflection);
            continue;
        }
        float3 tint=(hit.material==2 || hit.material==13) ? jewelOpalTint(hit,-r.direction) : float3(1);
        sum+=throughput*jewelEnvironment(photo,hit.point,crossing.reflection,0,u,polishedGold)*crossing.fresnel*tint;
        throughput*=1-crossing.fresnel;
        media=crossing.after;
        if(hit.material==2) backgroundBlur=max(backgroundBlur,2.2);
        r=jewelRay(hit.point+crossing.transmission*0.00012,crossing.transmission);
        if(max(throughput.r,max(throughput.g,throughput.b))<0.002) return sum;
    }
    // Never project a still-trapped ray straight through an unvisited solid.
    return jewelMediumMaterial(media)==0 ? sum+throughput*jewelEscapedLight(r,photo,u,backgroundBlur,polishedGold) : sum;
}
float3 jewelExitLight(ray r,JewelMedia media,texture2d<half> photo,JEWEL_SCENE_ARGS,float backgroundBlur) {
    JewelHit first=jewelIntersect(r,JEWEL_SCENE);
    return jewelExitLightKnown(r,first,media,photo,JEWEL_SCENE,backgroundBlur);
}
float3 jewelGold(texture2d<half> photo, JewelHit hit, float3 view,JewelMedia media, JEWEL_SCENE_ARGS) {
    if(hit.material==11) return jewelGoldBase(photo,hit,view,JEWEL_SCENE);
    float3 n=dot(hit.normal,view)>0 ? hit.normal : -hit.normal;
    float3 direction=reflect(-view,n);
    ray mirror=jewelRay(hit.point+n*0.00016+direction*0.00008,direction);
    JewelHit nearby=jewelIntersect(mirror,JEWEL_SCENE);
    float3 emission=jewelSurfaceEmission(hit,view,u)+jewelLocalLight(illumination,hit.point,u)*float3(1,0.67,0.21)*0.06;
    if(!nearby.valid || nearby.distance>0.075) return jewelSpecular(photo,hit,view,float3(1.0,0.74,0.30),0.075,u,true)+emission;
    // Polished lips reflect the actual adjacent crystal, enamel arm and other
    // faces of the setting. A secondary metal hit uses the bounded base model,
    // so these near reflections cannot recurse indefinitely.
    float nv=max(dot(n,view),0.001);
    float visibility=jewelSmith(nv,0.075*0.075);
    return jewelExitLightKnown(mirror,nearby,media,photo,JEWEL_SCENE,0.5,true)
        *jewelSchlick(nv,float3(1.0,0.74,0.30))*visibility*visibility+emission;
}
float3 jewelPearl(JewelHit hit, float3 view, texture2d<half> photo,texture3d<half> illumination, constant JewelUniforms &u) {
    float3 n = hit.normal;
    float3 a = jewelEnvironment(photo, hit.point, n, 5, u);
    float3 b = jewelEnvironment(photo, hit.point, normalize(n + float3(-0.5, -0.5, 0.3)), 5, u);
    float3 c = jewelEnvironment(photo, hit.point, normalize(n + float3(0.5, 0.2, 0.2)), 5, u);
    float3 light = (a + b + c) / 3+jewelLocalLight(illumination,hit.point,u)*4;
    float phase = n.x * 5.1 + n.y * 7.2 + n.z * 2.4 + sin(n.x * 8 + n.y * 3) * 0.6 + dot(n,view)*2.8;
    float3 opal = 0.62 + 0.20 * cos(float3(0, 2.1, 4.2) + phase);
    return light * opal * 0.78
         + jewelSpecular(photo, hit, view, float3(0.09), 0.07, u);
}
float3 jewelTrace(ray r,JewelHit firstHit,texture2d<half> photo,JEWEL_SCENE_ARGS) {
    float3 sum=0,throughput=1;
    JewelMedia media=jewelStartingMedia(r,firstHit);
    for(int bounce=0;bounce<12;++bounce) {
        JewelHit hit=bounce==0 ? firstHit : jewelIntersect(r,JEWEL_SCENE);
        if(!hit.valid) {
            sum+=throughput*jewelEscapedLight(r,photo,u,0);
            break;
        }
        jewelAbsorbSegment(hit.distance,media,hit,r.direction,photo,illumination,u,sum,throughput);
        if(jewelSourceMaterial(hit.material)) { sum+=throughput*jewelSurfaceEmission(hit,-r.direction,u);break; }
        if(jewelGoldMaterial(hit.material)) { sum+=throughput*jewelGold(photo,hit,-r.direction,media,JEWEL_SCENE); break; }
        if(hit.material==9 || hit.material==10) { sum+=throughput*jewelEnamel(photo,hit,-r.direction,u); break; }
        if(hit.material==8) { sum+=throughput*jewelPearl(hit,-r.direction,photo,illumination,u); break; }
        JewelInterface crossing=jewelResolveInterface(media,hit.boundary,r.direction,hit.normal,hit.geometricNormal);
        if(!crossing.valid) break;
        bool exiting=dot(r.direction,hit.geometricNormal)>0;
        if(crossing.fresnel>=0.99999) {
            // Total internal reflection keeps the same active media.
            r=jewelRay(hit.point+crossing.reflection*0.00012,crossing.reflection);
        } else if(!exiting) {
            // Use the same energy cutoff before spawning a branch as after
            // continuing one. Very weak nested-interface reflections should
            // not each launch another full scene traversal.
            float reflectionWeight=max(throughput.r,max(throughput.g,throughput.b))*crossing.fresnel;
            if(u.camera.z<0.5 && reflectionWeight>=0.002) {
                ray mirror=jewelRay(hit.point+crossing.reflection*0.00016,crossing.reflection);
                float3 tint=(hit.material==2 || hit.material==13) ? jewelOpalTint(hit,-r.direction) : float3(1);
                sum+=throughput*crossing.fresnel*tint*jewelExitLight(mirror,media,photo,JEWEL_SCENE,0);
            }
            throughput*=1-crossing.fresnel;
            media=crossing.after;
            r=jewelRay(hit.point+crossing.transmission*0.00012,crossing.transmission);
        } else {
            ray escaped=jewelRay(hit.point+crossing.transmission*0.00012,crossing.transmission);
            float blur=hit.material==2 ? 2.2 : hit.material==13 ? 0.5 : 0;
            sum+=throughput*(1-crossing.fresnel)*jewelExitLight(escaped,crossing.after,photo,JEWEL_SCENE,blur);
            throughput*=crossing.fresnel;
            r=jewelRay(hit.point+crossing.reflection*0.00012,crossing.reflection);
        }
        if(max(throughput.r,max(throughput.g,throughput.b))<0.002) break;
    }
    return sum;
}
float3 jewelToneMap(float3 color) {
    // Preserve the display-linear background baseline. Only HDR highlights use
    // a shoulder; a clear straight-through path does not brighten by exposure.
    float3 x = max(color, 0.0);
    float peak=max(x.r,max(x.g,x.b));
    float mapped=peak>0.72 ? 0.72+0.28*(1-exp(-(peak-0.72)/0.28)) : peak;
    return x*(mapped/max(peak,0.000001));
}
vertex JewelRaster gemstoneRayVertex(uint id [[vertex_id]]) {
    const float2 uv[4] = {float2(0, 0), float2(0, 1), float2(1, 0), float2(1, 1)};
    JewelRaster out;
    out.position = float4(uv[id].x * 2 - 1, 1 - uv[id].y * 2, 0, 1); out.uv = uv[id]; return out;
}
half4 jewelRenderPixel(JewelRaster in, texture2d<half> photo, JEWEL_SCENE_ARGS) {
    float diameter = min(u.sizeAndAngle.x, u.sizeAndAngle.y);
    float3 eye = jewelEye(u);
    float3 result = 0;
    float coverage = 0;
    int samples=u.cache.x==0 ? 1 : 8;
    // A fixed rotated eight-point pattern resolves subpixel gold threads.
    // Interaction remains single-sampled; only settled/cached pixels use this.
    const float2 offsets[8]={float2(0.0625,-0.1875),float2(-0.0625,0.1875),
        float2(0.3125,0.0625),float2(-0.1875,-0.3125),float2(-0.3125,0.3125),
        float2(-0.4375,-0.0625),float2(0.1875,0.4375),float2(0.4375,-0.4375)};
    float2 resolution=max(float2(u.cache.zw),float2(1));
    for (int sample = 0; sample < samples; ++sample) {
        float2 offset=samples==1 ? float2(0) : offsets[sample];
        // Pixel-space offsets are identical in a full pass and in divergent
        // cached regions; screen derivatives inside a masked branch are not.
        float2 uv = (in.position.xy+offset)/resolution;
        float2 p = (uv * u.sizeAndAngle.xy - u.sizeAndAngle.xy * 0.5) / diameter;
        ray cameraRay = jewelRay(eye, float3(p, 0) - eye);
        JewelHit primary = jewelIntersect(cameraRay, JEWEL_SCENE);
        if (!primary.valid) continue;
        if (u.camera.z > 0.5 && u.camera.w > 2.5 && primary.material != 4) continue;
        if (u.camera.w > 3.5) result += jewelBackground(photo, cameraRay.origin, cameraRay.direction, u);
        else if (u.camera.w > 0.5 && u.camera.w < 1.5) result += primary.normal * 0.5 + 0.5;
        else if (u.camera.w > 1.5 && u.camera.w < 2.5) result += float3(primary.material) / 8;
        else {
            float3 radiance = jewelTrace(cameraRay, primary, photo, JEWEL_SCENE);
            if ((primary.material == 2 || primary.material == 13) && u.camera.w < 0.5) {
                radiance *= 1 - 0.16 * jewelHandShadow(primary.point, hand, u, handInfluence);
                radiance *= jewelMountContact(primary.point,body,bodyMaterials);
            }
            result += u.camera.w > 2.5 ? radiance : jewelToneMap(radiance);
        }
        coverage += 1;
    }
    return half4(half3(result/float(samples)),half(coverage/float(samples)));
}

#define JEWEL_FRAGMENT_ARGS JewelRaster in [[stage_in]], constant JewelUniforms &u [[buffer(0)]], \
    device const JewelVertex *bodyVertices [[buffer(1)]], device const uint *bodyMaterials [[buffer(2)]], \
    device const JewelVertex *handVertices [[buffer(3)]], device const uint *handMaterials [[buffer(4)]], \
    primitive_acceleration_structure body [[buffer(5)]], primitive_acceleration_structure hand [[buffer(6)]], \
    texture2d<half> photo [[texture(0)]], texture3d<half> illumination [[texture(3)]]

fragment half4 gemstoneRayFragment(JEWEL_FRAGMENT_ARGS) {
    uint4 handInfluence=0;
    return jewelRenderPixel(in,photo,JEWEL_SCENE);
}

struct JewelCachedPixel { half4 color [[color(0)]]; uint4 influence [[color(1)]]; };
fragment JewelCachedPixel gemstoneRayCacheFragment(JEWEL_FRAGMENT_ARGS) {
    uint4 handInfluence=0;
    half4 color=jewelRenderPixel(in,photo,JEWEL_SCENE);
    return {color,handInfluence};
}

fragment half4 gemstoneRayCompositeFragment(JEWEL_FRAGMENT_ARGS,
    texture2d<half,access::read> cachedColor [[texture(1)]],
    texture2d<uint,access::read> influence [[texture(2)]]) {
    uint2 pixel=uint2(in.position.xy);
    if(!any((influence.read(pixel) & u.visibility)!=0u)) return cachedColor.read(pixel);
    uint4 handInfluence=0;
    return jewelRenderPixel(in,photo,JEWEL_SCENE);
}

struct JewelPhotonTriangle { float4 a,b,c,normal; uint4 medium; };
uint jewelRandomBits(thread uint &state) {
    state^=state<<13;state^=state>>17;state^=state<<5;return state;
}
float jewelRandom(thread uint &state) { return (float(jewelRandomBits(state)>>8)+0.5)/16777216.0; }
JewelHit jewelPhotonHit(ray r,primitive_acceleration_structure body,
    device const JewelVertex *vertices,device const uint *materials) {
    intersector<triangle_data> query;
    query.assume_geometry_type(geometry_type::triangle);query.force_opacity(forced_opacity::opaque);
    auto a=query.intersect(r,body);
    JewelHit hit;hit.valid=a.type!=intersection_type::none;
    if(!hit.valid) return hit;
    uint i=a.primitive_id*3;
    float3 w=float3(1-a.triangle_barycentric_coord.x-a.triangle_barycentric_coord.y,a.triangle_barycentric_coord);
    hit.distance=a.distance;hit.point=r.origin+r.direction*a.distance;
    hit.normal=normalize(vertices[i].normal*w.x+vertices[i+1].normal*w.y+vertices[i+2].normal*w.z);
    hit.geometricNormal=normalize(cross(vertices[i+1].position-vertices[i].position,vertices[i+2].position-vertices[i].position));
    hit.boundary=materials[a.primitive_id];hit.material=hit.boundary&255u;return hit;
}
void jewelDeposit(device atomic_uint *field,float3 point,float3 energy) {
    float3 p=(point-jewelFieldMin)/(jewelFieldMax-jewelFieldMin)*float3(jewelFieldSize)-0.5;
    int3 base=int3(floor(p));float3 f=fract(p);
    for(int z=0;z<2;++z) for(int y=0;y<2;++y) for(int x=0;x<2;++x) {
        int3 cell=base+int3(x,y,z);
        if(any(cell<0) || any(cell>=int3(jewelFieldSize))) continue;
        float weight=(x ? f.x : 1-f.x)*(y ? f.y : 1-f.y)*(z ? f.z : 1-f.z);
        uint offset=(uint(cell.x)+jewelFieldSize.x*(uint(cell.y)+jewelFieldSize.y*uint(cell.z)))*3;
        uint3 add=uint3(max(float3(0),energy*weight*jewelPhotonScale)+0.5);
        atomic_fetch_add_explicit(field+offset,add.x,memory_order_relaxed);
        atomic_fetch_add_explicit(field+offset+1,add.y,memory_order_relaxed);
        atomic_fetch_add_explicit(field+offset+2,add.z,memory_order_relaxed);
    }
}
kernel void gemstonePhotonTrace(constant float4 &parameters [[buffer(0)]],
    device const JewelVertex *vertices [[buffer(1)]],device const uint *materials [[buffer(2)]],
    primitive_acceleration_structure body [[buffer(5)]],device const JewelPhotonTriangle *sources [[buffer(7)]],
    device atomic_uint *field [[buffer(8)]],uint index [[thread_position_in_grid]]) {
    uint random=(index+1u)*747796405u+2891336453u;
    float choice=jewelRandom(random);uint lo=0,hi=uint(parameters.y)-1;
    while(lo<hi) { uint middle=(lo+hi)/2;if(choice>sources[middle].a.w) lo=middle+1;else hi=middle; }
    JewelPhotonTriangle source=sources[lo];
    float a=sqrt(jewelRandom(random)),b=jewelRandom(random);
    float3 point=source.a.xyz*(1-a)+source.b.xyz*a*(1-b)+source.c.xyz*a*b;
    float3 n=normalize(source.normal.xyz),t=normalize(abs(n.z)<0.99 ? cross(float3(0,0,1),n) : float3(1,0,0));
    float azimuth=jewelRandom(random)*2*jewelPi,radius=sqrt(jewelRandom(random));
    float3 direction=t*(cos(azimuth)*radius)+cross(n,t)*(sin(azimuth)*radius)+n*sqrt(1-radius*radius);
    float3 color=jewelEmissionRadiance(uint(source.c.w))*jewelSourceGradient(uint(source.c.w),point);
    float3 energy=color*(parameters.z/(parameters.x*source.b.w));
    ray r=jewelRay(point+n*0.0002,direction);
    JewelMedia media=jewelEmptyMedia();if(source.medium.x!=0) jewelCrossMedium(media,source.medium.x,false);
    for(int bounce=0;bounce<12;++bounce) {
        JewelHit hit=jewelPhotonHit(r,body,vertices,materials);
        if(!hit.valid) break;
        uint medium=jewelMediumMaterial(media);
        if(medium!=0) {
            float fraction=jewelRandom(random);
            float3 attenuated=energy*jewelTransmission(medium,hit.distance*fraction,parameters.w);
            jewelDeposit(field,r.origin+r.direction*(hit.distance*fraction),attenuated*hit.distance);
            float scattering=medium==2 ? 18.0 : medium==13 ? 0.20 : 0.35;
            energy*=jewelTransmission(medium,hit.distance,parameters.w)*exp(-scattering*hit.distance);
        }
        if(jewelSourceMaterial(hit.material)) break;
        if(hit.material==9 || hit.material==10) break;
        if(jewelGoldMaterial(hit.material) || hit.material==8) {
            jewelDeposit(field,hit.point,energy*0.0084);
            if(!jewelGoldMaterial(hit.material)) break;
            float3 n=dot(r.direction,hit.normal)<0 ? hit.normal : -hit.normal;
            energy*=hit.material==11 ? float3(0.32,0.14,0.035) : float3(0.95,0.67,0.21);
            r=jewelRay(hit.point+n*0.0002,reflect(r.direction,n));
        } else {
            JewelInterface crossing=jewelResolveInterface(media,hit.boundary,r.direction,hit.normal,hit.geometricNormal);
            if(!crossing.valid) break;
            if(jewelRandom(random)<crossing.fresnel) r=jewelRay(hit.point+crossing.reflection*0.0002,crossing.reflection);
            else { media=crossing.after;r=jewelRay(hit.point+crossing.transmission*0.0002,crossing.transmission); }
        }
        if(max(energy.r,max(energy.g,energy.b))<0.00000001) break;
    }
}
kernel void gemstonePhotonResolve(device const uint *field [[buffer(0)]],
    texture3d<half,access::write> output [[texture(0)]],uint3 cell [[thread_position_in_grid]]) {
    float3 sum=0;
    for(int z=-1;z<=1;++z) for(int y=-1;y<=1;++y) for(int x=-1;x<=1;++x) {
        int3 p=int3(cell)+int3(x,y,z);
        if(any(p<0) || any(p>=int3(jewelFieldSize))) continue;
        uint offset=(uint(p.x)+jewelFieldSize.x*(uint(p.y)+jewelFieldSize.y*uint(p.z)))*3;
        float weight=float((x==0 ? 2 : 1)*(y==0 ? 2 : 1)*(z==0 ? 2 : 1));
        sum+=float3(field[offset],field[offset+1],field[offset+2])*weight;
    }
    float3 spacing=(jewelFieldMax-jewelFieldMin)/float3(jewelFieldSize);
    float volume=spacing.x*spacing.y*spacing.z;
    output.write(half4(half3(min(float3(128),sum/(64*jewelPhotonScale*volume*4*jewelPi))),0),cell);
}
