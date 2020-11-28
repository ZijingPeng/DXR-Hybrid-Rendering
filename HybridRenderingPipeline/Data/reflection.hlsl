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

// A separate file with some simple utility functions: getPerpendicularVector(), initRand(), nextRand()
#include "commonUtils.hlsli"

// Payload for our primary rays.  We really don't use this for this g-buffer pass
struct ReflectRayPayload
{
	float4 reflectColor;
};

// A constant buffer we'll fill in for our ray generation shader
cbuffer RayGenCB
{
	uint  gFrameCount;
	float gMinT;
}

// Input and out textures that need to be set by the C++ code
Texture2D<float4> gPos;
Texture2D<float4> gNorm;
Texture2D<float4> gDiffuseMatl;
Texture2D<float4> gSpecMatl;
RWTexture2D<float4> gOutput;


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
	rayData.reflectColor = float4(shadeData.diffuse, 1);
}


[shader("raygeneration")]
void ReflectRayGen()
{
	// Where is this ray on screen?
	uint2 launchIndex = DispatchRaysIndex().xy;
	uint2 launchDim   = DispatchRaysDimensions().xy;

	// Initialize random seed per sample based on a screen position and temporally varying count
	uint randSeed = initRand(launchIndex.x + launchIndex.y * launchDim.x, gFrameCount, 16);

	// Load the position and normal from our g-buffer
	float4 worldPos = gPos[launchIndex];
	float4 worldNorm = gNorm[launchIndex];
	float4 diffuse = gDiffuseMatl[launchIndex];
	float4 specular = gSpecMatl[launchIndex];
	float roughness = gSpecMatl[launchIndex].w;

	float3 V = worldPos.xyz - gCamera.posW.xyz;
	V = -V;
	float3 N = worldNorm.xyz;

	if (worldPos.w != 0.0f)
	{
		RayDesc rayReflect;
		rayReflect.Origin = worldPos.xyz;
		rayReflect.Direction = reflect(-V, worldNorm.xyz);
		rayReflect.TMin = gMinT;
		rayReflect.TMax = 1e+38f;
		ReflectRayPayload rayPayload = { float4(0, 0, 0, 1) };
		TraceRay(gRtScene, RAY_FLAG_NONE, 0xFF, 0, hitProgramCount, 0, rayReflect, rayPayload);

		float3 L = rayReflect.Direction;
		float3 H = normalize(V + L);

		// GGX
		float3 F = FresnelSchlick(L, N, specular.xyz);
		float NDF = DistributionGGX(N, H, roughness);
		float G = GeometrySmith(N, V, L, roughness);
		float3 nominator = NDF * G * F;
		float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.001;
		float NdotL = max(dot(N, L), 0.0);
		gOutput[launchIndex] = float4(nominator / denominator, 1) * rayPayload.reflectColor * NdotL;

	}
	else
	{
		gOutput[launchIndex] = float4(0, 0, 0, 1);
	}

	
}
