#pragma once
#include <metal_stdlib>
using namespace metal;

// A compact ordered set of active solids. The most recently entered solid
// supplies the current medium; removing a lower layer preserves the top one.
// Four overlapping optical bodies cover the fitted dial's layer stack.
struct JewelMedia { uint4 layers; uint count; };
constant uint jewelEmissionFlag=0x80000000u;
uint jewelOpticalObject(uint boundary) { return (boundary & ~jewelEmissionFlag)>>8; }
JewelMedia jewelEmptyMedia() { JewelMedia s; s.layers=uint4(0); s.count=0; return s; }
uint jewelMediumMaterial(JewelMedia s) { return s.count==0 ? 0 : s.layers[s.count-1]&255u; }
bool jewelMediumEmissive(JewelMedia s) { return s.count>0 && (s.layers[s.count-1]&jewelEmissionFlag)!=0; }
bool jewelTransparent(uint material) { return (material>=2 && material<=7) || material==12 || material==13; }
bool jewelGoldMaterial(uint material) { return material==1 || material==11 || material==18 || material==20; }
bool jewelSourceMaterial(uint material) { return (material>=14 && material<=17) || material==19; }
float jewelIOR(uint material) {
    return material==0 ? 1.0 : material==4 ? 1.76 : material==2 ? 1.46 : material==13 ? 1.62 : 1.60;
}
float jewelMediumIOR(JewelMedia s) { return jewelIOR(jewelMediumMaterial(s)); }
bool jewelCrossMedium(thread JewelMedia &s, uint boundary, bool exiting) {
    uint object=jewelOpticalObject(boundary);
    uint found=s.count;
    for(uint i=0;i<s.count;++i) if(jewelOpticalObject(s.layers[i])==object) { found=i; break; }
    if(exiting) {
        if(found<s.count) {
            for(uint i=found;i+1<s.count;++i) s.layers[i]=s.layers[i+1];
            s.layers[--s.count]=0;
        }
        return true;
    }
    if(found<s.count) return true;
    if(s.count==4 || object==0) return false;
    s.layers[s.count++]=boundary;
    return true;
}
float3 jewelAbsorption(uint material) {
    if(material==4) return float3(18.0,6.5,2.4);
    if(material==5) return float3(15.0,2.5,2.25);
    if(material==6) return float3(0.15,1.8,6.5);
    if(material==7) return float3(0.20,8.0,7.0);
    if(material==12) return float3(0.20,4.2,2.0);
    if(material==2 || material==13) return float3(0.20,0.09,0.05);
    return material==0 ? float3(0) : float3(0.08,0.05,0.025);
}
float3 jewelTransmission(uint material,float distance,float pigmentDensity) {
    bool colored=(material>=4 && material<=7) || material==12;
    return exp(-jewelAbsorption(material)*max(0.0,distance)*(colored ? pigmentDensity : 1.0));
}
float jewelFresnel(float cosine,float from,float to) {
    if(abs(from-to)<0.000001) return 0;
    cosine=clamp(cosine,0.0,1.0);
    float sinTransmitted2=(from*from)/(to*to)*max(0.0,1-cosine*cosine);
    if(sinTransmitted2>=1) return 1;
    float transmittedCosine=sqrt(1-sinTransmitted2);
    float rs=(from*cosine-to*transmittedCosine)/max(0.0000001,from*cosine+to*transmittedCosine);
    float rp=(to*cosine-from*transmittedCosine)/max(0.0000001,to*cosine+from*transmittedCosine);
    return (rs*rs+rp*rp)*0.5;
}

struct JewelInterface {
    JewelMedia after;
    float3 reflection;
    float3 transmission;
    float fresnel;
    bool valid;
};
JewelInterface jewelResolveInterface(JewelMedia before,uint boundary,float3 direction,
                                     float3 smoothNormal,float3 geometricNormal) {
    bool exiting=dot(direction,geometricNormal)>0;
    JewelInterface result;
    result.after=before;
    result.valid=jewelCrossMedium(result.after,boundary,exiting);
    float from=jewelMediumIOR(before),to=jewelMediumIOR(result.after);
    float3 n=dot(direction,smoothNormal)<0 ? smoothNormal : -smoothNormal;
    result.transmission=refract(direction,n,from/to);
    // Interpolated normals must not bend a ray onto the wrong geometric side.
    // Fall back to the actual interface orientation in that narrow case.
    float3 reflected=reflect(direction,n);
    bool wrongReflection=(dot(reflected,geometricNormal)>0)==exiting;
    if(wrongReflection || (dot(result.transmission,result.transmission)>0.01 &&
       ((dot(result.transmission,geometricNormal)>0)!=exiting))) {
        n=exiting ? -geometricNormal : geometricNormal;
        result.transmission=refract(direction,n,from/to);
    }
    result.reflection=reflect(direction,n);
    result.fresnel=jewelFresnel(saturate(dot(-direction,n)),from,to);
    if(result.fresnel>=0.99999 || dot(result.transmission,result.transmission)<0.01) {
        result.after=before;
        result.transmission=float3(0);
        result.fresnel=1;
    }
    return result;
}
