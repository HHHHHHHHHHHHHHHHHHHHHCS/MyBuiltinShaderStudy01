// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

#ifndef AUTOLIGHT_INCLUDED
	#define AUTOLIGHT_INCLUDED
	
	#include "HLSLSupport.cginc"
	#include "CGIncludes/UnityShadowLibrary.cginc"
	
	// ---- Screen space direction light shadows helpers (any version)
	#if defined(SHADOWS_SCREEN)
		#if defined(UNITY_NO_SCREENSPACE_SHADOWS)
			#define TRANSFER_SHADOW(a) a._ShadowCoord = mul(unity_WorldToShadow[0], mul(unity_ObjectToWorld, v.vertex));
		#else
			#define TRANSFER_SHADOW(a) a._ShadowCoord = ComputeScreenPos(a.pos);
		#endif
		//TODO:
		#define SHADOW_COORDS(idx1) unityShadowCoord4 _ShadowCoord: TEXCOORD##idx1;
		//TODO:
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
