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

Texture2D<float4>   gPos;
Texture2D<float4>   gReflection; 
Texture2D<float4>   gDirectLighting;
Texture2D<float4>   gShadowAO;
Texture2D<float4>   gEmissive;

float4 main(float2 texC : TEXCOORD, float4 pos : SV_Position) : SV_Target0
{
    uint2 pixelPos = (uint2)pos.xy;
	float4 worldPos = gPos[pixelPos];
    float4 reflection = gReflection[pixelPos];
	float4 directLighting = gDirectLighting[pixelPos];
	float4 shadow = gShadowAO[pixelPos];
	float4 emissive = gEmissive[pixelPos];
	float ambient = 0.1;

	float3 shadeColor;

	// Todo: reflection
	shadeColor = (directLighting * (float4(ambient) + shadow)).rgb + reflection.rgb + emissive.rgb;
	bool isGeometryValid = (worldPos.w != 0.0f);
	shadeColor = (worldPos.w != 0.0f) ? shadeColor : shadeColor + float3(0.48, 0.75, 0.85);
	return float4(shadeColor, 1.0f);
}
