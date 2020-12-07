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
//import Raytracing;
import Shading;                      // Shading functions, etc     
import Lights;                       // Light structures for our current scene

Texture2D<float4>   gPos;           // G-buffer world-space position
Texture2D<float4>   gNorm;          // G-buffer world-space normal
Texture2D<float4>   gDiffuseMatl;   // G-buffer diffuse material (RGB) and opacity (A)

void getLightData(in int index, in float3 hitPos, out float3 toLight, out float3 lightIntensity, out float distToLight)
{
	// Use built-in Falcor functions and data structures to fill in a LightSample data structure
	//   -> See "Lights.slang" for it's definition
	LightSample ls;

	// Is it a directional light?
	if (gLights[index].type == LightDirectional)
		ls = evalDirectionalLight(gLights[index], hitPos);

	// No?  Must be a point light.
	else
		ls = evalPointLight(gLights[index], hitPos);

	// Convert the LightSample structure into simpler data
	toLight = normalize(ls.L);
	lightIntensity = ls.diffuse;
	distToLight = length(ls.posW - hitPos);
}

float4 main(float2 texC : TEXCOORD, float4 pos : SV_Position) : SV_Target0
{
    uint2 pixelPos = (uint2)pos.xy;
    float4 worldPos = gPos[pixelPos];
    float4 worldNorm = gNorm[pixelPos];
    float4 difMatlColor = gDiffuseMatl[pixelPos];

	float3 shadeColor;
	float ambient = 0.03;

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

	//shadeColor = max(shadeColor, ambient * difMatlColor.rgb);
	shadeColor = max(ambient * difMatlColor.rgb, shadeColor);
	shadeColor = min(shadeColor, float3(1.0, 1.0, 1.0));

	//return float4(1.0, 0.0, 0.0, 1.0f);
	return float4(shadeColor, 1.0f);
}
