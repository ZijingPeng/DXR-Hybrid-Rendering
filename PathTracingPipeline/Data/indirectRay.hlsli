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

#include "halton.hlsli"

// The payload structure for our indirect rays
struct IndirectRayPayload
{
	float3 color;    // The (returned) color in the ray's direction
	uint   rndSeed;  // Our random seed, so we pick uncorrelated RNGs along our ray
	uint   rayDepth; // What is the depth of our current ray?
	HaltonState hState;
};

float3 shootIndirectRay(float3 rayOrigin, float3 rayDir, float minT, uint curPathLen, uint seed, HaltonState hState, uint curDepth)
{
	// Setup our indirect ray
	RayDesc rayColor;
	rayColor.Origin = rayOrigin;  // Where does it start?
	rayColor.Direction = rayDir;  // What direction do we shoot it?
	rayColor.TMin = minT;         // The closest distance we'll count as a hit
	rayColor.TMax = 1.0e38f;      // The farthest distance we'll count as a hit

	// Initialize the ray's payload data with black return color and the current rng seed
	IndirectRayPayload payload;
	payload.color = float3(0, 0, 0);
	payload.rndSeed = seed;
	payload.rayDepth = curDepth + 1;
	payload.hState = hState;

	// Trace our ray to get a color in the indirect direction.  Use hit group #1 and miss shader #1
	TraceRay(gRtScene, 0, 0xFF, 1, hitProgramCount, 1, rayColor, payload);

	// Return the color we got from our ray
	return payload.color;
}

[shader("miss")]
void IndirectMiss(inout IndirectRayPayload rayData)
{
	// Load some information about our lightprobe texture
	float2 dims;
	gEnvMap.GetDimensions(dims.x, dims.y);

	// Convert our ray direction to a (u,v) coordinate
	float2 uv = wsVectorToLatLong(WorldRayDirection());

	// Load our background color, then store it into our ray payload
	rayData.color = gEnvMap[uint2(uv * dims)].rgb;
}

[shader("anyhit")]
void IndirectAnyHit(inout IndirectRayPayload rayData, BuiltInTriangleIntersectionAttributes attribs)
{
	// Is this a transparent part of the surface?  If so, ignore this hit
	if (alphaTestFails(attribs))
		IgnoreHit();
}

float3 lambertianDirect(inout uint rndSeed, HaltonState hState, float3 hit, float3 norm, float3 difColor)
{
	// Pick a random light from our scene to shoot a shadow ray towards
	int lightToSample = min(int(nextRand(rndSeed) * gLightsCount), gLightsCount - 1);

	// Query the scene to find info about the randomly selected light
	float distToLight;
	float3 lightIntensity;
	float3 toLight;
	getLightData(lightToSample, hit, toLight, lightIntensity, distToLight);

	// Compute our lambertion term (L dot N)
	float LdotN = saturate(dot(norm, toLight));

	// Shoot our shadow ray to our randomly selected light
	float shadowMult = float(gLightsCount) * shadowRayVisibility(rndSeed, hit, toLight, gMinT, distToLight);

	// Return the Lambertian shading color using the physically based Lambertian term (albedo / pi)
	return shadowMult * LdotN * lightIntensity * difColor / M_PI;
}

float3 lambertianIndirect(inout uint rndSeed, HaltonState hState, float3 hit, float3 norm, float3 difColor, uint rayDepth)
{
	// Shoot a randomly selected cosine-sampled diffuse ray.
	float3 L = getCosHemisphereSample(rndSeed, norm);
	float3 bounceColor = shootIndirectRay(hit, L, gMinT, 0, rndSeed, hState, rayDepth);

	// Accumulate the color: (NdotL * incomingLight * difColor / pi) 
	// Probability of sampling:  (NdotL / pi)
	return bounceColor * difColor;
}

float3 ggxDirect(inout uint rndSeed, HaltonState hState, float3 hit, float3 N, float3 V, float3 dif, float3 spec, float rough)
{
	return lambertianDirect(rndSeed, hState, hit, N, dif) * dif;
	//return float3(0.0);
}

float3 ggxIndirect(inout uint rndSeed, HaltonState hState, float3 hit, float3 N, float3 noNormalN, float3 V, float3 dif, float3 spec, float rough, uint rayDepth, bool inverseRoughness)
{
	if (!inverseRoughness) {
		rough = 1.0 - rough;
	}
	// We have to decide whether we sample our diffuse or specular/ggx lobe.
	float probDiffuse = probabilityToSampleDiffuse(dif, spec);
	//int chooseDiffuse = 0;

	// We'll need NdotV for both diffuse and specular...
	float NdotV = saturate(dot(N, V));

	// If we randomly selected to sample our diffuse lobe...
	if (frac(haltonNext(hState) + nextRand(rndSeed)) > rough)
	{
		return lambertianIndirect(rndSeed, hState, hit, N, dif, rayDepth);
		//return float3(0.0);
	}
	// Otherwise we randomly selected to sample our GGX lobe
	else
	{
		float rnd1 = frac(haltonNext(hState) + nextRand(rndSeed));
		float rnd2 = frac(haltonNext(hState) + nextRand(rndSeed));
		float2 Xi = float2(rnd1, rnd2);
		float3 H = ImportanceSampleGGX(Xi, N, 1.0 - rough);
		float3 L = normalize(2.0 * dot(V, H) * H - V);

		float3 bounceColor = shootIndirectRay(hit, L, gMinT, 0, rndSeed, hState, rayDepth);
		return bounceColor;
		//return float3(0.0, 1.0, 0.0);
	}
}

[shader("closesthit")]
void IndirectClosestHit(inout IndirectRayPayload rayData, BuiltInTriangleIntersectionAttributes attribs)
{
	// Run a helper functions to extract Falcor scene data for shading
	ShadingData shadeData = getHitShadingData( attribs, WorldRayOrigin() );

    // Add emissive color
    rayData.color = gEmitMult * shadeData.emissive.rgb;

	// Do direct illumination at this hit location
    if (gDoDirectGI)
    {
        rayData.color += ggxDirect(rayData.rndSeed, rayData.hState, shadeData.posW, shadeData.N, shadeData.V,
            shadeData.diffuse, shadeData.specular, 0.0);
    }

	// Do indirect illumination at this hit location (if we haven't traversed too far)
	if (rayData.rayDepth < gMaxDepth)
	{
		// Use the same normal for the normal-mapped and non-normal mapped vectors... This means we could get light
		//     leaks at secondary surfaces with normal maps due to indirect rays going below the surface.  This
		//     isn't a huge issue, but this is a (TODO: fix)
		rayData.color += ggxIndirect(rayData.rndSeed, rayData.hState, shadeData.posW, shadeData.N, shadeData.N, shadeData.V,
			shadeData.diffuse, shadeData.specular, shadeData.roughness, rayData.rayDepth, gInverseRoughness);
	}
}
