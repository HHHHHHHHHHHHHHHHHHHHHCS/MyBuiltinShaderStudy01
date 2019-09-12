#ifndef UNITY_STANDARD_BRDF_INCLUDED
	#define UNITY_STANDARD_BRDF_INCLUDED
	
	#include "CGIncludes/UnityLightingCommon.cginc"
	
	#define INCLUDE_UNITY_STANDARD_BRDF_DEPRECATED
	#include "CGIncludes/UnityDeprecated.cginc"
	#undef INCLUDE_UNITY_STANDARD_BRDF_DEPRECATED
	
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
	
	float PerceptualRoughnessToRoughness(float perceptualRoughness)
	{
		return perceptualRoughness * perceptualRoughness;
	}
	
	//计算输入的间接光
	half3 BRDF3_Indirect(half3 diffColor, half3 specColor, UnityIndirect indirect, half grazingTerm, half fresnelTerm)
	{
		//diff颜色乘法叠加
		half3 c = indirect.diffuse * diffColor;
		//高光反射 加法叠加   这里有菲尼尔lerp
		c += indirect.specular * lerp(specColor, grazingTerm, fresnelTerm);
		return c;
	}
	
	//预存的BRDF 跟rougness 有关的预积分Lut图  采样结果是specular
	sampler2D_float unity_NHxRoughness;
	half3 BRDF3_Direct(half3 diffColor, half3 specColor, half rlPow4, half smoothness)
	{
		half LUT_RANGE = 16.0;//必须跟 GeneratedTextures.cpp 中的 NHxRoughness() 方法的 范围想匹配
		
		#if defined(_SPECULARHIGHTS_OFF)
			half specular = 0.0;
		#else
			half specular = tex2D(unity_NHxRoughness, half2(rlPow4, SmoothnessToPerceptualRoughness(smoothness))).r * LUT_RANGE;
		#endif
		
		return diffColor + specular * specColor;
	}
	
#endif // UNITY_STANDARD_BRDF_INCLUDED
