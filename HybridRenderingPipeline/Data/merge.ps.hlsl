#include "HostDeviceSharedMacros.h"
#include "HostDeviceData.h"      

Texture2D<float4>   gM1;           
Texture2D<float4>   gM2;

float4 main(float2 texC : TEXCOORD, float4 pos : SV_Position) : SV_Target0
{
  uint2 pixelPos = (uint2)pos.xy;
	float3 shadeColor = gM1[pixelPos].rgb * gM2[pixelPos].rgb;
	return float4(shadeColor, 1.0f);
}
