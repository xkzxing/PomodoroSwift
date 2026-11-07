#include "../../PomodoroSwift/Shaders/GemstoneRayTracing.metal"

// Sweep a curved metal surface under one view, then move the view. Bright
// regions must follow reflected directions and the photograph's radiance.
kernel void gemstoneGoldHighlightCases(texture2d<half> photo [[texture(0)]],
    device float4 *out [[buffer(0)]],constant JewelUniforms &u [[buffer(1)]],
    uint index [[thread_position_in_grid]]) {
    float angle=float(index%32)*2*jewelPi/32;
    float z=(float(index/32)+0.5)/32;
    float radius=sqrt(1-z*z);
    JewelHit hit;
    hit.point=float3(0);hit.normal=float3(radius*cos(angle),radius*sin(angle),z);
    hit.geometricNormal=hit.normal;hit.material=1;hit.boundary=1;hit.valid=true;
    float3 view=float3(0,0,1),f0=float3(1,0.74,0.30);
    out[index*3]=float4(jewelSpecular(photo,hit,view,f0,0.075,u,true),1);
    out[index*3+1]=float4(jewelSpecular(photo,hit,view,f0,0.075,u),1);
    out[index*3+2]=float4(jewelSpecular(photo,hit,normalize(float3(0.25,0.10,1)),f0,0.075,u,true),1);
}

kernel void gemstoneGoldSourceCases(constant JewelUniforms &u [[buffer(0)]],
    device float4 *out [[buffer(7)]],uint index [[thread_position_in_grid]]) {
    JewelHit hit;hit.point=float3(0);hit.normal=float3(0,0,1);hit.material=18;hit.boundary=18|jewelEmissionFlag;
    float facing=float(index)/31;
    float3 view=float3(sqrt(1-facing*facing),0,facing);
    out[index]=float4(jewelSurfaceEmission(hit,view,u),jewelGoldMaterial(18) && !jewelTransparent(18) ? 1 : 0);
}

kernel void gemstoneHandPriorityCases(constant JewelUniforms &u [[buffer(0)]],
    device float4 *out [[buffer(7)]],uint index [[thread_position_in_grid]]) {
    JewelHit hit;hit.point=float3(index==0 ? -0.006 : 0,-0.25,0.11);hit.normal=float3(0,0,1);
    hit.material=index==0 ? 19 : 20;hit.boundary=hit.material|jewelEmissionFlag;
    out[index]=float4(jewelSurfaceEmission(hit,float3(0,0,1),u),jewelHandLightGain(u));
}

kernel void gemstoneGoldGradientCases(constant JewelUniforms &u [[buffer(0)]],
    device float4 *out [[buffer(7)]],uint index [[thread_position_in_grid]]) {
    float t=float(index)/64;
    float3 point=mix(float3(-0.35,-0.35,0),float3(0.35,0.35,0),t);
    out[index]=float4(jewelEmissionRadiance(18)*jewelSourceGradient(18,point),1);
}

kernel void gemstonePhotoReflectionCases(texture2d<half> photo [[texture(0)]],
    device float4 *out [[buffer(0)]],constant JewelUniforms &u [[buffer(1)]],
    uint index [[thread_position_in_grid]]) {
    float angle=float(index)*2*jewelPi/256;
    float3 direction=normalize(float3(cos(angle),sin(angle),float(int(index%9)-4)*0.25));
    float3 point=float3(0.8*sin(angle*3),0.65*cos(angle*2),0.05);
    float lod=float(index%4)*0.25;
    out[index*2]=float4(jewelEnvironment(photo,point,direction,lod,u),1);
    out[index*2+1]=float4(jewelEnvironment(photo,point+float3(0.13,0,0),direction,lod,u),1);
}

// Uniform illumination must remain luminous after travelling through clear or
// opal layers. This also catches a dark reflection replacing forward scatter.
kernel void gemstoneTransmissionLiftCases(constant JewelUniforms &u [[buffer(0)]],
    device float4 *out [[buffer(7)]],uint index [[thread_position_in_grid]]) {
    float3 color=index<=256 ? float3(float(index)/256)
        : index==257 ? float3(0.18) : index==258 ? float3(0.02,0.1,0.25) : float3(0.3,0.08,0.02);
    out[index]=float4(jewelLiftTransmission(color,u.lighting.y),dot(color,float3(0.2126,0.7152,0.0722)));
}

