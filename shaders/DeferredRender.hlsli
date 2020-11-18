
cbuffer ViewData : register (b0)
{
	float4x4 gMVP;
	float4x4 gInvPV;
	float3 gCamPos;
}
cbuffer LightData : register (b1)
{
	float3 gLightPos;
}


struct vs_in {
	float4 position : POSITION;
	float2 texcoord : TEXCOORD;
};

struct vs_out {
	float4 position : SV_POSITION;
	float2 texcoord : TEXCOORD;
};

struct vs_gbuffer_in {
	float4 position : POSITION;
	float3 normal : NORMAL;

};
struct vs_gbuffer_out {
	float4 position : SV_POSITION;
	float3 normal : NORMAL;
	float4 worldPos :TEXCOORD;
};
struct SurfaceData
{
	float3 positionView;         // View space position
	float3 normal;               // View space normal
	float4 albedo;
	float3 specular;      
	float gloss;
};