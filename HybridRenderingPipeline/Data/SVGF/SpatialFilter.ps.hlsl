import Shading;
import MathHelpers;
import SVGFCommon;

Texture2D         gLinearZAndNormal;
Texture2D<float4> gReflection;
Texture2D<float4> gBRDFOverPDF;
RWTexture2D<float> gVariance;


float4 main(FullScreenPassVsOut vsOut) : SV_TARGET0
{
    float4 posH = vsOut.posH;
    int2 ipos = int2(posH.xy);
    int2 screenSize = getTextureDims(gReflection, 0);

    // float sumWIllumination = 0.0;
    // float3 sumIllumination = float3(0.0, 0.0, 0.0);
    // float2 sumMoments = float2(0.0, 0.0);

    const float4 colorCenter = gReflection[ipos];
    const float2 zCenter = gLinearZAndNormal[ipos].xy;

    if (zCenter.x < 0)
    {
        // current pixel does not a valid depth => must be envmap => do nothing
        return colorCenter;
    }
    float3 sumColor = float3(0.0, 0.0, 0.0);
    float3 sumWeight = float3(0.0, 0.0, 0.0);
    // const float3 nCenter = oct_to_ndir_snorm(gLinearZAndNormal[ipos].zw);
    // const float phiLIllumination = gPhiColor;
    // const float phiDepth = max(zCenter.y, 1e-8) * 3.0;

    // compute first and second moment spatially. This code also applies cross-bilateral
    // filtering on the input illumination.
    const int radius = 2;

    for (int yy = -radius; yy <= radius; yy++)
    {
        for (int xx = -radius; xx <= radius; xx++)
        {
            const int2 p = ipos + int2(xx, yy);
            const bool inside = all(p >= int2(0,0)) && all(p < screenSize);

            if (inside)
            {
                float3 weight = gBRDFOverPDF[p].rgb;
                float3 r = gReflection[p].rgb;
                bool colorsNan = any(isnan(r));
                if (colorsNan) continue;
                sumColor += weight * gReflection[p].rgb;
                sumWeight += weight;
            }
        }
    }
    // Clamp sum to >0 to avoid NaNs.
    sumWeight = max(sumWeight, float3(1e-6f));
    sumColor /= sumWeight;
    return float4(sumColor.rgb, 1.f);
}