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
// Get a random vector in a cone centered around a specified normal direction.
float3 getConeSample(inout uint randSeed, float3 hitNorm, float cosThetaMax)
{
	// Get 2 random numbers to select our sample with
	float2 randVal = float2(nextRand(randSeed), nextRand(randSeed));

	// Cosine weighted hemisphere sample from RNG
	float3 bitangent = getPerpendicularVector(hitNorm);
	float3 tangent = cross(bitangent, hitNorm);

	float cosTheta = (1.0 - randVal.x) + randVal.x * cosThetaMax;
	float r = sqrt(1.0 - cosTheta * cosTheta);
	float phi = randVal.y * 2.0 * 3.14159265f;

	// Get our cosine-weighted hemisphere lobe sample direction
	return tangent * (r * cos(phi)) + bitangent * (r * sin(phi)) + hitNorm.xyz * cosTheta;
}

// Payload for our shadow rays. 
struct ShadowRayPayload
{
	float visFactor;  // Will be 1.0 for fully lit, 0.0 for fully shadowed
};

// A utility function to trace a shadow ray and return 1 if no shadow and 0 if shadowed.
//    -> Note:  This assumes the shadow hit programs and miss programs are index 0!
float shadowRayVisibility(inout uint rndSeed, float3 origin, float3 direction, float minT, float maxT)
{
	// Setup our shadow ray
	RayDesc ray;
	ray.Origin = origin;        // Where does it start?
	ray.Direction = normalize(getConeSample(rndSeed, direction, 0.995));  // What direction do we shoot it?
	ray.TMin = minT;            // The closest distance we'll count as a hit
	ray.TMax = maxT;            // The farthest distance we'll count as a hit

	// Our shadow rays are *assumed* to hit geometry; this miss shader changes this to 1.0 for "visible"
	ShadowRayPayload payload = { 0.0f };

	// Query if anything is between the current point and the light
	TraceRay(gRtScene,
		RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER,
		0xFF, 0, hitProgramCount, 0, ray, payload);

	// Return our ray payload (which is 1 for visible, 0 for occluded)
	return payload.visFactor;
}

// What code is executed when our ray misses all geometry?
[shader("miss")]
void ShadowMiss(inout ShadowRayPayload rayData)
{
	// If we miss all geometry, then the light is visibile
	rayData.visFactor = 1.0f;
}

// What code is executed when our ray hits a potentially transparent surface?
[shader("anyhit")]
void ShadowAnyHit(inout ShadowRayPayload rayData, BuiltInTriangleIntersectionAttributes attribs)
{
	// Is this a transparent part of the surface?  If so, ignore this hit
	if (alphaTestFails(attribs))
		IgnoreHit();
}

// What code is executed when we have a new closest hitpoint?
[shader("closesthit")]
void ShadowClosestHit(inout ShadowRayPayload rayData, BuiltInTriangleIntersectionAttributes attribs)
{
}
