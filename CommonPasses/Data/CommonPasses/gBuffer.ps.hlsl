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

// Falcor / Slang imports to include shared code and data structures
__import Shading;           // Imports ShaderCommon and DefaultVS, plus material evaluation
__import DefaultVS;         // VertexOut declaration
import MathHelpers;

struct GBuffer
{
	float4 wsPos    : SV_Target0;
	float4 wsNorm   : SV_Target1;
	float4 matDif   : SV_Target2;
	float4 matSpec  : SV_Target3;
  float4 matEmissive : SV_Target4;
  float4 linearZAndNormal : SV_Target5;
  float4 motionVecFwidth : SV_Target6;
};

cbuffer PerImageCB {
  float2 gRenderTargetDim;
};

// Our main entry point for the g-buffer fragment shader.
GBuffer main(VertexOut vsOut, uint primID : SV_PrimitiveID, float4 pos : SV_Position)
{
	// This is a Falcor built-in that extracts data suitable for shading routines
	//     (see ShaderCommon.slang for the shading data structure and routines)
	ShadingData hitPt = prepareShadingData(vsOut, gMaterial, gCamera.posW);

	// Check if we hit the back of a double-sided material, in which case, we flip
	//     normals around here (so we don't need to when shading)
	float NdotV = dot(normalize(hitPt.N.xyz), normalize(gCamera.posW - hitPt.posW));
	if (NdotV <= 0.0f && hitPt.doubleSidedMaterial)
		hitPt.N = -hitPt.N;

	// Dump out our G buffer channels
	GBuffer gBufOut;
	gBufOut.wsPos    = float4(hitPt.posW, 1.f);
	gBufOut.wsNorm   = float4(hitPt.N, length(hitPt.posW - gCamera.posW) );
	gBufOut.matDif   = float4(hitPt.diffuse, hitPt.opacity);
	gBufOut.matSpec  = float4(hitPt.specular, hitPt.linearRoughness);
  gBufOut.matEmissive = float4(hitPt.emissive, 0.f);
  

  float3 albedo = hitPt.diffuse;
  const float linearZ = vsOut.posH.z * vsOut.posH.w;
  // Pack normal into the last component of linear z
  const float2 nPacked = ndir_to_oct_snorm(hitPt.N);
  gBufOut.linearZAndNormal = float4(linearZ, max(abs(ddx(linearZ)), abs(ddy(linearZ))), nPacked.x, nPacked.y); 

  int2 ipos = int2(vsOut.posH.xy);
  const float2 pixelPos = ipos + float2(0.5, 0.5); // Current sample in pixel coords.
  const float4 prevPosH = vsOut.prevPosH; // Sample in previous frame in clip space coords, no jittering applied.
  float2 motionVec = calcMotionVector(pixelPos, prevPosH, gRenderTargetDim) + float2(gCamera.jitterX, -gCamera.jitterY);
  float2 posNormalFwidth = float2(length(fwidth(hitPt.posW)), length(fwidth(hitPt.N)));
  gBufOut.motionVecFwidth = float4(motionVec.x, motionVec.y, posNormalFwidth.x, posNormalFwidth.y);

	return gBufOut;
}


