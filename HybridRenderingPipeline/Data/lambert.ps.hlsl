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
// Some shared Falcor stuff for talking between CPU and GPU code
#include "HostDeviceSharedMacros.h"
#include "HostDeviceData.h"     

// Include and import common Falcor utilities and data structures
__import Raytracing;
__import ShaderCommon;
__import Shading;                      // Shading functions, etc
__import Lights;                       // Light structures for our current scene

// A separate file with some simple utility functions: getPerpendicularVector(), initRand(), nextRand()
#include "commonUtils.hlsli"

Texture2D<float4>   gPos;           // G-buffer world-space position
Texture2D<float4>   gNorm;          // G-buffer world-space normal
Texture2D<float4>   gDiffuseMatl;   // G-buffer diffuse material (RGB) and opacity (A)
Texture2D<float4>   gSpecMatl;

float4 main(float2 texC : TEXCOORD, float4 pos : SV_Position) : SV_Target0
{
    uint2 pixelPos = (uint2)pos.xy;
    float4 worldPos = gPos[pixelPos];
    float4 worldNorm = gNorm[pixelPos];
    float4 difMatlColor = gDiffuseMatl[pixelPos];
	float4 specMatlColor = gSpecMatl[pixelPos];

	float3 shadeColor;
	float ambient = 0.03;

	float probDiffuse = probabilityToSampleDiffuse(difMatlColor.xyz, specMatlColor.xyz);

	// Our camera sees the background if worldPos.w is 0, only do diffuse shading
	if (worldPos.w != 0.0f)
	{
		// We're going to accumulate contributions from multiple lights, so zero out our sum
		shadeColor = float3(0.0, 0.0, 0.0);

		// Iterate over the lights
		for (int lightIndex = 0; lightIndex < gLightsCount; lightIndex++)
		{
			// We need to query our scene to find info about the current light
			float distToLight;      // How far away is it?
			float3 lightIntensity;  // What color is it?
			float3 toLight;         // What direction is it from our current pixel?

			// A helper (from the included .hlsli) to query the Falcor scene to get this data
			getLightData(lightIndex, worldPos.xyz, toLight, lightIntensity, distToLight);

			// Compute our lambertion term (L dot N)
			float LdotN = saturate(dot(worldNorm.xyz, toLight));

			// Accumulate our Lambertian shading color
			shadeColor += LdotN * lightIntensity;
		}
		// Modulate based on the physically based Lambertian term (albedo/pi)
		shadeColor *= difMatlColor.rgb / 3.141592f;
	}

	shadeColor = max(shadeColor, 0.05 * difMatlColor.xyz);

	return float4(shadeColor, 1.0f);
}
