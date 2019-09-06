#ifndef UNITY_STANDARD_CORE_INCLUDED
	#define UNITY_STANDARD_CORE_INCLUDED
	
	#include "CGIncludes/UnityStandardInput.cginc"
	#include "CGIncludes/UnityStandardBRDF.cginc"
	#include "CGIncludes/AutoLight.cginc"
	
	
	//正常在Standard.shader 定义的是 MetallicSetup
	#ifndef UNITY_SETUP_BRDF_INPUT
		#define UNITY_SETUP_BRDF_INPUT SpecularSetup
	#endif
	
	struct FragmentCommonData
	{
		half3 diffColor, specColor;
		
		//1-反射率 和 平滑度 主要用于DX9 SM2.0级别
		//大部分的计算都在这些 (1-反射率)  的值 上完成 , 这就节省了宝贵的ALU插值
		half oneMinusReflectivity, smoothness;
		float3 normalWorld;
		float3 eyeVec;
		half alpha;
		float3 posWorld;
		
		#if UNITY_STANDARD_SIMPLE
			half3 reflUVW;
		#endif
		
		#if UNITY_STANDARD_SIMPLE
			half3 tangentSpaceNormal;
		#endif
	};
	
	UnityLight MainLight()
	{
		UnityLight l;
		
		l.color = _LightColor0.rgb;
		l.dir = _WorldSpaceLightPos0.xyz;
		return l;
	}
	
	#if UNITY_REQUIRE_FRAG_WORLDPOS
		#if UNITY_PACK_WORLDPOS_WITH_TANGENT
			#define IN_WORLDPOS(i) half3(i.tangentToWorldAndPackedData[0].w, i.tangentToWorldAndPackedData[1].w, i.tangentToWorldAndPackedData[2].w)
		#else
			#define IN_WORLDPOS(i) i.posWorld
		#endif
	#else
		#define IN_WORLDPOS(i) half3(0, 0, 0)
	#endif
	
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
	
	//i_tex  xy是uv0  zw由Enum决定uv1还是uv2
	inline FragmentCommonData MetallicSetup(float4 i_tex)
	{
		half2 metallicGloss = MetallicGloss(i_tex.xy);
		half metallic = metallicGloss.x;
		half smoothness = metallicGloss.y;//这是 (1-实际粗糙度m) 的平方根
		
		half oneMinusReflectivity;
		half3 specColor;
		//DiffuseAndSpecularFromMetallic -> UnityStandardCore.cginc 根据金属度得到Diffuse和Specular
		half3 diffColor = DiffuseAndSpecularFromMetallic(Albedo(i_tex), metallic, /*out*/ specColor, /*out*/ oneMinusReflectivity);
		
		FragmentCommonData o = (FragmentCommonData)0;
		o.diffColor = diffColor;
		o.specColor = specColor;
		o.oneMinusReflectivity = oneMinusReflectivity;
		o.smoothness = smoothness;
		
		return o;
	}
	
	
#endif // UNITY_STANDARD_CORE_INCLUDED
