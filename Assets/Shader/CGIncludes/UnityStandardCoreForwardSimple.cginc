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
	//UNITY_SETUP_BRDF_INPUT -> MetallicSetup    MetallicSetup_Reflectivity
	#define UNIFORM_REFLECTIVITY JOIN(UNITY_SETUP_BRDF_INPUT, _Reflectivity)
	
	#if !SPECULAR_HIGHLIGHTS
		#define REFLECTVEC_FOR_SPECULAR(i, s) half3(0, 0, 0)
	#elif defined(_NORMALMAP)
		#define REFLECTVEC_FOR_SPECULAR(i, s) reflect(i.tangentSpaceEyeVec, s.tangentSpaceNormal)
	#else
		#define REFLECTVEC_FOR_SPECULAR(i, s) s.reflUVW
	#endif
	
	struct VertexOutputBaseSimple
	{
		//UNITY_POSITION() -> HLSLSupport.cginc    #define UNITY_POSITION(pos) float4 pos : SV_POSITION
		UNITY_POSITION(pos);//切线空间位置
		float4 tex: TEXCOORD0;//UV
		//xyz:世界空间视野角度
		//w:grazingTerm->光泽度 =smooth + metallic or 直接使用贴图的值
		half4 eyeVec: TEXCOORD1;
		
		half4 ambientOrLightmapUV: TEXCOORD2;//球谐颜色 或 Lightmap.xyzw=uv1.xy uv2.xy
		//SHADOW_COORDS() -> AutoLigt.cginc    unityShadowCoord4 _ShadowCoord : TEXCOORD##idx1;
		SHADOW_COORDS(3) //阴影位置
		//UNITY_FOG_COORDS_PACKED() -> UnityCG.ginc    #define UNITY_FOG_COORDS_PACKED(idx, vectype) vectype fogCoord : TEXCOORD##idx;
		UNITY_FOG_COORDS_PACKED(4, half4) //x:fog的UV  yzw:反射角度    x:fogCoord , yzw:reflect eye
		
		half4 normalWorld: TEXCOORD5;//xyz:世界空间normal w:fresnelTerm->菲尼尔用
		
		#ifdef _NORMALMAP
			half3 tangentSpaceLightDir: TEXCOORD6;//切线空间灯光角度
			#if SPECULAR_HIGHLIGHTS
				half3 tangentSpeaceEyeVec: TEXCOORD7;//切线空间视野角度
			#endif
		#endif
		
		//Unity在片元需要世界位置
		#if UNITY_REQUIRE_FRAG_WORLDPOS
			float3 posWorld: TEXCOORD8;//顶点世界空间位置
		#endif
		
		UNITY_VERTEX_OUTPUT_STEREO//合批处理用
	};
	
	//计算金属度反射
	half MetallicSetup_Reflectivity()
	{
		return 1.0h - OneMinusReflectivityFromMetallic(_Metallic);
	}
	
	//计算高光反射度
	half SpecularSetup_Reflectivity()
	{
		//_SpecColor 是Unity 自带的
		return SpecularStrength(_SpecColor.rgb);
	}
	
	//smoothness + metallic or 贴图颜色
	half PerVertexGrazingTerm(VertexOutputBaseSimple i, FragmentCommonData s)
	{
		#if GLOSSMAP
			return saturate(s.smoothness + (1 - s.oneMinusReflectivity));
		#else
			return i.eyeVec.w;
		#endif
	}
	
	//normalWorld的W存的是菲尼尔值
	//计算方法是 Pow4(1 - saturate(dot(normalWorld, -eyeVec)))
	half PerVertexFresnelTerm(VertexOutputBaseSimple i)
	{
		return i.normalWorld.w;
	}
	
	//根据是否开启发现 使用选择用那个空间下的灯光方向
	half3 LightDirForSpecular(VertexOutputBaseSimple i, UnityLight mainLight)
	{
		#if SPECULAR_HIGHLIGHTS && defined(_NORMALMAP)
			return i.tangentSpaceLightDir;
		#else
			return mainLight.dir;
		#endif
	}
	
	//平行光的计算
	half3 BRDF3DirectSimple(half3 diffColor, half3 specColor, half smoothness, half rl)
	{
		//是否要计算高光
		#if SPECULAR_HIGHLIGHTS
			return BRDF3_Direct(diffColor, specColor, Pow4(rl), smoothness);
		#else
			return diffColor;
		#endif
	}
	
	FragmentCommonData FragmentSetupSimple(VertexOutputBaseSimple i)
	{
		half alpha = Alpha(i.tex.xy);
		#if defined(_ALPHATEST_ON)
			clip(alpha - _Cutoff);
		#endif
		
		//MetallicSetup
		FragmentCommonData s = UNITY_SETUP_BRDF_INPUT(i.tex);
		
		//注意：着色器依赖于预乘alpha混合(_srcblund=one，_dstblund=oneminussrcalpha)
		s.diffColor = PreMultiplyAlpha(s.diffColor, alpha, s.oneMinusReflectivity, /*out*/ s.alpha);
		
		s.normalWorld = i.normalWorld.xyz;
		s.eyeVec = i.eyeVec.xyz;
		s.posWorld = IN_WORLDPOS(i);
		s.reflUVW = i.fogCoord.yzw;
		
		#ifdef _NORMALAMP
			s.tangentSpaceNormal = NormalInTangentSpace(i.tex);
		#else
			s.tangentSpaceNormal = 0;
		#endif
		
		return s;
	}
	
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
	
	UnityLight MainLightSimple(VertexOutputBaseSimple i, FragmentCommonData s)
	{
		UnityLight mainLight = MainLight();
		return mainLight;
	}
	
	VertexOutputBaseSimple vertForwardBaseSimple(VertexInput v)
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
		
		o.fogCoord.yzw = reflect(eyeVec, normalWorld);
		
		o.normalWorld.w = Pow4(1 - saturate(dot(normalWorld, -eyeVec)));//菲尼尔用
		#if !GLOSSMAP
			//UNIFORM_REFLECTIVITY() = MetallicSetup_Reflectivity()
			o.eyeVec.w = saturate(_Glossiness + UNIFORM_REFLECTIVITY());
		#endif
		
		UNITY_TRANSFER_FOG(o, o.pos);
		return o;
	}
	
	half4 fragForwardBaseSimpleInternal(VertexOutputBaseSimple i)
	{
		UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);
		
		FragmentCommonData s = FragmentSetupSimple(i);
		
		UnityLight mainLight = MainLightSimple(i, s);
		
		#if !defined(_LIGHTMAP_ON) && defined(_NORMALMAP)
			//i.tangentSpaceLightDir(切线空间下) == mainLight.dir == _WolrdSpaceLightPos0.xyz
			half ndotl = saturate(dot(s.tangentSpaceNormal, i.tangentSpaceLightDir));
		#else
			half ndotl = saturate(dot(s.normalWorld, mainLight.dir));
		#endif
		
		//这里不能有worldpos(在sm 2.0上没有足够的插值器),所以在这种情况下不会有阴影褪色
		//UnitySampleBakedOcclusion 是 烘焙的光照阴影遮挡  跟 unity_ShadowMask 和 光照探针有关
		half shadowMaskAttenuation = UnitySampleBakedOcclusion(i.ambientOrLightmapUV, 0);
		//SHADOW_ATTENUATION 是阴影强度(衰减) 0代表全黑的   跟shadowMap 有关
		half realtimeShadowAttenuation = SHADOW_ATTENUATION(i);
		//根据实时的阴影和烘焙的阴影  算出要的阴影
		half atten = UnityMixRealtimeAndBakedShadows(realtimeShadowAttenuation, shadowMaskAttenuation, 0);
		
		//遮罩
		half occlusion = Occlusion(i.tex.xy);
		//dot(Refl(eyeView),lightDir)
		half rl = dot(REFLECTVEC_FOR_SPECULAR(i, s), LightDirForSpecular(i, mainLight));
		
		//计算GI和环境光
		UnityGI gi = FragmentGI(s, occlusion, i.ambientOrLightmapUV, atten, mainLight);
		//lightColor 衰减
		half3 attenuatedLightColor = gi.light.color * ndotl;
		
		half3 c = 0;
		//间接光
		c += BRDF3_Indirect(s.diffColor, s.specColor, gi.indirect, PerVertexGrazingTerm(i, s), PerVertexFresnelTerm(i));
		//叠加  平行高光 * 间接光衰减
		c += BRDF3DirectSimple(s.diffColor, s.specColor, s.smoothness, rl) * attenuatedLightColor;
		//自发光
		c += Emission(i.tex.xy);
		
		UNITY_APPLY_FOG(i.fogCoord, c);
		
		return OutputForward(half4(c, 1), s.alpha);
	}
	
	
#endif // UNITY_STANDARD_CORE_FORWARD_SIMPLE_INCLUDED
