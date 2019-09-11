#ifndef UNITY_GLOBAL_ILLUMINATION_INCLUDED
	#define UNITY_GLOBAL_ILLUMINATION_INCLUDED
	
	#include "CGIncludes/UnityImageBasedLighting.cginc"
	
	inline void ResetUnityLight(out UnityLight outLight)
	{
		outLight.color = half3(0, 0, 0);
		outLight.dir = half3(0, 1, 0);//不相关的方向,但是不能为空
		outLight.ndotl = 0;//用不到了
	}
	
	inline void ResetUnityGI(out UnityGI outGI)
	{
		ResetUnityLight(outGI.light);
		outGI.indirect.diffuse = 0;
		outGI.indirect.specular = 0;
	}
	
	//选择lightmap亮度颜色和实时的亮度颜色中的最小颜色
	//bakedColorTex 用不到
	inline half3 SubtractMainLightWithRealtimeAttenuationFromLightmap(half3 lightmap, half attenuation, half4 bakedColorTex, half3 normalWorld)
	{
		//让我们尝试使实时阴影在已经包含主太阳光的烘焙照明和阴影。
		half3 shadowColor = unity_ShadowColor.rgb;
		half shadowStrength = _LightShadowData.x;
		
		/*
		总结：
		1).通过从 被实时阴影遮挡的 地方 减去 估计的光 贡献值 来计算阴影中的遮挡值：
		a)保留其他烘焙灯光和灯光反弹
		b)消除远离光线的几何体上的阴影
		2).根据用户定义的阴影颜色进行clamp。
		3).选择原始lightmap值(如果它是最暗的值)
		*/
		
		//1).很好地估计了照明，就好像在烘焙过程中光线会被遮挡一样。
		//保留反弹和其他烘焙灯光
		//几何体上没有远离灯光的阴影
		
		//LambertTerm() -> clamp01(dot(normal,lightDir))
		half ndotl = LambertTerm(normalWorld, _WorldSpaceLightPos0.xyz);
		//光贡献的颜色
		half3 estimatedLightContributionMaskedByInverseOfShadow = ndotl * (1 - attenuation) * _LightColor0.rgb;
		//阴影贡献的颜色 = 光照颜色-光贡献的颜色
		half3 subtractedLightmap = lightmap - estimatedLightContributionMaskedByInverseOfShadow;
		
		//2).允许用户定义场景的整体环境，并在实时阴影变得太暗时控制情况。
		//实际阴影颜色的 r=max(阴影贡献的颜色.r,预设的阴影颜色.r)  g b 相似
		half3 realtimeShadow = max(subtractedLightmap, shadowColor);
		//实际的颜色 根据阴影强度决定
		realtimeShadow = lerp(realtimeShadow, lightmap, shadowStrength);
		
		//3).在lightmap颜色和实时的颜色中 选择最暗的颜色
		return min(lightmap, realtimeShadow);
	}
	
	inline UnityGI UnityGI_Base(UnityGIInput data, half occlusion, half3 normalWorld)
	{
		//实时球谐  静态的unity_Lightmap   实时的unity_DynamicLightmap 三选一使用
		
		UnityGI o_gi;
		ResetUnityGI(o_gi);
		
		//基于性能原因，支持光照贴图的基本过程负责处理阴影遮罩/混合
		#if defined(HANDLE_SHADOWS_BLEDING_IN_GI)
			half bakedAtten = UnitySampleBakedOcclusion(data.lightmapUV.xy, data.worldPos);
			float zDist = dot(_WorldSpaceCameraPos - data.worldPos, UNITY_MATRIX_V[2].xyz);
			float fadeDist = UnityComputeShadowFadeDistance(data.worldPos, zDist);
			//根据物体动静态 决定用realtimeAtten 还是 bakedAtten
			data.atten = UnityMixRealTimeAndBakedShadows(data.atten, bakedAtten, UntiyComputeShadowFade(fadeDist));
		#endif
		
		o_gi.light = data.light;
		o_gi.light.color *= data.atten;
		
		// UNITY_SHOULD_SAMPLE_SH -> 当前渲染是动态模型  直接用球谐去计算
		// #define UNITY_SHOULD_SAMPLE_SH ( defined (LIGHTMAP_OFF) && defined(DYNAMICLIGHTMAP_OFF) )
		#if UNITY_SHOULD_SAMPLE_SH
			o_gi.indirect.diffuse = ShadeSHPerPixel(normalWorld, data.ambient, data.worldPos);
		#endif
		
		//如果是用lightmap 去计算
		#if defined(LIGHTMAP_ON)
			half4 bakedColorTex = UNITY_SAMPLE_TEX2D(unity_Lightmap, data.lightmapUV.xy);
			half3 bakedColor = DecodeLightmap(bakedColorTex);
			
			//主光的烘焙贴图是合并的 则要解压
			#ifdef DIRLIGHTMAP_COMBINED
				//烘焙的主光方向(要解压) bakedDirTex  xyz 是方向  w 是系数
				fixed4 bakedDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_LightmapInd, unity_Lightmap, data.lightmapUV.xy);
				o_gi.indirect.diffuse += DecodeDirectionalLightmap(bakedColor, bakedDirTex, normalWorld);
				
				//subtract mode 则要根据lightmap颜色和实时颜色进行重新计算取值
				#if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
					ResetUnityLight(o_gi.light);
					o_gi.indirect.diffuse = SubtractMainLightWithRealtimeAttenuationFromLightmap(o_gi.indirect.diffuse, data.atten, bakedColorTex, normalWorld);
				#endif
				
			#else //没有主光贴图
				o_gi.indirect.diffuse += bakedColor;
				
				//subtract mode 则要根据lightmap颜色和实时颜色进行重新计算取值
				#if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWSMASK) && defined(SHADOWS_SCREEN)
					ResetUnityLight(o_gi.light);
					o_gi.indirect.diffuse = SubtractMainLightWithRealtimeAttenuationFromLightmap(o_gi.indirect.diffuse, data.atten, bakedColorTex, normalWorld);
				#endif
			#endif
		#endif
		
		//如果是动态光照贴图
		#ifdef DYNAMICLIGHT_ON
			fixed4 realtimeColorTex = UNITY_SAMPLE_TEX2D(unity_DynamicLightmap, data.lightmapUV.zw);
			half3 realtimeColor = DecodeRealtimeLightmap(realtimeColorTex);//解码Enlighten 的RGBM 贴图
			
			#ifdef DIRLIGHTMAP_COMBINED
				half4 realtimeDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_DynamicDirectionality, unity_DynamicLightmap, data.lightmapUV.zw);
				o_gi.indirect.diffuse += DecodeDirectionalLightmap(realtimeColor, realtimeDirTex, normalWorld);
			#else
				o_gi.indirect.diffuse += realtimeColor;
			#endif
		#endif
		
		
		o_gi.indirect.diffuse *= occlusion;
		return o_gi;
	}
	
	//用于获取环境反射
	inline half3 UnityGI_IndirectSpecular(UnityGIInput data, half occlusion, Unity_GlossyEnvironmentData glossIn)
	{
		half3 specular;
		
		//cubeBox投影矫正
		#ifdef UNITY_SPACECUBE_BOX_PROJECTION
			half3 originalReflUVW = glossIn.reflUVW;
			glossIn.reflUVW = BoxProjectedCubemapDirection(originalReflUVW, data.worldPos, data.probePosition[0], data.boxMin[0], data.boxMax[0]);
		#endif
		
		//光照反射度 关闭 
		#ifdef _GLOSSYREFLECTIONS_OFF
			specular = unity_IndirectSpecColor.rgb;
		#else
			//环境反射球的颜色
			half3 env0 = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(unity_SpecCube0), data.probeHDR[0], glossIn);
			#ifdef UNITY_SPECCUBE_BLENDING
				const float kBlendFactor = 0.99999;
				float blendLerp = data.boxMin[0].w;//w是混合值
				
				//#define UNITY_BRANCH    [branch]
				//正常GPU IF ELSE 为了指令计数器和并行效率两个分支都执行
				//但是如果IF ELSE 里面的计算量过大 可以用宏 只执行一个
				UNITY_BRANCH
				//小于0.9999  则需要 反射球[1]
				if (blendLerp < kBlendFactor)
				{
					#ifdef UNITY_SPECCUBE_BOX_PROJECTION
						glossIn.reflUVW = BOXProjectedCubemapDirection(originalReflUVW, data.worldPos, data.probePosition[1], data.boxMin[1], data.boxMax[1]);
					#endif
					
					half3 env1 = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE_SAMPLER(unity_specCube1, unity_SpecCube0), data.probeHDR[1], glossIn);
					specular = lerp(env1, env0, blendLerp);
				}
				else
				{
					specular = env0;
				}
			#else
				specular = env0;
			#endif
		#endif
		
		return specular * occlusion;
	}
	
	//已经启用 但是由于依赖关系 无法移动到 Deprecated.cginc 文件中
	inline half3 UnityGI_IndirectSpecular(UnityGIInput data, half occlusion, half3 normalWorld, Unity_GlossyEnvironmentData glossIn)
	{
		// normalWorld 不再使用了
		return UnityGI_IndirectSpecular(data, occlusion, glossIn);
	}
	
	inline UnityGI UnityGlobalIllumination(UnityGIInput data, half occlusion, half3 normalWorld)
	{
		return UnityGI_Base(data, occlusion, normalWorld);
	}
	
	inline UnityGI UnityGlobalIllumination(UnityGIInput data, half occlusion, half3 normalWorld, Unity_GlossyEnvironmentData glossIn)
	{
		UnityGI o_gi = UnityGI_Base(data, occlusion, normalWorld);
		o_gi.indirect.specular = UnityGI_IndirectSpecular(data, occlusion, glossIn);
		return o_gi;
	}
	
#endif
