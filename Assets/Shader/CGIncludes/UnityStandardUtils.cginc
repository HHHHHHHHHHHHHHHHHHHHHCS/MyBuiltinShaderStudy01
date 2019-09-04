#ifndef UNITY_STANDARD_UTILS_INCLUDED
	#define UNITY_STANDARD_UTILS_INCLUDED
	
	#include "CGIncludes/UnityCG.cginc"
	#include "UnityStandardConfig.cginc"
	
	//计算球谐光
	half3 ShadeSHPerVertex(half3 normal, half3 ambient)
	{
		#if UNITY_SAMPLE_FULL_SH_PER_PIXEL
			//如果是完全按像素计算,则此处不做任何操作
		#elif (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE
			//完全按照顶点计算
			ambient += max(half3(0, 0, 0), ShadeSH9(half4(normal, 1.0)));
		#else
			// L2 per-vertex, L0..L1 & gamma-correction per-pixel
			
			// NOTE: SH data is always in Linear AND calculation is split between vertex & pixel
			// Convert ambient to Linear and do final gamma-correction at the end (per-pixel)
			#ifdef UNITY_COLORSPACE_GAMMA
				ambient = GammaToLinearSpace(ambient);//TODO:
			#endif
			ambient += SHEvalLinearL2(half4(normal, 1.0));     // no max since this is only L2 contribution
		#endif
		
		return ambient;
	}
	
	
#endif // UNITY_STANDARD_UTILS_INCLUDED
