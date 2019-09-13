#ifndef UNITY_STANDARD_CORE_INCLUDED
	#define UNITY_STANDARD_CORE_INCLUDED
	
	#include "CGIncludes/UnityStandardInput.cginc"
	#include "CGIncludes/UnityStandardBRDF.cginc"
	#include "CGIncludes/AutoLight.cginc"
	#include "CGIncludes/UnityPBSLighting.cginc"
	
	
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
	
	half3 NormalizePerVertexNormal(float3 n)
	{
		//如果SM2.0 或者 想要优化计算
		//则在顶点阶段 直接normalize
		//否则在像素阶段 normalize
		#if (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE
			return normalize(n);
		#else
			return n;
		#endif
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
	
	half4 OutputForward(half4 output, half alphaFormSurface)
	{
		//开启Alpha
		#if defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
			output.a = alphaFormSurface;
		#else //如果没有开启Alpha  则直接用 1
			UNITY_OPAQUE_ALPHA(output.a);
		#endif
		return output;
	}
	
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
		
		//DYNAMICLIGHTMAP_ON也就是打开了realtime GI，这样的话，又会多一套realtime GI lightmap，计算方式同上，计算的结果也将加入间接光照的diffuse部分
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
	
	inline UnityGI FragmentGI(FragmentCommonData s, half occlusion, half4 i_ambientOrLightmapUV, half atten, UnityLight light, bool reflections)
	{
		UnityGIInput d;
		d.light = light;
		d.worldPos = s.posWorld;
		d.worldViewDir = -s.eyeVec;
		d.atten = atten;
		#if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
			d.ambient = 0;
			d.lightmapUV = i_ambientOrLightmapUV;
		#else
			d.ambient = i_ambientOrLightmapUV.rgb;
			d.lightmapUV = 0;
		#endif
		
		d.probeHDR[0] = unity_SpecCube0_HDR;//unity_SpecCube0包含了现在激活的反射探头,unity_SpecCube0_HDR是其HDR颜色数据
		d.probeHDR[1] = unity_SpecCube1_HDR;//unity_SpecCube1包含了现在激活的反射探头,unity_SpecCube1_HDR是其HDR颜色数据
		
		//UNITY_SPECCUBE_BLENDING 是 启用反射球混合宏
		/*
		不管是reflection probe还是skybox，其本质上它使用的是cubemap，保存它周围的环境信息。
		然而如果把这个环境信息当做球来判断，在数学上，其实是把它当做一个无穷远来工作的。
		这个时候如果用反射探针来抓取一个室内场景，也就是一个空间有限的场景，则会得到一个错误的矫正结果，
		因为你本质上抓的这个cubemap是一个空间有限的范围，但是计算的时候是按照空间无限远的范围来计算的，这个时候就会带来精度误差。
		所以说如果想做到精确反射，则可以使用box projection，也就是打开了这里的宏UNITY_SPECCUBE_BOX_PROJECTION，通过数学上的小技巧进行校正。
		其中具体的数学技巧有兴趣的可以去看下GPU Gems中介绍IBL的一篇文章
		*/
		#if defined(UNITY_SPECCUBE_BLENDING) || defined(UNITY_SPECCUBE_BOX_PROJECTION)
			d.boxMin[0] = unity_SpecCube0_BoxMin;//.w 是 lerp value 用于混合
		#endif
		
		#ifdef UNITY_SPECCUBE_BOX_PROJECTION
			d.boxMax[0] = unity_SpecCube0_BoxMax;
			d.probePosition[0] = unity_SpecCube0_ProbePosition;
			d.boxMax[1] = unity_SpecCube1_BoxMax;
			d.boxMin[1] = unity_SpecCube1_BoxMin;
			d.probePosition[1] = unity_SpecCube1_ProbePosition;
		#endif
		
		if (reflections)
		{
			Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(s.smoothness, -s.eyeVec, s.normalWorld, s.specColor);
			//如果refluvw已在顶点着色器中计算，则替换它。注意：编译器将在unityglossy环境中优化计算安装程序本身
			#if UNITY_STANDARD_SIMPLE
				g.reflUVW = s.reflUVW;
			#endif
			
			//有环境反射球 就计算环境反射球和GI
			return UnityGlobalIllumination(d, occlusion, s.normalWorld, g);
		}
		else
		{
			//否则直接就直接计算GI
			return UnityGlobalIllumination(d, occlusion, s.normalWorld);
		}
	}
	
	inline UnityGI FragmentGI(FragmentCommonData s, half occlusion, half4 i_ambientOrLightmapUV, half atten, UnityLight light)
	{
		return FragmentGI(s, occlusion, i_ambientOrLightmapUV, atten, light, true);
	}
	
	VertexOutputForwardBase vertForwardBase(VertexInput v)
	{
		UNITY_SETUP_INSTANCE_ID(v);
		VertexOutputForwardBase o;
		UNITY_INITIALIZE_OUTPUT(VertexOutputForwardBase, o);
		UNITY_TRANSFER_INSTANCE_ID(v, o);
		
		float4 posWorld = mul(unity_ObjectToWorld, v.vertex);
		#if UNITY_REQUIRE_FRAG_WORLDPOS
			#if UNITY_PACK_WORLD_WITH_TANGENT
				o.tangentToWorldAndPackedData[0].w = posWorld.x;
				o.tangentToWorldAndPackedData[1].w = posWorld.y;
				o.tangentToWorldAndPackedData[2].w = posWorld.z;
			#else
				o.posWorld = posWorld.xyz;
			#endif
		#endif
		
		//虽然也可以用 UnityObjectToClipPos() ->  mul(UNITY_MATRIX_VP, mul(unity_ObjectToWorld, float4(pos, 1.0)))
		o.pos = mul(UNITY_MATRIX_VP, posWorld);
		
		o.tex = TexCoords(v);
		o.eyeVec.xyz = NormalizePerVertexNormal(posWorld.xyz - _WorldSpaceCameraPos);
		float3 normalWorld = UnityObjectToWorldNormal(v.normal);
		
		#ifdef _TANGENT_TO_WORLD
			float4 tangentWorld = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tanget.w);
			
			float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld.xyz, tangentWorld.w);
			o.tangentToWorldAndPackedData[0].xyz = tangentToWorld[0];
			o.tangentToWorldAndPackedData[1].xyz = tangentToWorld[1];
			o.tangentToWorldAndPackedData[2].xyz = tangentToWorld[2];
		#else
			o.tangentToWorldAndPackedData[0].xyz = 0;
			o.tangentToWorldAndPackedData[1].xyz = 0;
			o.tangetnToWorldAndPackedData[2].xyz = normalWorld;
		#endif
		
		o.ambientOrLightmapUV = 0;
		
		#ifdef LIGHTMAP_ON
			o.ambientOrLightmapUV.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmpaST.zw;
		#endif
		
		#ifdef DYNAMICLIGHTMAP_ON
			o.ambientOrLightmapUV.zw = v.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
		#endif
		
		#if UNITY_SHOULD_SAMPLE_SH
			o.ambientOrLightmapUV.rgb = ShadeSHPerVertex(normalWorld, o.ambientOrLightmapUV.rgb);
		#endif
		
		
		
		#ifdef _PARALLAXMAP
			TANGENT_SPACE_ROTATION;
			half3 viewDirForParallax = mul(rotation, ObjSpaceViewDir(v.vertex));
			o.tangentToWorldAndPackedData[0].w = viewDirForParallax.x;
			o.tangentToWorldAndPackedData[1].w = viewDirForParallax.y;
			o.tangentToWorldAndPackedData[2].w = viewDirForParallax.z;
		#endif
		
		return o;
	}
	
#endif // UNITY_STANDARD_CORE_INCLUDED
