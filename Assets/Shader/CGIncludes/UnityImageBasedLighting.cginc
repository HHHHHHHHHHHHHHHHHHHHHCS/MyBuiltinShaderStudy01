#ifndef UNITY_IMAGE_BASED_LIGHTING_INCLUDED
	#define UNITY_IMAGE_BASED_LIGHTING_INCLUDED
	
	#include "CGIncludes/UnityCG.cginc"
	#include "CGIncludes/UnityStandardBRDF.cginc"
	
	//glossyenvironment->将镜面照明与默认天空或反射探针集成的功能
	struct Unity_GlossyEnvironmentData
	{
		//延迟 只有一个cubemap
		//前向 可以有两个混合的cubemap(被常用的应该被舍弃)
		
		//用于cubemap的Surface属性
		half roughness; // 注意：这是perceptualRoughness，但由于兼容性，此名称不能更改
		half3 reflUVW;
	};
	
	//perceptualRoughness * step 计算 mipmap 等级
	half PerceptualRoughnessToMipmapLevel(half perceptualRoughness)
	{
		//UNITY_SPECCUBE_LOD_STEPS -> 6.0
		return perceptualRoughness * UNITY_SPECCUBE_LOD_STEPS;
	}

	Unity_GlossyEnvironmentData UnityGlossyEnvironmentSetup(half Smoothness, half3 worldViewDir, half3 Normal, half3 fresnel0)
	{
		Unity_GlossyEnvironmentData g;
		
		//roughness = 1 - Smoothness
		g.roughness /* perceptualRoughness */ = SmoothnessToPerceptualRoughness(Smoothness);
		g.reflUVW = reflect(-worldViewDir, Normal);
		
		return g;
	}
	
	//UNITY_ARGS_TEXCUBE -> samplerCUBE
	//得到环境反射球的颜色
	half3 Unity_GlossyEnvironment(UNITY_ARGS_TEXCUBE(tex), half4 hdr, Unity_GlossyEnvironmentData glossIn)
	{
		//perceptualRoughness =  1 - roughness
		half perceptualRoughness = glossIn.roughness;
		
		//perceptualRoughness 校正
		#if 0
			//PerceptualRoughnessToRoughness -> perceptualRoughness*perceptualRoughness
			float m = PerceptualRoughnessToRoughness(perceptualRoughness);
			const float fEps = 1.192092896e-07F;
			float n = (2.0 / (max(fEps, m * m))) - 2.0;
			
			n /= 4;
			
			perceptualRoughness = pow(2 / (n + 2), 0.25);
		#else
			perceptualRoughness = perceptualRoughness * (1.7 - 0.7 * perceptualRoughness);
		#endif
		
		half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
		half3 R = glossIn.reflUVW;
		//tex -> unity_SpecCube0 解析出的是RGBM 颜色   需要通过HDR 解压
		//UNITY_SAMPLE_TEXCUBE_LOD -> texCUBElod(sampler,dir,mimapLevel)
		half4 rgbm = UNITY_SAMPLE_TEXCUBE_LOD(tex, R, mip);
		
		return DecodeHDR(rgbm, hdr);
	}
	
#endif // UNITY_IMAGE_BASED_LIGHTING_INCLUDED
