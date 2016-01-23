Texture2D<uint> depthImage : register(t0);
Texture2D<float2> depthFrameToCameraSpaceTable : register(t1);
// can't create a structured buffer that is also a vertex buffer, so we use byte address buffers:
RWByteAddressBuffer worldCoordinates : register(u0);
RWByteAddressBuffer indices : register(u1);

cbuffer constants : register(b0)
{
	matrix world;
	uint indexOffset;
}

static const int depthImageWidth = 512;

[numthreads(32, 22, 1)]
void main( uint3 DTid : SV_DispatchThreadID )
{
	// test upper and lower triangles in this quad; avoid dynamic branching
	// A triangle is valid if all its points are nonzero, and each point is close to each other in 
	// depth (i.e., they do not straddle a large depth discontinuity).
	uint depth00 = depthImage[DTid.xy];
	uint depth10 = depthImage[DTid.xy + uint2(1, 0)];
	uint depth01 = depthImage[DTid.xy + uint2(0, 1)];
	uint depth11 = depthImage[DTid.xy + uint2(1, 1)];

	uint upperNonzero = (depth00 * depth10 * depth01) > 0;
	uint lowerNonzero = (depth11 * depth10 * depth01) > 0;

	uint near01 = abs((int)depth00 - (int)depth01) < 100;
	uint near02 = abs((int)depth00 - (int)depth10) < 100;
	uint near12 = abs((int)depth01 - (int)depth10) < 100;

	uint near43 = abs((int)depth10 - (int)depth11) < 100;
	uint near53 = abs((int)depth01 - (int)depth11) < 100;
	uint near45 = near12;

	uint upperValid = upperNonzero * near01 * near02 * near12;
	uint lowerValid = lowerNonzero * near43 * near53 * near45;

	// world coordinate
	float2 distorted00 = depthFrameToCameraSpaceTable[DTid.xy];
	float depth00m = (float)depth00 / 1000; // m
	float4 depthCamera00 = float4(distorted00*depth00m, depth00m, 1);
	float4 pos00 = mul(world, depthCamera00);

	float2 distorted10 = depthFrameToCameraSpaceTable[DTid.xy + uint2(1, 0)];
	float depth10m = (float)depth10 / 1000; // m
	float4 depthCamera10 = float4(distorted10*depth10m, depth10m, 1);

	float2 distorted01 = depthFrameToCameraSpaceTable[DTid.xy + uint2(0, 1)];
	float depth01m = (float)depth01 / 1000; // m
	float4 depthCamera01 = float4(distorted01*depth01m, depth01m, 1);

	float2 distorted11 = depthFrameToCameraSpaceTable[DTid.xy + uint2(1, 1)];
	float depth11m = (float)depth11 / 1000; // m
	float4 depthCamera11 = float4(distorted11*depth11m, depth11m, 1);


	float3 a = depthCamera01.xyz - depthCamera00.xyz;
	float3 b = depthCamera10.xyz - depthCamera00.xyz;
	float3 normal0 = cross(a, b);
	normal0 = mul((float3x3)world, normal0);
	normal0 = normalize(normal0);

	float3 c = depthCamera10.xyz - depthCamera11.xyz;
	float3 d = depthCamera01.xyz - depthCamera11.xyz;
	float3 normal1 = cross(c, d);
	normal1 = mul((float3x3)world, normal1);
	normal1 = normalize(normal1);

	float3 normal = normal0 + normal1;


	uint index = DTid.y * depthImageWidth + DTid.x;
	worldCoordinates.Store3(index * 24, asuint(pos00.xyz));
	worldCoordinates.Store3(index * 24 + 12, asuint(normal));


	// indices
	uint index2 = index + indexOffset; // each camera is 512*484*6 vertices
	indices.Store3(index * 24, upperValid * uint3(index2, index2 + depthImageWidth, index2 + 1)); // 00, 01, 10
	indices.Store3(index * 24 + 12, lowerValid * uint3(index2 + depthImageWidth + 1, index2 + 1, index2 + depthImageWidth)); // 11, 10, 10
}