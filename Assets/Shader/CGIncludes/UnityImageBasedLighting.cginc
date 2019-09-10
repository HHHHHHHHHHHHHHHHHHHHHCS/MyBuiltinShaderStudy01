#ifndef UNITY_IMAGE_BASED_LIGHTING_INCLUDED
	#define UNITY_IMAGE_BASED_LIGHTING_INCLUDED
	
	#include "CGIncludes/UnityCG.cginc"
	#include "CGIncludes/UnityStandardBRDF.cginc"
	
	
	// ----------------------------------------------------------------------------
	// 包含了不推荐的函数
	#define INCLUDE_UNITY_IMAGE_BASED_LIGHTING_DEPRECATED
	#include "CGIncludes/UnityDeprecated.cginc"
	#undef INCLUDE_UNITY_IMAGE_BASED_LIGHTING_DEPRECATED
	// ----------------------------------------------------------------------------
	
	//glossyenvironment->将镜面照明与默认天空或反射探针集成的功能
	struct Unity_GlossyEnvironmentData
	{
		//延迟 只有一个cubemap
		//前向 可以有两个混合的cubemap(被常用的应该被舍弃)

		//用于cubemap的Surface属性
		half roughness; // 注意：这是perceptualRoughness，但由于兼容性，此名称不能更改
		half3 reflUVW;
	};
	
	Unity_GlossyEnvironmentData UnityGlossyEnvironmentSetup(half Smoothness, half3 worldViewDir, half3 Normal, half3 fresnel0)
	{
		Unity_GlossyEnvironmentData g;
		
		//roughness = 1 - Smoothness
		g.roughness /* perceptualRoughness */ = SmoothnessToPerceptualRoughness(Smoothness);
		g.reflUVW = reflect(-worldViewDir, Normal);
		
		return g;
	}
	
#endif // UNITY_IMAGE_BASED_LIGHTING_INCLUDED
