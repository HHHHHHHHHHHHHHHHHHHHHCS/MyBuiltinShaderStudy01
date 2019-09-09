#ifndef UNITY_IMAGE_BASED_LIGHTING_INCLUDED
	#define UNITY_IMAGE_BASED_LIGHTING_INCLUDED
	
	#include "CGIncludes/UnityCG.cginc"
	#include "CGIncludes/UnityStandardBRDF.cginc"
	
	//glossyenvironment->将镜面照明与默认天空或反射探针集成的功能
	struct Unity_GlossyEnvironmentData
	{
		//延期案件有一个立方图
		//前向事例可以有两个混合的立方映射（不寻常的应该被弃用）。
		
		//用于cubemap集成的曲面属性
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
