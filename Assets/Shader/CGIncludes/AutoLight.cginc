#ifndef AUTOLIGHT_INCLUDED
	#define AUTOLIGHT_INCLUDED
	
	#include "CGIncludes/HLSLSupport.cginc"
	#include "CGIncludes/UnityShadowLibrary.cginc"
	
	
	// ----------------
	// 阴影助手
	// ----------------
	
	// 如果没有定义任何关键字  则还是用平行光
	#if !defined(POINT) && !defined(SPOT) && !defined(DIRECTIONAL) && !defined(POINT_COOKIE) && !defined(DIRECTIONAL_COOKIE)
		#define DIRECTIONAL
	#endif
	
	// 屏幕空间 平行光 shadows helpers (any version)
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
	
	// -----------------------------
	// 阴影助手(5.6+ 版本)
	// -----------------------------
	//此版本取决于片段明暗器中的worldpos可用，并使用它来计算灯光坐标。
	//if还支持shadowmask（光照贴图对象的单独烘焙阴影）
	
	//计算阴影遮罩(烘焙的 实时的 近距离的)
	half UnityComputeForwardShadows(float2 lightmapUV, float3 worldPos, float4 screenPos)
	{
		//Z深度
		float zDist = dot(_WorldSpaceCameraPos - worldPos, UNITY_MATRIX_V[2].xyz);
		//根据阴影类型 到阴影中心的距离或者深度
		float fadeDist = UnityComputeShadowFadeDistance(worldPos, zDist);
		//获得Distance Clip 距离
		half  realtimeToBakedShadowFade = UnityComputeShadowFade(fadeDist);
		
		//得到烘焙的阴影遮罩
		half shadowMaskAttenuation = UnitySampleBakedOcclusion(lightmapUV, worldPos);
		
		//实时灯光遮罩
		half realtimeShadowAttenuation = 1.0f;
		//平行光实时阴影
		#if defined(SHADOWS_SCREEN)
			#if defined(UNITY_NO_SCREENSPACE_SHADOWS) && !defined(UNITY_HALF_PRECISION_FRAGMENT_SHADER_REGISTERS)
				realtimeShadowAttenuation = unitySampleShadow(mul(unity_WorldToShadow[0], unityShadowCoord4(worldPos, 1)));
			#else
				//仅当未定义lightmap_on时才到达（因此，我们对屏幕位置使用插值器，而不是lightmap uv）。请参见下面的处理阴影混合。
				realtimeShadowAttenuation = unitySampleShadow(screenPos);
			#endif
		#endif
		
		//软阴影 并且  没有混合LightMap Shadow   并且是快速的连贯的
		#if defined(UNITY_FAST_COHERENT_DYNAMIC_BRANCHING) && defined(SHADOWS_SOFT) && !defined(LIGHTMAP_SHADOW_MIXING)
			//避免在连贯很好的距离出现昂贵的阴影
			UNITY_BRANCH
			//realtimeToBakedShadowFade 距离过近  则要仔细重新计算
			if (realtimeToBakedShadowFade < (1.0f - 1e-2f))
			{
			#endif
			
			//聚光灯实时阴影
			#if (defined(SHADOWS_DEPTH) && defined(SPOT))
				#if !defined(UNITY_HALF_PRECISION_FRAGMENT_SHADER_REGISTERS)
						unityShadowCoord4 spotShadowCoord = mul(unity_WorldToShadow[0], unityShadowCoord4(worldPos, 1));
				#else
					unityShadowCoord4 spotShadowCoord = screenPos;
				#endif
				realtimeShadowAttenuation = UnitySampleShadowmap(spotShadowCoord);
			#endif
			
			//点光源实时阴影
			#if defined(SHADOWS_CUBE)
				realtimeShadowAttenuation = UnitySampleShadowmap(worldPos - _LightPositionRange.xyz);
			#endif
			
			#if defined(UNITY_FAST_COHERENT_DYNAMIC_BRANCHING) && defined(SHADOWS_SOFT) && !defined(LIGHTMAP_SHADOW_MIXING)
			}
		#endif
		
		return UnityMixRealtimeAndBakedShadows(realtimeShadowAttenuation, shadowMaskAttenuation, realtimeToBakedShadowFade);
	}
	
	#if defined(SHADER_API_D3D11) || defined(SHADER_API_D3D12) || defined(SHADER_API_XBOXONE) || defined(SHADER_API_PSSL)
		//DX
		#define UNITY_SHADOW_W(_w) _w
	#else
		//OPENGL
		#define UNITY_SHADOW_W(_w) (1.0 / _w)
	#endif
	
	#if !defined(UNITY_HALF_PRECISION_FRAGMENT_SHADER_REGISTERS)
		#define UNITY_READ_SHADOW_COORDS(input) 0
	#else
		//半精度
		#define UNITY_READ_SHADOW_COORDS(input) READ_SHADOW_COORDS(input)
	#endif
	
	#if defined(HANDLE_SHADOWS_BLENDING_IN_GI)
		// 出于性能原因，处理gi函数深处的阴影
		#define UNITY_SHADOW_COORDS(idx1) SHADOW_COORDS(idx1)
		#define UNITY_TRANSFER_SHADOW(a, coord) TRANSFER_SHADOW(a)
		#define UNITY_SHADOW_ATTENUATION(a, worldPos) SHADOW_ATTENUATION(a)
	#elif defined(SHADOWS_SCREEN) && !defined(LIGHTMAP_ON) && !defined(UNITY_NO_SCREENSPACE_SHADOWS)
		//不用Lightmap的实时屏幕要空间阴影
		//因为no lightmap uv因此存储screenpos
		//如果我们有两个平行光就可能发生。主光用gi代码处理，但第二个dir光可以有阴影屏和遮罩。
		//在ES2上禁用，因为WebGL 1.0在.w中似乎有垃圾（尽管它不应该）
		#if defined(SHADOWS_SHADOWMASK) && !defined(SHADER_API_GLES)
			//如果使用的是Shadowmask 或者 不是GLES
			#define UNITY_SHADOW_COORDS(idx1) unityShadowCoord4 _ShadowCoord: TEXCOORD##idx1;
			//_ShadowCoord.xy 是 LightmapUV  _ShadowCoord.zw 是 屏幕空间UV
			#define UNITY_TRANSFER_SHADOW(a, coord) a._ShadowCoord.xy = coord * unity_LightmapST.xy + unity_LightmapST.zw; a._ShadowCoord.zw = ComputeScreenPos(a.pos).xy;
			#define UNITY_SHADOW_ATTENUATION(a, worldPos) UnityComputeForwardShadows(a._ShadowCoord.xy, worldPos, float4(a._ShadowCoord.zw, 0.0, UNITY_SHADOW_W(a.pos.w)));
		#else
			//如果是GLES 要么 不是SHADOWMASK   处于性能考虑
			#define UNITY_SHADOW_COORDS(idx1) SHADOW_COORDS(idx1)
			#define UNITY_TRANSFER_SHADOW(a, coord) TRANSFER_SHADOW(a)
			#define UNITY_SHADOW_ATTENUATION(a, worldPos) UnityComputeForwardShadows(0, worldPos, a._ShadowCoord)
		#endif
	#else
		#define UNITY_SHADOW_COORDS(idx1) unityShadowCoord4 _ShadowCoord: TEXCOORD##idx1;
		#if defined(SHADOWS_SHADOWMASK)
			//使用ShadowMask
			#define UNITY_TRANSFER_SHADOW(a, coord) a._ShadowCoord.xy = coord.xy * unity_LightmapST.xy + unity_LightmapST.zw;
			#if (defined(SHADOWS_DEPTH) || defined(SHADOWS_SCREEN) || defined(SHADOWS_CUBE) || UNITY_LIGHT_PROBE_PROXY_VOLUME)
				//SHADOWS_DEPTH 深度阴影    SHADOWS_SCREEN 屏幕阴影    SHADOWS_CUBE 点光源阴影    UNITY_LIGHT_PROBE_PROXY_VOLUME 光照探针
				#define UNITY_SHADOW_ATTENUATION(a, worldPos) UnityComputeForwardShadows(a._ShadowCoord.xy, worldPos, UNITY_READ_SHADOW_COORDS(a))
			#else
				//比如平行光等
				#define UNITY_SHADOW_ATTENUATION(a, worldPos) UnityComputeForwardShadows(a._ShadowCoord.xy, 0, 0)
			#endif
		#else
			#if !defined(UNITY_HALF_PRECISION_FRAGMENT_SHADER_REGISTERS)
				//没有定义半精度
				#define UNITY_TRANSFER_SHADOW(a, coord)
			#else
				//定义了 半精度 half
				#define UNITY_TRANSFER_SHADOW(a, coord) TRANSFER_SHADOW(a)
			#endif
			
			#if (defined(SHADOWS_DEPTH) || defined(SHADOWS_SCREEN) || defined(SHADOWS_CUBE))
				//SHADOWS_DEPTH 深度阴影    SHADOWS_SCREEN 屏幕阴影    SHADOWS_CUBE 点光源阴影
				#define UNITY_SHADOW_ATTENUATION(a, worldPos) UnityComputeForwardShadows(0, worldPos, UNITY_READ_SHADOW_COORDS(a))
			#else
				//平行光
				#if UNITY_LIGHT_PROBE_PROXY_VOLUME
					//光照探针
					#define UNITY_SHADOW_ATTENUATION(a, worldPos) UnityComputeForwardShadows(0, worldPos, UNITY_READ_SHADOW_COORDS(a))
				#else
					//没有光照探针
					#define UNITY_SHADOW_ATTENUATION(a, worldPos) UnityComputeForwardShadows(0, 0, 0)
				#endif
			#endif
		#endif
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
	
	#ifdef DIRECTIONAL
		#define UNITY_LIGHT_ATTENUATION(destName, input, worldPos) fixed destName = UNITY_SHADOW_ATTENUATION(input, worldPos);
	#endif
	
#endif
