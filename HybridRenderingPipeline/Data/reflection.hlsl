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
	bool isOpenScene;
	float3 hitPoint;
	bool miss;
};

// A constant buffer we'll fill in for our ray generation shader
cbuffer RayGenCB
{
	uint  gFrameCount;
	float gMinT;
	bool gOpenScene;
	bool gHalfResolution;
}

// Input and out textures that need to be set by the C++ code
Texture2D<float4> gPos;
Texture2D<float4> gNorm;
Texture2D<float4> gDiffuseMatl;
Texture2D<float4> gSpecMatl;
Texture2D<float4>   gShadow;
RWTexture2D<float4> gOutput;

#include "standardShadowRay.hlsli"

[shader("miss")]
void ReflectMiss(inout ReflectRayPayload hitData : SV_RayPayload)
{
	hitData.reflectColor = hitData.isOpenScene ? float4(0.053, 0.081, 0.092, 1.0f) : float4(0, 0, 0, 1);
	hitData.miss = true;
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

	rayData.hitPoint = hit;
	int lightToSample = min(int(nextRand(rayData.rndSeed) * gLightsCount), gLightsCount - 1);
	// Query the scene to find info about the randomly selected light
	float distToLight;
	float3 lightIntensity;
	float3 L;
	getLightData(lightToSample, hit, L, lightIntensity, distToLight);
	float NdotL = saturate(dot(N, L));
	float shadowMult = float(gLightsCount) * shadowRayVisibility(hit, L, gMinT, distToLight);
	shadowMult = max(shadowMult, 0.08);

	// Compute our final color (combining diffuse lobe plus specular GGX lobe)
	rayData.reflectColor += float4(shadowMult * lightIntensity * ( NdotL * dif / PI), 1);
}


[shader("raygeneration")]
void ReflectRayGen()
{
	// Where is this ray on screen?
	uint2 launchIndex = DispatchRaysIndex().xy;
	uint2 launchDim = DispatchRaysDimensions().xy;
	// Initialize random seed per sample based on a screen position and temporally varying count
	uint randSeed = initRand(launchIndex.x + launchIndex.y * launchDim.x, gFrameCount, 16);

	uint2 launchIndexCopy;
	
	if (!gHalfResolution) {
		launchIndexCopy = launchIndex;
	}
	else {
		launchIndexCopy = launchIndex * 2;
		launchIndex = launchIndex * 2 + uint2(int(randSeed) & 1, int(nextRand(randSeed)) & 1);
	}

	// Load the position and normal from our g-buffer
	float4 worldPos = gPos[launchIndex];
	float4 worldNorm = gNorm[launchIndex];
	float4 diffuse = gDiffuseMatl[launchIndex];
	float4 specular = gSpecMatl[launchIndex];
	float roughness = gSpecMatl[launchIndex].w;
	float4 shadow = gNorm[launchIndex];

	float3 V = normalize(gCamera.posW - worldPos.xyz);
	float3 N = worldNorm.xyz;

	// Make sure our normal is pointed the right direction
	if (dot(N, V) <= 0.0f) N = -N;
	float NdotV = dot(N, V);

	bool isGeometryValid = (worldPos.w != 0.0f);
	float3 shadeColor;
	float3 bounceColor;
	if (isGeometryValid)
	{
		HaltonState hState;
		haltonInit(hState, launchIndex.x, launchIndex.y, 1, 1, gFrameCount, 1);
		uint randSeed = initRand(launchIndex.x + launchIndex.y * launchDim.x, gFrameCount, 16);
		float rnd1 = frac(haltonNext(hState) + nextRand(randSeed));
		float rnd2 = frac(haltonNext(hState) + nextRand(randSeed));
		float2 Xi = float2(rnd1, rnd2);
		float3 H = getGGXMicrofacet(Xi, N, roughness);
		float3 L = normalize(2.0 * dot(V, H) * H - V);

		RayDesc rayReflect;
		rayReflect.Origin = worldPos.xyz;
		rayReflect.Direction = L;
		rayReflect.TMin = gMinT;
		rayReflect.TMax = 1e+38f;
		ReflectRayPayload rayPayload = { float4(0, 0, 0, 1), randSeed, gOpenScene, float3(0), false };
		TraceRay(gRtScene, RAY_FLAG_NONE, 0xFF, 0, hitProgramCount, 0, rayReflect, rayPayload);

		bounceColor = rayPayload.reflectColor.xyz;

		bool colorsNan = any(isnan(bounceColor));
		if (colorsNan || rayPayload.miss) {
			gOutput[launchIndexCopy] = float4(bounceColor, 1);
			if (gHalfResolution) {
				gOutput[launchIndexCopy + uint2(0, 1)] = float4(bounceColor, 1);
				gOutput[launchIndexCopy + uint2(1, 0)] = float4(bounceColor, 1);
				gOutput[launchIndexCopy + uint2(1, 1)] = float4(bounceColor, 1);
			}
		}
		else {
			// Compute some dot products needed for shading
			float NdotL;

			if (gHalfResolution) {
				float3 hitPoint = rayPayload.hitPoint;
				NdotL = saturate(dot(N, normalize(rayPayload.hitPoint - gPos[launchIndexCopy].xyz)));
				gOutput[launchIndexCopy] = float4(NdotL * bounceColor, 1);
				NdotL = saturate(dot(N, normalize(rayPayload.hitPoint - gPos[launchIndexCopy + uint2(0, 1)].xyz)));
				gOutput[launchIndexCopy + uint2(0, 1)] = float4(NdotL * bounceColor, 1);
				NdotL = saturate(dot(N, normalize(rayPayload.hitPoint - gPos[launchIndexCopy + uint2(1, 0)].xyz)));
				gOutput[launchIndexCopy + uint2(1, 0)] = float4(NdotL * bounceColor, 1);
				NdotL = saturate(dot(N, normalize(rayPayload.hitPoint - gPos[launchIndexCopy + uint2(1, 1)].xyz)));
				gOutput[launchIndexCopy + uint2(1, 1)] = float4(NdotL * bounceColor, 1);
			}
			else {
				NdotL = saturate(dot(N, L));
				gOutput[launchIndexCopy] = float4(NdotL * bounceColor, 1);
			}
		}
	}
	else {
		gOutput[launchIndexCopy] = float4(0, 0, 0, 1.0f);
		if (gHalfResolution) {
			gOutput[launchIndexCopy + uint2(0, 1)] = float4(0, 0, 0, 1.0f);
			gOutput[launchIndexCopy + uint2(1, 0)] = float4(0, 0, 0, 1.0f);
			gOutput[launchIndexCopy + uint2(1, 1)] = float4(0, 0, 0, 1.0f);
		}
	}

}
