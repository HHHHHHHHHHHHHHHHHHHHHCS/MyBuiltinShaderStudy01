#ifndef UNITY_STANDARD_INPUT_INCLUDED
	#define UNITY_STANDARD_INPUT_INCLUDED
	
	#include "CGIncludes/UnityStandardUtils.cginc"
	
	
	//---------------------------------------
	half4       _Color;
	half        _Cutoff;
	
	sampler2D   _MainTex;
	float4      _MainTex_ST;
	
	sampler2D   _DetailAlbedoMap;
	float4      _DetailAlbedoMap_ST;
	
	sampler2D   _BumpMap;
	half        _BumpScale;
	
	sampler2D   _DetailMask;
	sampler2D   _DetailNormalMap;
	half        _DetailNormalMapScale;
	
	sampler2D   _SpecGlossMap;
	sampler2D   _MetallicGlossMap;
	half        _Metallic;
	float       _Glossiness;
	float       _GlossMapScale;
	
	sampler2D   _OcclusionMap;
	half        _OcclusionStrength;
	
	sampler2D   _ParallaxMap;
	half        _Parallax;
	half        _UVSec;
	
	half4       _EmissionColor;
	sampler2D   _EmissionMap;
	
	//-------------------------------------------------------------------------------------
	
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
		
		// UnityInstancing.cginc    uint instanceID : SV_InstanceID;
		UNITY_VERTEX_INPUT_INSTANCE_ID
	};
	
	float4 TexCoords(VertexInput v)
	{
		float4 texcoord;
		texcoord.xy = TRANSFORM_TEX(v.uv0, _MainTex); // Always source from uv0
		texcoord.zw = TRANSFORM_TEX(((_UVSec == 0) ? v.uv0: v.uv1), _DetailAlbedoMap);
		return texcoord;
	}
	
	//a是DetailNormal的mask
	half DetailMask(float2 uv)
	{
		return tex2D(_DetailMask, uv).a;
	}
	
	//遮罩
	half Occlusion(float2 uv)
	{
		#if (SHADER_TARGET < 30)
			//SM2.0 : 指令计数器限制   简化  没有lerp
			return tex2D(_OcclusionMap, uv).g;
		#else
			half occ = tex2D(_OcclusionMap, uv).g;
			return LerpOneTo(occ, _OcclusionStrength);
		#endif
	}
	
	half3 Albedo(float4 texcoords)
	{
		half3 albedo = _Color.rgb * tex2D(_MainTex, texcoords.xy).rgb;
		#if _DETAIL
			#if (SHADER_TARGET < 30)
				//SM2.0:因为指令计数器限制 所以没有细节mask
				half mask = 1;
			#else
				half mask = DetailMask(texcoords.xy);
			#endif
			half3 detailAlbedo = tex2D(_DetailAlbedoMap, texcoords.zw).rgb;
			#if _DETAIL_MULX2
				albedo *= LerpWhiteTo(detailAlbedo * unity_ColorSpaceDouble.rgb, mask);
			#elif _DETAIL_MUL
				albedo *= LerpWhiteTo(detailAlbedo, mask);
			#elif _DETAIL_ADD
				albedo += detailAlbedo * mask;
			#elif _DETAIL_LERP
				albedo = lerp(albeodo, detailAlbedo, mask);
			#endif
		#endif
		return albedo;
	}
	
	half Alpha(float2 uv)
	{
		#if defined(_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A)
			return _Color.a;
		#else
			return tex2D(_MainTex, uv).a * _Color.a;
		#endif
	}
	
	half2 MetallicGloss(float2 uv)
	{
		half2 mg;
		
		#ifdef _METALLICGLOSSMAP
			#ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
				mg.r = tex2D(_MetallicGlossMap, uv).r;
				mg.g = tex2D(_MainTex, uv).a;
			#else
				mg = tex2D(_MatallicGlossMap, uv).ra;
			#endif
			mg.g *= _GlossMapScale;
		#else
			mg.r = _Metallic;
			#ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
				mg.g = tex2D(_MainTex, uv).a * _GlossMapScale;
			#else
				mg.g = _Glossiness;
			#endif
		#endif
		
		return mg;
	}
	
	#ifdef _NORMALMAP
		//切线空间的法线 xy是_BumpMap法线uv    zw是_DetailNormalMap法线uv
		half3 NormalInTangentSpace(float4 texcoords)
		{
			half3 normalTangent = UnpackScaleNormal(tex2D(_BumpMap, texcoords.xy), _BumpScale);
			
			#if _DETAIL && defined(UNITY_ENABLE_DETAIL_NORMALMAP)
				half mask = DetailMask(texcoords.xy);//a是DetailNormal的mask
				half3 detailNormalTangent = UnpackScaleNormal(tex2D(_DetailNormalMap, texcoords.zw), _DetailNormalMapScale);
				
				#if _DETAIL_LERP
					normalTangent = lerp(normalTangent, detailNormalTangent, mask);
				#else
					normalTangent = lerp(normalTangent, BlendNormals(normalTangent, detailNormalTangent), mask);
				#endif
			#endif
			
			return normalTangent;
		}
		
	#endif
	
	half3 Emission(float2 uv)
	{
		#ifndef _EMISSION
			return 0;
		#else
			return tex2D(_EmissionMap, uv).rgb * _EmissionColor.rgb;
		#endif
	}
	
#endif // UNITY_STANDARD_INPUT_INCLUDED