kernel void gemstoneBackdropTransmissionCases(constant JewelUniforms &u [[buffer(0)]],
    texture2d<half> photo [[texture(0)]],texture3d<half> illumination [[texture(3)]],
    device float4 *out [[buffer(7)]],uint index [[thread_position_in_grid]]) {
    const uint materials[4]={2,3,4,5};
    const float distances[4]={0.005,0.015,0.03,0.08};
    uint material=materials[index/4];float distance=distances[index%4];
    JewelHit hit;
    hit.valid=true;hit.point=float3(0);hit.normal=float3(0,0,1);
    hit.geometricNormal=hit.normal;hit.distance=distance;hit.material=material;hit.boundary=(1u<<8)|material;
    JewelMedia media=jewelEmptyMedia();jewelCrossMedium(media,hit.boundary,false);
    float3 color=0,throughput=1;
    jewelAbsorbSegment(distance,media,hit,float3(0,0,-1),photo,illumination,u,color,throughput);
    float3 background=float3(photo.sample(jewelPhoto,float2(0.5),level(0)).rgb);
    out[index]=float4(color+throughput*background,float(material));
}

kernel void gemstoneBoundaryCases(device float4 *out [[buffer(0)]],uint index [[thread_position_in_grid]]) {
    if(index!=0) return;
    JewelMedia s=jewelEmptyMedia();
    float3 direction=float3(0.5,0,-sqrt(0.75));
    const uint objects[4]={(1u<<8)|13u,(2u<<8)|4u,(2u<<8)|4u,(1u<<8)|13u};
    for(uint i=0;i<4;++i) {
        float3 n=i<2 ? float3(0,0,1) : float3(0,0,-1);
        JewelInterface step=jewelResolveInterface(s,objects[i],direction,n,n);
        s=step.after;direction=step.transmission;
        out[i]=float4(direction,jewelMediumIOR(s));
    }
    out[4]=float4(jewelTransmission(13,0.03,4.8)*jewelTransmission(4,0.04,4.8),float(s.count));
    s=jewelEmptyMedia();
    jewelCrossMedium(s,(11u<<8)|4u,false);
    JewelInterface same=jewelResolveInterface(s,(12u<<8)|4u,float3(0,0,-1),float3(0,0,1),float3(0,0,1));
    s=same.after;
    out[5]=float4(same.fresnel,jewelMediumIOR(s),float(s.count),float(s.layers[s.count-1]>>8));
    JewelInterface underneath=jewelResolveInterface(s,(11u<<8)|4u,float3(0,0,-1),float3(0,0,-1),float3(0,0,-1));
    out[7]=float4(jewelMediumIOR(underneath.after),float(underneath.after.count),float(underneath.after.layers[0]>>8),underneath.fresnel);
    JewelInterface tir=jewelResolveInterface(underneath.after,(12u<<8)|4u,float3(0.9,0,sqrt(0.19)),float3(0,0,1),float3(0,0,1));
    out[6]=float4(tir.fresnel,length(tir.transmission),float(tir.after.count),tir.reflection.z);
    s=jewelEmptyMedia();
    for(uint i=1;i<=4;++i) jewelCrossMedium(s,(i<<8)|3u,false);
    bool accepted=jewelCrossMedium(s,(5u<<8)|4u,false);
    out[8]=float4(jewelFresnel(0,1.62,1.62),jewelFresnel(1,1,1.76),float(accepted),float(s.count));
    out[9]=float4(jewelTransmission(5,0.02,4.8),1);
    out[10]=float4(jewelTransmission(5,0.16,4.8),1);
    s=jewelEmptyMedia();
    uint glowing=(88u<<8)|5u|jewelEmissionFlag;
    jewelCrossMedium(s,glowing,false);
    jewelCrossMedium(s,glowing&~jewelEmissionFlag,false);
    float3 state=float3(float(s.count),jewelMediumEmissive(s) ? 1 : 0,float(jewelOpticalObject(s.layers[0])));
    jewelCrossMedium(s,glowing&~jewelEmissionFlag,true);
    out[11]=float4(state,float(s.count));
    JewelInterface grazing=jewelResolveInterface(jewelEmptyMedia(),(9u<<8)|4u,
        float3(0.1,0,-sqrt(0.99)),float3(0.7,0,sqrt(0.51)),float3(0,0,1));
    out[12]=float4(grazing.reflection.z,grazing.transmission.z,jewelMediumIOR(grazing.after),grazing.valid ? 1 : 0);
    s=jewelEmptyMedia();
    uint fixed=(2u<<8)|5u,moving=(0x00400002u<<8)|5u;
    jewelCrossMedium(s,fixed,false);jewelCrossMedium(s,moving,false);
    float together=float(s.count);
    jewelCrossMedium(s,fixed,true);
    float remaining=float(s.count),identity=float(jewelOpticalObject(s.layers[0]));
    jewelCrossMedium(s,moving,true);
    out[13]=float4(together,remaining,identity,float(s.count));
}

