/**********************************************************************************************************************
# Copyright (c) 2018, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
# following conditions are met:
#  * Redistributions of code must retain the copyright notice, this list of conditions and the following disclaimer.
#  * Neither the name of NVIDIA CORPORATION nor the names of its contributors may be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT
# SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
# OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**********************************************************************************************************************/

#include "HostDeviceSharedMacros.h"

// Include and import common Falcor utilities and data structures
__import Raytracing;
__import ShaderCommon;
__import Shading;                      // Shading functions, etc
__import Lights;                       // Light structures for our current scene

// A separate file with some simple utility functions: getPerpendicularVector(), initRand(), nextRand()
#include "commonUtils.hlsli"
#include "halton.hlsli"

// Payload for our primary rays.  We really don't use this for this g-buffer pass
struct ReflectRayPayload
{
	float4 reflectColor;
	uint rndSeed;
};

// A constant buffer we'll fill in for our ray generation shader
cbuffer RayGenCB
{
	uint  gFrameCount;
	float gMinT;
	bool gReverseRoughness;
}

// Input and out textures that need to be set by the C++ code
Texture2D<float4> gPos;
Texture2D<float4> gNorm;
Texture2D<float4> gDiffuseMatl;
Texture2D<float4> gSpecMatl;
Texture2D<float4>   gExtraMatl;
Texture2D<float4>   gShadow;
RWTexture2D<float4> gOutput;

#include "standardShadowRay.hlsli"

[shader("miss")]
void ReflectMiss(inout ReflectRayPayload hitData : SV_RayPayload)
{
	gOutput[DispatchRaysIndex().xy] = float4(0, 0, 0, 1.0f);
}

[shader("anyhit")]
void ReflectAnyHit(inout ReflectRayPayload rayData, BuiltInTriangleIntersectionAttributes attribs)
{
	// Is this a transparent part of the surface?  If so, ignore this hit
	if (alphaTestFails(attribs))
		IgnoreHit();

}

[shader("closesthit")]
void ReflectClosestHit(inout ReflectRayPayload rayData, BuiltInTriangleIntersectionAttributes attribs)
{
	ShadingData shadeData = getShadingData(PrimitiveIndex(), attribs);
	rayData.reflectColor = float4(shadeData.emissive.rgb, 1);
	// Direct Shade
	float3 hit = shadeData.posW;
	float3 N = shadeData.N;
	float3 V = shadeData.V;
	float3 dif = shadeData.diffuse;
	float3 spec = shadeData.specular;
	float rough = shadeData.roughness;

	int lightToSample = min(int(nextRand(rayData.rndSeed) * gLightsCount), gLightsCount - 1);
	// Query the scene to find info about the randomly selected light
	float distToLight;
	float3 lightIntensity;
	float3 L;
	getLightData(lightToSample, hit, L, lightIntensity, distToLight);
	float NdotL = saturate(dot(N, L));
	float shadowMult = float(gLightsCount) * shadowRayVisibility(hit, L, gMinT, distToLight);
	shadowMult = max(shadowMult, 0.05);

	// Compute half vectors and additional dot products for GGX
	float3 H = normalize(V + L);
	float NdotH = saturate(dot(N, H));
	float LdotH = saturate(dot(L, H));
	float NdotV = saturate(dot(N, V));

	// Evaluate terms for our GGX BRDF model
	float  D = ggxNormalDistribution(NdotH, rough);
	float  G = ggxSchlickMaskingTerm(NdotL, NdotV, rough);
	float3 F = schlickFresnel(spec, LdotH);

	// Evaluate the Cook-Torrance Microfacet BRDF model
	//     Cancel out NdotL here & the next eq. to avoid catastrophic numerical precision issues.
	float3 ggxTerm = D * G * F / (4 * NdotV /* * NdotL */);

	// Compute our final color (combining diffuse lobe plus specular GGX lobe)
	rayData.reflectColor += float4(shadowMult * lightIntensity * ( /* NdotL * */ ggxTerm + NdotL * dif / PI), 1);
}


