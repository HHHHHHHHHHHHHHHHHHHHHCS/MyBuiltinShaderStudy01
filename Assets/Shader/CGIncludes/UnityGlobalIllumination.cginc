#ifndef UNITY_GLOBAL_ILLUMINATION_INCLUDED
	#define UNITY_GLOBAL_ILLUMINATION_INCLUDED
	
	#include "CGIncludes/UnityImageBasedLighting.cginc"
	
	inline void ResetUnityLight(out UnityLight outLight)
	{
		outLight.color = half3(0, 0, 0);
		outLight.dir = half3(0, 1, 0);//不相关的方向,但是不能为空
		outLight.ndotl = 0;//用不到了
	}
	
	inline void ResetUnityGI(out UnityGI outGI)
	{
		ResetUnityLight(outGI.light);
		outGI.indirect.diffuse = 0;
		outGI.indirect.specular = 0;
	}
	
	inline UnityGI UnityGI_Base(UnityGIInput data, half occlusion, half3 normalWorld)
	{
		//TODO:
		UnityGI o_gi;
		ResetUnityGI(o_gi);
		
		//基于性能原因，支持光照贴图的基本过程负责处理阴影遮罩/混合
		#if defined(HANDLE_SHADOWS_BLEDING_IN_GI)
			half bakedAtten = UnitySampleBakedOcclusion(data.lightmapUV.xy, data.worldPos);
			float zDist = dot(_WorldSpaceCameraPos - data.worldPos, UNITY_MATRIX_V[2].xyz);
			float fadeDist = UnityComputeShadowFadeDistance(data.worldPos,zDist);
			data.atten = UnityMixRealTimeAndBakedShadows(data.atten,bakedAtten,UntiyComputeShadowFade(fadeDist));
		#endif
	}
	
	inline UnityGI UnityGlobalIllumination(UnityGIInput data, half occlusion, half3 normalWorld)
	{
		//TODO:UnityGI_Base
		return UnityGI_Base(data, occlusion, normalWorld);
	}
	
	inline UnityGI UnityGlobalIllumination(UnityGIInput data, half occlusion, half3 normalWorld, Unity_GlossyEnvironmentData glossIn)
	{
		UnityGI o_gi = UnityGI_Base(data, occlusion, normalWorld);
		o_gi.indirect.specular = UnityGI_IndirectSpecular(data, occlusion, glossIn);
		return o_gi;
	}
	
#endif