kernel void gemstoneEmbeddedLightCases(
    constant JewelUniforms &u [[buffer(0)]],
    device const JewelVertex *bodyVertices [[buffer(1)]],device const uint *bodyMaterials [[buffer(2)]],
    device const JewelVertex *handVertices [[buffer(3)]],device const uint *handMaterials [[buffer(4)]],
    primitive_acceleration_structure body [[buffer(5)]],primitive_acceleration_structure hand [[buffer(6)]],
    texture2d<half> photo [[texture(0)]],texture3d<half> illumination [[texture(3)]],device float4 *out [[buffer(7)]],uint index [[thread_position_in_grid]]) {
    uint4 handInfluence=0;
    float2 target=float2(-0.17+float(index%32)*0.34/31,-0.12+float(index/32)*0.24/31);
    ray r=jewelRay(float3(target,0.4),float3(0,0,-1));
    JewelHit first=jewelIntersect(r,JEWEL_SCENE);
    out[index]=float4(jewelTrace(r,first,photo,JEWEL_SCENE),1);
}

kernel void gemstonePassiveLightCases(
    constant JewelUniforms &u [[buffer(0)]],
    device const JewelVertex *bodyVertices [[buffer(1)]],device const uint *bodyMaterials [[buffer(2)]],
    device const JewelVertex *handVertices [[buffer(3)]],device const uint *handMaterials [[buffer(4)]],
    primitive_acceleration_structure body [[buffer(5)]],primitive_acceleration_structure hand [[buffer(6)]],
    texture2d<half> photo [[texture(0)]],texture3d<half> illumination [[texture(3)]],
    device float4 *out [[buffer(7)]],uint index [[thread_position_in_grid]]) {
    uint4 handInfluence=0;
    float2 target=float2(0.025+float(index%32)*0.19/31,-0.12+float(index/32)*0.24/31);
    ray r=jewelRay(float3(target,0.4),float3(0,0,-1));
    JewelHit first=jewelIntersect(r,JEWEL_SCENE);
    out[index]=float4(jewelTrace(r,first,photo,JEWEL_SCENE),1);
}

kernel void gemstoneFieldProbeCases(texture3d<half> illumination [[texture(3)]],
    device float4 *out [[buffer(0)]],uint index [[thread_position_in_grid]]) {
    float3 point=float3(0.035+float(index%16)*0.17/15,-0.10+float((index/16)%8)*0.20/7,
        -0.035+float(index/128)*0.12/7);
    out[index]=float4(float3(illumination.sample(jewelFieldSampler,(point-jewelFieldMin)/(jewelFieldMax-jewelFieldMin)).rgb),1);
}

// Independent single-stone reference: enter once, continue reflecting only
// when refraction is impossible, and return the first escape direction.
// This is the escape-path baseline used by Drei's MeshRefractionMaterial.
// Source and MIT notice: OpticalReference.md. The benchmark uses geometric
// normals on both sides so it compares transport rather than smooth shading.
float4 gemstoneReferenceEscape(ray r,JEWEL_SCENE_ARGS) {
    JewelHit first=jewelIntersect(r,JEWEL_SCENE);
    if(!first.valid) return float4(0);
    float ior=jewelIOR(first.material);
    float3 direction=refract(r.direction,first.geometricNormal,1/ior);
    r=jewelRay(first.point+direction*0.00012,direction);
    for(uint bounce=0;bounce<12;++bounce) {
        JewelHit hit=jewelIntersect(r,JEWEL_SCENE);
        if(!hit.valid) return float4(r.direction,1);
        float3 n=dot(r.direction,hit.geometricNormal)<0 ? hit.geometricNormal : -hit.geometricNormal;
        float3 escape=refract(r.direction,n,ior);
        if(dot(escape,escape)>0.01) return float4(escape,1);
        direction=reflect(r.direction,n);
        r=jewelRay(hit.point+direction*0.00012,direction);
    }
    return float4(0,0,0,-1);
}

