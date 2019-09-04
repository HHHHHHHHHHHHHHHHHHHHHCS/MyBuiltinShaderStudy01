#ifndef UNITY_STANDARD_CORE_FORWARD_SIMPLE_INCLUDED
	#define UNITY_STANDARD_CORE_FORWARD_SIMPLE_INCLUDED
	
	#include "CGIncludes/UnityStandardCore.cginc"
	
	//不支持 : _PARALLAXMAP, DIRLIGHTMAP_COMBINED
	#define GLOSSMAP (defined(_SPECGLOSSMAP) || defined(_METALLICGLOSSMAP))
	
	#ifndef SPECULAR_HIGHLIGHTS
		#define SPECULAR_HIGHLIGHTS (!defined(_SPECULAR_HIGHLIGHTS_OFF))
	#endif // SPECULAR_HIGHLIGHTS
	
	
	#define JOIN2(a, b) a##b
	#define JOIN(a, b) JOIN2(a, b)
	#define UNIFORM_REFLECTIVITY JOIN(UNITY_SETUP_BRDF_INPUT, _Reflectivity)
	
	struct VertexOutputBaseSimple
	{
		//UNITY_POSITION() -> HLSLSupport.cginc    #define UNITY_POSITION(pos) float4 pos : SV_POSITION
		UNITY_POSITION(pos);//切线空间位置
		float4 tex: TEXCOORD0;//UV
		half4 eyeVec: TEXCOORD1; //xyz:世界空间视野角度    w:grazingTerm->光泽度
		
		half4 ambientOrLightmapUV: TEXCOORD2;//球谐颜色 或 Lightmap.xyzw=uv1.xy uv2.xy
		//SHADOW_COORDS() -> AutoLigt.cginc    unityShadowCoord4 _ShadowCoord : TEXCOORD##idx1;
		SHADOW_COORDS(3) //阴影位置
		//UNITY_FOG_COORDS_PACKED() -> UnityCG.ginc    #define UNITY_FOG_COORDS_PACKED(idx, vectype) vectype fogCoord : TEXCOORD##idx;
		UNITY_FOG_COORDS_PACKED(4, half4) //x:fog的UV  yzw:反射角度    x:fogCoord , yzw:reflectVec
		
		half4 normalWorld: TEXCOORD5;//xyz:世界空间normal w:fresnelTerm->菲尼尔用
		
		#ifdef _NORMALMAP
			half3 tangentSpaceLightDir: TEXCOORD6;//切线空间灯光角度
			#if SPECULAR_HIGHLIGHTS
				half3 tangentSpeaceEyeVec: TEXCOORD7;//切线空间视野角度
			#endif
		#endif
		
		#if UNITY_REQUIRE_FRAG_WORLDPOS
			float3 posWorld: TEXCOORD8;//顶点世界空间位置
		#endif
		
		UNITY_VERTEX_OUTPUT_STEREO//合批处理用
	};
	
	
	#ifdef _NORMALMAP
		
		half3 TransformToTangentSpace(half3 tangent, half3 binormal, half3 normal, half3 v)
		{
			// Mali400  更喜欢用half3x3的矩阵的点积表达
			return half3(dot(tangent, v), dot(binormal, v), dot(normal, v));
		}
		
		void TangentSpaceLightingInput(half3 normalWorld, half4 vTangent, half3 lightDirWorld, half3 eyeVecWorld, out half3 tangentSpaceLightDir, out half3 tangentSpaceEyeVec)
		{
			half3 tangentWorld = UnityObjectToWorldDir(vTangent.xyz);
			
			//unity_WorldTransformParams -> UnityShaderVariables.cginc     w通常是1或-1 代表transform.scale 的正负
			half sign = half(vTangent.w) * half(unity_WorldTransformParams.w);
			//副法线
			half3 binormalWorld = cross(normalWorld, tangentWorld) * sign;
			//TBN  切线空间灯光角度
			tangentSpaceLightDir = TransformToTangentSpace(tangentWorld, binormalWorld, normalWorld, lightDirWorld);
			#if SPECULAR_HIGHLIGHTS
				//TBN  切线空间视野角度
				tangentSpaceEyeVec = normalize(TransformToTangentSpace(tangentWorld, binormalWorld, normalWorld, eyeVecWorld));
			#else
				tangentSpaceEyeVec = 0;
			#endif
		}
		
	#endif // _NORMALMAP
	
	VertexOutputBaseSimple vertexForwardBaseSimple(VertexInput v)
	{
		UNITY_SETUP_INSTANCE_ID(v);
		VertexOutputBaseSimple o;
		UNITY_INITIALIZE_OUTPUT(VertexOutputBaseSimple, o);
		UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
		
		float4 posWorld = mul(unity_ObjectToWorld, v.vertex);
		o.pos = UnityObjectToClipPos(v.vertex);
		//TexCoords() -> UnityStandardInput.cginc
		//xy = TRANSFORM_TEX(v.uv0, _MainTex); // Always source from uv0
		//zw = TRANSFORM_TEX(((_UVSec == 0) ? v.uv0 : v.uv1), _DetailAlbedoMap);
		o.tex = TexCoords(v);
		
		half3 eyeVec = normalize(posWorld.xyz - _WorldSpaceCameraPos);
		half3 normalWorld = UnityObjectToWorldNormal(v.normal);
		
		o.normalWorld.xyz = normalWorld;
		o.eyeVec.xyz = eyeVec;
		
		#ifdef _NORMALMAP
			half3 tangentSpaceEyeVec;
			TangentSpaceLightingInput(normalWorld, v.tangent, _WorldSpaceLightPos0.xyz, eyeVec, /*out*/ o.tangentSpaceLightDir, /*out*/ tangentSpaceEyeVec);
			#if SPECULAR_HIGHLIGHTS
				o.tangentSpaceEyeVec = tangentSpaceEyeVec;
			#endif
		#endif
		
		//用来接受阴影  计算阴影空间位置
		//TRANSFER_SHADOW() -> AutoLight.cginc    a._ShadowCoord = mul(unity_WorldToShadow[0], mul(unity_ObjectToWorld, v.vertex ));
		TRANSFER_SHADOW(o);
		
		o.ambientOrLightmapUV = VertexGIForward(v, posWorld, normalWorld);
		
		o.normalWorld.w = Pow4(1 - saturate(dot(normalWorld, -eyeVec)));//菲尼尔用
		#if !GLOSSMAP
		//UNIFORM_REFLECTIVITY() = UNITY_SETUP_BRDF_INPUT_Reflectivity
			o.eyeVec.w = saturate(_Glossiness + UNIFORM_REFLECTIVITY());//TODO:
		#endif
		
		UNITY_TRANSFER_FOG(o, o.pos);
		return o;
	}
	
	
#endif // UNITY_STANDARD_CORE_FORWARD_SIMPLE_INCLUDED
