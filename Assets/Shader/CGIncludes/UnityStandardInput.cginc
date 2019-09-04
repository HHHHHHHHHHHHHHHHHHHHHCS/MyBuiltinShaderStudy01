#ifndef UNITY_STANDARD_INPUT_INCLUDED
	#define UNITY_STANDARD_INPUT_INCLUDED
	
	#include "CGIncludes/UnityStandardUtils.cginc"
	
	struct VertexInput
	{
		float4 vertex: POSITION;
		half3 normal: NORMAL;
		float2 uv0: TEXCOORD0;
		float2 uv1: TEXCOORD1;
		#if defined(DYNAMICLIGHTMAP_ON) || defined(UNITY_PASS_META)
			float2 uv2: TEXCOORD2;
		#endif
		#ifdef _TANGENT_TO_WORLD
			half4 tangent: TANGENT;
		#endif
		
		UNITY_VERTEX_INPUT_INSTANCE_ID
	};
	
#endif // UNITY_STANDARD_INPUT_INCLUDED