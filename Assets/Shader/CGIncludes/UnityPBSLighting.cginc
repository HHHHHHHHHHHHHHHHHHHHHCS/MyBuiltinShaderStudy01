#ifndef UNITY_PBS_LIGHTING_INCLUDED
	#define UNITY_PBS_LIGHTING_INCLUDED
	
	#include "UnityGlobalIllumination.cginc"
	
	//允许在自定义着色器中显式重写brdf
	#if !defined(UNITY_BRDF_PBS)
		//仍然为低着色器模型添加安全网，否则可能导致着色器无法编译
		//surface shader analysis pass 用最便宜的
		//Editor->Project Settings ->Graphics    TierSettings.standardShaderQuality 定义的
		//TODO:
		#if SHADER_TARGET < 30 || defined(SHADER_TARGET_SURFACE_ANALYSIS)
			#define UNITY_BRDF_PBS BRDF3_Unity_PBS
		#elif defined(UNITY_PBS_USE_BRDF3)
			#define UNITY_BRDF_PBS BRDF3_Unity_PBS
		#elif defined(UNITY_PBS_USE_BRDF2)
			#define UNITY_BRDF_PBS BRDF2_Unity_PBS
		#elif defined(UNITY_PBS_USE_BRDF1)
			#define UNITY_BRDF_PBS BRDF1_Unity_PBS
		#else
			#error something broke in auto - choosing BRDF
		#endif
		
	#endif
	
#endif // UNITY_PBS_LIGHTING_INCLUDED
