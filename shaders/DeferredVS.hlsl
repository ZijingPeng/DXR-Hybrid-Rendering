#include "DeferredRender.hlsli"



vs_gbuffer_out main(vs_gbuffer_in vIn)
{
	
	vs_gbuffer_out vOut;
	vOut.position = mul(vIn.position, gMVP);
	
	vOut.normal = vIn.normal;
	vOut.worldPos = vOut.position/ vOut.position.w;
	return vOut;
}