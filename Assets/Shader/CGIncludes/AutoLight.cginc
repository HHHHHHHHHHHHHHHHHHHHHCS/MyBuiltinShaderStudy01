// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

#ifndef AUTOLIGHT_INCLUDED
	#define AUTOLIGHT_INCLUDED
	
	#include "HLSLSupport.cginc"
	#include "CGIncludes/UnityShadowLibrary.cginc"
	
	// ---- Screen space direction light shadows helpers (any version)
	#if defined(SHADOWS_SCREEN)
		#if defined(UNITY_NO_SCREENSPACE_SHADOWS)
			UNITY_DECLARE_SHADOWMAP(_ShadowMapTexture);
			#define TRANSFER_SHADOW(a) a._ShadowCoord = mul(unity_WorldToShadow[0], mul(unity_ObjectToWorld, v.vertex));
			inline fixed unitySampleShadow(unityShadowCoord4 shadowCoord)
			{
				#if defined(SHADOWS_NATIVE)
					//UNITY_SAMPLE_SHADOW() -> SAMPLE_DEPTH_TEXTURE (SAMPLE_DEPTH_TEXTURE(tex,xy) < z) ? 0.0 : 1.0
					fixed shadow = UNITY_SAMPLE_SHADOW(_ShadowMapTexture, shadowCoord.xyz);
					shadow = _LightShadowData.r + shadow * (1 - _LightShadowData.r);
					return shadow;
				#else
					unityShadowCoord dist = SAMPLE_DEPTH_TEXTURE(_ShadowMapTexture, shadowCoord.xy);
					unityShadowCoord lightShadowDataX = _LightShadowData.x;
					//shadowCoord.z是阀值 大于某个就是阴影
					unityShadowCoord threshold = shadowCoord.z;
					return max(dist > threshold, lightShadowDataX);
				#endif
			}
		#else
			//UNITY_DECLARE_SCREENSPACE_SHADOWMAP -> sampler2D
			UNITY_DECLARE_SCREENSPACE_SHADOWMAP(_ShadowMapTexture);
			#define TRANSFER_SHADOW(a) a._ShadowCoord = ComputeScreenPos(a.pos);
			inline fixed unitySampleShadow(unityShadowCoord4 shadowCoord)
			{
				//UNITY_SAMPLE_SCREEN_SHADOW() -> tex2Dproj( tex, UNITY_PROJ_COORD(uv) ).r
				fixed shadow = UNITY_SAMPLE_SCREEN_SHADOW(_ShadowMapTexture, shadowCoord);
				return shadow;
			}
		#endif
		#define SHADOW_COORDS(idx1) unityShadowCoord4 _ShadowCoord: TEXCOORD##idx1;
		#define SHADOW_ATTENUATION(a) unitySampleShadow(a._ShadowCoord)
	#endif
	
	// ---- Spot light shadows
	#if defined(SHADOWS_DEPTH) && defined(SPOT)
		#define SHADOW_COORDS(idx1) unityShadowCoord4 _ShadowCoord: TEXCOORD##idx1;
		#define TRANSFER_SHADOW(a) a._ShadowCoord = mul(unity_WorldToShadow[0], mul(unity_ObjectToWorld, v.vertex));
		#define SHADOW_ATTENUATION(a) UnitySampleShadowmap(a._ShadowCoord)
	#endif
	
	// ---- Point light shadows
	#if defined(SHADOWS_CUBE)
		#define SHADOW_COORDS(idx1) unityShadowCoord3 _ShadowCoord: TEXCOORD##idx1;
		#define TRANSFER_SHADOW(a) a._ShadowCoord.xyz = mul(unity_ObjectToWorld, v.vertex).xyz - _LightPositionRange.xyz;
		#define SHADOW_ATTENUATION(a) UnitySampleShadowmap(a._ShadowCoord)
	#endif
	
	// ---- Shadows off
	#if !defined(SHADOWS_SCREEN) && !defined(SHADOWS_DEPTH) && !defined(SHADOWS_CUBE)
		
		#define SHADOW_COORDS(idx1)
		#define TRANSFER_SHADOW(a)
		#define SHADOW_ATTENUATION(a) 1.0
	#endif
	
#endif