[shader("raygeneration")]
void ReflectRayGen()
{
	// Where is this ray on screen?
	uint2 launchIndex = DispatchRaysIndex().xy;
	uint2 launchDim = DispatchRaysDimensions().xy;

	// Initialize random seed per sample based on a screen position and temporally varying count
	uint randSeed = initRand(launchIndex.x + launchIndex.y * launchDim.x, gFrameCount, 16);

	// Load the position and normal from our g-buffer
	float4 worldPos = gPos[launchIndex];
	float4 worldNorm = gNorm[launchIndex];
	float4 diffuse = gDiffuseMatl[launchIndex];
	float4 specular = gSpecMatl[launchIndex];
	float roughness = gSpecMatl[launchIndex].w;
	float4 extraData = gExtraMatl[launchIndex];
	float4 shadow = gNorm[launchIndex];

	float3 V = normalize(gCamera.posW - worldPos.xyz);
	float3 N = worldNorm.xyz;
	if (gReverseRoughness)
	{
		roughness = 1 - roughness;
		specular = float4(roughness, roughness, roughness, roughness);
	}

	// Make sure our normal is pointed the right direction
	if (dot(N, V) <= 0.0f) N = -N;
	float NdotV = dot(N, V);

	bool isGeometryValid = (worldPos.w != 0.0f);
	float3 shadeColor = isGeometryValid ? float3(0, 0, 0) : diffuse.rgb;

	if (isGeometryValid)
	{
		HaltonState hState;
		haltonInit(hState, launchIndex.x, launchIndex.y, 1, 1, gFrameCount, 1);
		uint randSeed = initRand(launchIndex.x + launchIndex.y * launchDim.x, gFrameCount, 16);
		float rnd1 = frac(haltonNext(hState) + nextRand(randSeed));
		float rnd2 = frac(haltonNext(hState) + nextRand(randSeed));
		float2 Xi = float2(rnd1, rnd2);
		float3 H = ImportanceSampleGGX(Xi, N, roughness);
		float3 L = normalize(2.0 * dot(V, H) * H - V);

		RayDesc rayReflect;
		rayReflect.Origin = worldPos.xyz;
		rayReflect.Direction = L;
		rayReflect.TMin = gMinT;
		rayReflect.TMax = 1e+38f;
		ReflectRayPayload rayPayload = { float4(0, 0, 0, 1), randSeed };
		TraceRay(gRtScene, RAY_FLAG_NONE, 0xFF, 0, hitProgramCount, 0, rayReflect, rayPayload);


		// Grab our geometric normal.
		float3 geoN = normalize(extraData.yzw);
		if (dot(geoN, V) <= 0.0f) geoN = -geoN;

		float3 bounceColor = rayPayload.reflectColor.xyz;
		if (dot(geoN, L) <= 0.0f) bounceColor = float3(0, 0, 0);

		// Compute some dot products needed for shading
		float  NdotL = saturate(dot(N, L));
		float  NdotH = saturate(dot(N, H));
		float  LdotH = saturate(dot(L, H));

		// Evaluate our BRDF using a microfacet BRDF model
		float  D = ggxNormalDistribution(NdotH, roughness);          // The GGX normal distribution
		float  G = ggxSchlickMaskingTerm(NdotL, NdotV, roughness);   // Use Schlick's masking term approx
		float3 F = schlickFresnel(specular.xyz, LdotH);                  // Use Schlick's approx to Fresnel
		float3 ggxTerm = D * G * F / (4 * NdotL * NdotV);        // The Cook-Torrance microfacet BRDF

		// What's the probability of sampling vector H from getGGXMicrofacet()?
		float  ggxProb = D * NdotH / (4 * LdotH);

		float probDiffuse = probabilityToSampleDiffuse(diffuse.xyz, specular.xyz);
		// Accumulate the color:  ggx-BRDF * incomingLight * NdotL / probability-of-sampling
		shadeColor = NdotL * bounceColor * ggxTerm / (ggxProb * (1.0f - probDiffuse));
		//shadeColor = bounceColor * (1.0 - roughness);
	}

	bool colorsNan = any(isnan(shadeColor));
	// Store out the color of this shaded pixel
	gOutput[launchIndex] = float4(colorsNan ? float3(0, 0, 0) : shadeColor, 1.0f);

}
