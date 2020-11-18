#include "DeferredRender.hlsli"
struct ps_output
{
	float4 albedo : SV_TARGET0;
	float4 normal : SV_TARGET1;
	float4 specgloss : SV_TARGET2;
};

ps_output main(vs_gbuffer_out pIn) : SV_TARGET
{
	ps_output output;
	output.albedo = float4(1.0f, 0.0f, 0.0f, 0.0f);
	output.normal = float4(pIn.normal, 1.0f);


	output.specgloss = float4(0.5,0.5,0.5,0.6);

	return output;
}