kernel void gemstoneSingleStoneCases(
    constant JewelUniforms &u [[buffer(0)]],
    device const JewelVertex *bodyVertices [[buffer(1)]],device const uint *bodyMaterials [[buffer(2)]],
    device const JewelVertex *handVertices [[buffer(3)]],device const uint *handMaterials [[buffer(4)]],
    primitive_acceleration_structure body [[buffer(5)]],primitive_acceleration_structure hand [[buffer(6)]],
    texture3d<half> illumination [[texture(3)]],device float4 *out [[buffer(7)]],uint index [[thread_position_in_grid]]) {
    uint4 handInfluence=0;
    float2 position=float2(-0.047+float(index%8)*0.0134,-0.475+float(index/8)*0.019);
    ray r=jewelRay(float3(position,0.4),float3(0.04,-0.025,-1));
    out[index*2]=gemstoneReferenceEscape(r,JEWEL_SCENE);
    JewelMedia media=jewelEmptyMedia();
    out[index*2+1]=float4(0);
    for(uint bounce=0;bounce<13;++bounce) {
        JewelHit hit=jewelIntersect(r,JEWEL_SCENE);
        if(!hit.valid) break;
        JewelInterface step=jewelResolveInterface(media,hit.boundary,r.direction,hit.geometricNormal,hit.geometricNormal);
        if(!step.valid) { out[index*2+1]=float4(0,0,0,-2); break; }
        bool escaped=media.count>0 && step.after.count==0;
        media=step.after;
        float3 direction=step.fresnel>=0.99999 ? step.reflection : step.transmission;
        if(escaped) { out[index*2+1]=float4(direction,1); break; }
        out[index*2+1]=float4(0,0,0,-1);
        r=jewelRay(hit.point+direction*0.00012,direction);
    }
}

// Check the conservative cache mask against real hand geometry around every
// angular-bin boundary. Each ray/angle pair gets an independent BVH query.
kernel void gemstoneHandVisibilityCases(
    primitive_acceleration_structure hand [[buffer(6)]],
    device float4 *out [[buffer(7)]],uint index [[thread_position_in_grid]]) {
    uint rayIndex=index/256,angleIndex=index%256;
    float angle=(float(angleIndex/2)*360/128+(angleIndex%2==0 ? -0.0001 : 0.0001))*jewelPi/180;
    const float radii[8]={0.014,0.03,0.07,0.13,0.20,0.26,0.32,0.35};
    float azimuth=float(rayIndex%64)*2*jewelPi/64;
    float3 target=float3(float2(sin(azimuth),-cos(azimuth))*radii[rayIndex/64],0.10);
    float3 direction=normalize(float3(0.6*sin(azimuth*3),0.45*cos(azimuth*2),-1));
    ray r=jewelRay(target-direction*(0.08/-direction.z),direction);
    r.max_distance=0.25;
    uint4 mask=jewelHandRayMask(r,r.max_distance);
    r.origin.xy=jewelRotate(r.origin.xy,-angle);
    r.direction.xy=jewelRotate(r.direction.xy,-angle);
    intersector<triangle_data> query;
    query.assume_geometry_type(geometry_type::triangle);
    query.force_opacity(forced_opacity::opaque);
    auto hit=query.intersect(r,hand);
    uint bin=angleIndex%2==0 ? (angleIndex/2+127)%128 : angleIndex/2;
    bool missed=hit.type!=intersection_type::none && (mask[bin/32] & (1u<<(bin%32)))==0;
    out[index]=float4(missed ? 1 : 0,hit.type!=intersection_type::none ? 1 : 0,float(rayIndex),float(angleIndex));
}
