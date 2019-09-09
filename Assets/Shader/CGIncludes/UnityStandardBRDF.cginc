#ifndef UNITY_STANDARD_BRDF_INCLUDED
	#define UNITY_STANDARD_BRDF_INCLUDED
	
	#include "CGIncludes/UnityLightingCommon.cginc"
	
	
	inline half Pow4(half x)
	{
		return x * x * x * x;
	}
	
	inline float2 Pow4(float2 x)
	{
		return x * x * x * x;
	}
	
	inline half3 Pow4(half3 x)
	{
		return x * x * x * x;
	}
	
	inline half4 Pow4(half4 x)
	{
		return x * x * x * x;
	}
	
	float SmoothnessToPerceptualRoughness(float smoothness)
	{
		return 1 - smoothness;
	}
	
#endif // UNITY_STANDARD_BRDF_INCLUDED
