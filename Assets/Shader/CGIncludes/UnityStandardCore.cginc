#ifndef UNITY_STANDARD_CORE_INCLUDED
	#define UNITY_STANDARD_CORE_INCLUDED
	
	#include "CGIncludes/UnityStandardInput.cginc"
	#include "AutoLight.cginc"
	
	
	inline half4 VertexGIForward(VertexInput v, float3 posWorld, half3 normalWorld)
	{
		half4 ambientOrLightmapUV = 0;
		//如果使用了Lightmaps
		#ifdef LIGHTMAP_ON
			ambientOrLightmapUV.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
			ambientOrLightmapUV.zw = 0;
			// 仅用于动态对象的采样光探头（无静态或动态光照图）
		#elif UNITY_SHOULD_SAMPLE_SH
			#ifdef VERTEXLIGHT_ON
				//Shade4PointLights() -> UnityCG.cginc
				//如果使用了顶点光  则计算前四个非重要的点光源的近似光照
				ambientOrLightmapUV.rgb = Shade4PointLights(unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
				unity_LightColor[0].rgb, unity_LightColor[1].rgb, unity_LightColor[2].rgb, unity_LightColor[3].rgb,
				unity_4LightAtten0, posWorld, normalWorld);
			#endif
			
			//ShadeSHPerVertex() -> UnityStandardUtils.cginc  计算球谐光
			ambientOrLightmapUV.rgb = ShadeSHPerVertex(normalWorld, ambientOrLightmapUV.rgb);
		#endif
		
		#ifdef DYNAMICLIGHTMAP_ON
			//如果开启了动态光  则 zw为UV2
			ambientOrLightmapUV.zw = v.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
		#endif
		
		return ambientOrLightmapUV;
	}
	
	
#endif // UNITY_STANDARD_CORE_INCLUDED
