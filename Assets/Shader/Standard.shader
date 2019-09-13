Shader "HCS/Standard"
{
	Properties
	{
		_Color ("Color", Color) = (1, 1, 1, 1)
		_MainTex ("Albedo", 2D) = "white" { }
		
		_Cutoff ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
		
		_Glossiness ("Smoothness", Range(0.0, 1.0)) = 0.5
		_GlossMapScale ("Smoothness Scale", Range(0.0, 1.0)) = 1.0
		[Enum(Metallic Alpha, 0, Albedo Alpha, 1)] _SmoothnessTextureChannel ("Smoothness texture channel", Float) = 0
		
		[Gamma]_Metallic ("Metaliic", Range(0.0, 1.0)) = 0.0
		_MetallicGlossMap ("Metallic", 2D) = "white" { }
		
		[ToggleOff]_SpecularHighlights ("Specular Highlights", Float) = 1.0
		[ToggleOff]_GlossyReflections ("Glossy Reflections", Float) = 1.0
		
		_BumpScale ("Scale", Float) = 1.0
		[Normal] _BumpMap ("Normal Map", 2D) = "bump" { }
		
		_Parallax ("Height Scale", Range(0.005, 0.08)) = 0.02
		_ParallaxMap ("Height Map", 2D) = "black" { }
		
		_OcclusionStrength ("Strength", Range(0.0, 1.0)) = 1.0
		_OcclusionMap ("Occlusion", 2D) = "white" { }
		
		_EmissionColor ("Color", Color) = (0, 0, 0)
		_EmissionMap ("Emission", 2D) = "white" { }
		
		_DetailMask ("Detail Mask", 2D) = "white" { }
		
		_DetailAlbedoMap ("Detail Albedo x2", 2D) = "grey" { }
		_DetailNormalMapScale ("Scale", Float) = 1.0
		[Normal]_DetailNormalMap ("Normal Map", 2D) = "bump" { }
		
		[Enum(UV0, 0, UV1, 1)] _UVSec ("UV Set for secondary textures", Float) = 0
		
		[HideInInspector]_Mode ("__mode", Float) = 0.0
		[HideInInspector]_SrcBlend ("__src", Float) = 1.0
		[HideInInspector]_DstBlend ("__dst", Float) = 0.0
		[HideInInspector]_ZWrite ("__zw", Float) = 1.0
	}
	
	CGINCLUDE
	//决定用 SpecularSetup 还是 MetallicSetup
	#define UNITY_SETUP_BRDF_INPUT MetallicSetup
	ENDCG
	
	SubShader
	{
		Tags { "RenderType" = "Opaque" "PerformanceChecks" = "False" }
		LOD 300
		
		// ------------------------------------------------------------------
		//  Base forward pass (directional light, emission, lightmaps, ...)
		Pass
		{
			Name "FORWARD"
			Tags { "LightMode" = "ForwardBase" }
			
			Blend[_SrcBlend][_DstBlend]
			ZWrite[_ZWrite]
			
			CGPROGRAM
			
			#pragma target 3.0
			
			//这个宏是使用低效果,高性能的效果
			//#define UNITY_NO_FULL_STANDARD_SHADER
			
			#pragma shader_feature _NORMALMAP
			//最多声明256个全局 其中一个技巧是使用 _   代表不用A和A
			//multi_complie_local来声明局部的 最多可以包含64个local Keyword
			#pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			//Base Pass有自发光  Add Pass 没有自发光
			#pragma shader_feature _EMISSION
			#pragma shader_feature_local _METALLICGLOSSMAP
			#pragma shader_feature_local _DETAIL_MULX2
			#pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature_local _SPECULARHIGHLIGHTS_OFF
			#pragma shader_feature_local _GLOSSYREFLECTIONS_OFF
			#pragma shader_feature_local _PARALLAXMAP
			
			#pragma multi_compile_fwdbase
			#pragma multi_compile_fog
			//会使你的Shader生成两个变体,其中一个定义了Shader关键字INSTANCING_ON,另外一个没有定义此关键字。
			//开启这将使得着色器有变体,来支持几个实例化关键字
			#pragma multi_compile_instancing
			
			// 取消对以下行的注释以启用抖动LOD交叉淡入淡出。注意：对于其他传递，文件中还有更多要取消注释的内容。
			//#pragma multi_compile _  LOD_FADE_CROSSFADE
			
			#pragma vertex vertBase
			#pragma fragment fragBase
			
			
			#include "CGIncludes/UnityStandardCoreForward.cginc"
			
			
			ENDCG
			
		}
		/*
		// ------------------------------------------------------------------
		//  Additive forward pass (每一盏Additive光,会进行一次渲染)
		Pass
		{
			Name "FORWARD_DELTA"
			Tags { "LightMode" = "ForwardAdd" }
			Blend [_SrcBlend] One
			Fog
			{
				Color(0, 0, 0, 0)
			}//AddPass  Fog 应该是不可见的
			ZWrite Off
			ZTest LEqual
			
			CGPROGRAM
			
			#pragma target 3.0
			
			
			#pragma shader_feature _NORMALMAP
			#pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature_local _METALLICGLOSSMAP
			#pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature_local _SPECULARHIGHLIGHTS_OFF
			#pragma shader_feature_local _DETAIL_MULX2
			#pragma shader_feature_local _PARALLAXMAP
			
			#pragma multi_compile_fwdadd_fullshadows
			#pragma multi_compile_fog
			//#pragma multi_compile _ LOD_FADE_CROSSFADE
			
			#pragma vertex vertAdd
			#pragma fragment fragAdd
			#include "UnityStandardCoreForward.cginc"
			
			ENDCG
			
		}
		
		// ------------------------------------------------------------------
		//  Deferred pass
		Pass
		{
			Name "DEFERRED"
			Tags { "LightMode" = "Deferred" }
			
			CGPROGRAM
			
			#pragma target 3.0
			//排除了不支持mrt 的设备
			#pragma exclude_renderers nomrt
			
			#pragma shader_feature _NORMALMAP
			#pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature _EMISSION
			#pragma shader_feature_local _METALLICGLOSSMAP
			#pragma shader_feature_local _DETAIL_MULX2
			#pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature_local _SPECULARHIGHLIGHTS_OFF
			#pragma shader_feature_local _GLOSSYREFLECTIONS_OFF
			#pragma shader_feature_local _PARALLAXMAP
			
			//延迟渲染final pass (applies lighting & textures).  延迟渲染合批次用
			#pragma multi_compile_prepassfinal
			#pragma multi_compile_instancing
			//#pragma multi_compile _ LOD_FADE_CROSSFADE
			
			#pragma vertex vertDeferred
			#pragma fragment fragDeferred
			
			#include "UnityStandardCore.cginc"
			
			ENDCG
			
		}
		
		// ------------------------------------------------------------------
		//提取光照映射信息，gi(发射，反照率，…)用于烘焙 , 常规渲染用不到
		Pass
		{
			Name"META"
			Tags { "LightMode" = "Meta" }
			
			Cull Off
			
			CGPROGRAM
			
			#pragma vertex vert_meta
			#pragma fragment frag_meta
			
			#pragma shader_feature _EMISSION
			#pragma shader_feature_local _METALLICGLOSSMAP
			#pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature_local _DETAIL_MULX2
			#pragma shader_feature EDITOR_VISUALIZATION
			
			#include "UnityStandardMeta.cginc"
			ENDCG
			
		}
		*/
	}
	
	/*
	SubShader
	{
		//不支持 target 3.0  改用2.0
		Tags { "RenderType" = "Opaque" "PerformanceChecks" = "False" }
		LOD 150
		
		// ------------------------------------------------------------------
		//  Base forward pass (directional light, emission, lightmaps, ...)
		Pass
		{
			Name "FORWARD"
			Tags { "LightMode" = "ForwardBase" }
			
			Blend [_SrcBlend] [_DstBlend]
			ZWrite [_ZWrite]
			
			CGPROGRAM
			
			#pragma target 2.0
			
			#pragma shader_feature _NORMALMAP
			#pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature _EMISSION
			#pragma shader_feature_local _METALLICGLOSSMAP
			#pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature_local _SPECULARHIGHLIGHTS_OFF
			#pragma shader_feature_local _GLOSSYREFLECTIONS_OFF
			// SM2.0: NOT SUPPORTED shader_feature_local _DETAIL_MULX2
			// SM2.0: NOT SUPPORTED shader_feature_local _PARALLAXMAP
			
			//skip_variants忽略一些变量
			#pragma skip_variants SHADOWS_SOFT DIRLIGHTMAP_COMBINED
			
			#pragma multi_compile_fwdbase
			#pragma multi_compile_fog
			
			#pragma vertex vertBase
			#pragma fragment fragBase
			#include "UnityStandardCoreForward.cginc"
			
			ENDCG
			
		}
		// ------------------------------------------------------------------
		//  Additive forward pass (one light per pass)
		Pass
		{
			Name "FORWARD_DELTA"
			Tags { "LightMode" = "ForwardAdd" }
			Blend [_SrcBlend] One
			Fog
			{
				Color(0, 0, 0, 0)
			}// in additive pass fog should be black
			ZWrite Off
			ZTest LEqual
			
			CGPROGRAM
			
			#pragma target 2.0
			
			#pragma shader_feature _NORMALMAP
			#pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature_local _METALLICGLOSSMAP
			#pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature_local _SPECULARHIGHLIGHTS_OFF
			#pragma shader_feature_local _DETAIL_MULX2
			// SM2.0: NOT SUPPORTED shader_feature_local _PARALLAXMAP
			#pragma skip_variants SHADOWS_SOFT
			
			#pragma multi_compile_fwdadd_fullshadows
			#pragma multi_compile_fog
			
			#pragma vertex vertAdd
			#pragma fragment fragAdd
			#include "UnityStandardCoreForward.cginc"
			
			ENDCG
			
		}
		// ------------------------------------------------------------------
		//  Shadow rendering pass
		Pass
		{
			Name "ShadowCaster"
			Tags { "LightMode" = "ShadowCaster" }
			
			ZWrite On ZTest LEqual
			
			CGPROGRAM
			
			#pragma target 2.0
			
			#pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature_local _METALLICGLOSSMAP
			#pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma skip_variants SHADOWS_SOFT
			#pragma multi_compile_shadowcaster
			
			#pragma vertex vertShadowCaster
			#pragma fragment fragShadowCaster
			
			#include "UnityStandardShadow.cginc"
			
			ENDCG
			
		}
		
		// ------------------------------------------------------------------
		// Extracts information for lightmapping, GI (emission, albedo, ...)
		// This pass it not used during regular rendering.
		Pass
		{
			Name "META"
			Tags { "LightMode" = "Meta" }
			
			Cull Off
			
			CGPROGRAM
			
			#pragma vertex vert_meta
			#pragma fragment frag_meta
			
			#pragma shader_feature _EMISSION
			#pragma shader_feature_local _METALLICGLOSSMAP
			#pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature_local _DETAIL_MULX2
			#pragma shader_feature EDITOR_VISUALIZATION
			
			#include "UnityStandardMeta.cginc"
			ENDCG
			
		}
	}
	
	FallBack "VertexLit"
	*/

	CustomEditor "StandardShaderGUI"
}
