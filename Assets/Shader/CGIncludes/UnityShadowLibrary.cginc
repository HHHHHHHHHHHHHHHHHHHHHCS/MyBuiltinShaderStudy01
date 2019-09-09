#ifndef UNITY_BUILTIN_SHADOW_LIBRARY_INCLUDED
	#define UNITY_BUILTIN_SHADOW_LIBRARY_INCLUDED
	
	#if UNITY_LIGHT_PROBE_PROXY_VOLUME
		
		//探针的球谐光
		half4 LPPV_SampleProbeOcclusion(float3 worldPos)
		{
			//unity_ProbeVolumeParams.y    0 全局坐标    1 局部坐标
			const float transformToLocal = unity_ProbeVolumeParams.y;
			//unity_ProbeVolumeParams.z    UV的u 的texelSize 大小
			const float texelSizeX = unity_ProbeVolumeParams.z;
			
			//将sh系数纹理和探针遮挡填充到1个图集中。
			//RGBA->SHR/SHG/SHB/OCC
			float3 position = (transformToLocal == 1.0f) ? mul(unity_ProbeVolumeWorldToObject, float4(worldPos, 1.0)).xyz: worldPos;
			
			//获取0到1之间的tex坐标
			float3 texCoord = (position - unity_ProbeVolumeMin.xyz) * unity_ProbeVolumeSizeInv.xyz;
			
			//atlas中的第四个纹理样本
			//我们需要计算适当的u坐标来采样。
			//夹住坐标otherwize我们将在shb系数和探针遮挡（occ）信息之间泄漏
			texCoord.x = max(texCoord.x * 0.25f + 0.75f, 0.75f + 0.5f * texelSizeX);
			
			//UNITY_SAMPLE_TEX3D_SAMPLER() -> tex3D or tex.Sample
			//unity_ProbeVolumeSH() -> Texture3D or sampler3D_float ...
			return UNITY_SAMPLE_TEX3D_SAMPLER(unity_ProbeVolumeSH, unity_ProbeVolumeSH, texCoord);
		}
		
	#endif //#if UNITY_LIGHT_PROBE_PROXY_VOLUME
	
	#define unityShadowCoord float
	#define unityShadowCoord2 float2
	#define unityShadowCoord3 float3
	#define unityShadowCoord4 float4
	#define unityShadowCoord4x4 float4x4
	
	//得到烘焙的阴影遮罩  只在 forward 使用
	fixed UnitySampleBakedOcclusion(float2 lightmapUV, float3 worldPos)
	{
		#if defined(SHADOWS_SHADOWMASK)
			#if defined(LIGHTMAP_ON)
				//UNITY_SAMPLE_TEX2D() -> tex2D or tex.Sample
				//rawOcclusionMask 阴影遮罩
				fixed4 rawOcclusionMask = UNITY_SAMPLE_TEX2D(unity_ShadowMask, lightmapUV.xy);
			#else
				fixed4 rawOcclusionMask = fixed4(1.0, 1.0, 1.0, 1.0);
				//如果使用了光照探针
				#if UNITY_LIGHT_PROBE_PROXY_VOLUME
					if (unity_ProbeVolumeParams.x == 1.0)
						rawOcclusionMask = LPPV_SampleProbeOcclusion(worldPos);
					else
					rawOcclusionMask = UNITY_SAMPLE_TEX2D(unity_ShadowMask, lightmapUV.xy);
				#else
					rawOcclusionMask = UNITY_SAMPLE_TEX2D(unity_ShadowMask, lightmapUV.xy);
				#endif
			#endif
			//unity_OcclusionMaskSelector 部分的灯光,因为他可能在阴影距离之外使用
			return saturate(dot(rawOcclusionMask, unity_OcclusionMaskSelector));
			
		#else
			//在正向动态对象只能从lppv得到烘焙遮挡的情况下，光探头遮挡是在cpu上通过减弱光的颜色来实现的。
			fixed atten = 1.0f;
			#if defined(UNITY_INSTANCING_ENABLED) && defined(UNITY_USE_SHCOEFFS_ARRAYS)
				atten = unity_SHC.w;
				//…除非我们正在进行实例化，并且衰减被压缩到SHC阵列的.W分量中。
			#endif
			
			#if UNITY_LIGHT_PROBE_PROXY_VOLUME && !defined(LIGHTMAP_ON) && !UNITY_STANDARD_SIMPLE
				fixed4 rawOcclusionMask = atten.xxxx;
				if (unity_ProbeVolumeParams.x == 1.0)
					rawOcclusionMask = LPPV_SampleProbeOcclusion(worldPos);
				return saturate(dot(rawOcclusionMask, unity_OcclusionMaskSelector));
			#endif
			
			return atten;
		#endif
	}
	
	
	half    UnitySampleShadowmap_PCF7x7(float4 coord, float3 receiverPlaneDepthBias);   // 采样  shadowmap 基与 PCF 滤波 (7x7 kernel)
	half    UnitySampleShadowmap_PCF5x5(float4 coord, float3 receiverPlaneDepthBias);   // 采样  shadowmap 基与 PCF 滤波 (5x5 kernel)
	half    UnitySampleShadowmap_PCF3x3(float4 coord, float3 receiverPlaneDepthBias);   // 采样  shadowmap 基与 PCF 滤波 (3x3 kernel)
	float3  UnityGetReceiverPlaneDepthBias(float3 shadowCoord, float biasbiasMultiply); // 接收平面深度偏差
	
	
	// ------------------------------------------------------------------
	// Shadow fade
	// ------------------------------------------------------------------
	
	//根据阴影类型 计算到阴影中心的距离   或者是 Z深度
	//返回在[0,1]之间
	float UnityComputeShadowFadeDistance(float3 wpos, float z)
	{
		float sphereDist = distance(wpos, unity_ShadowFadeCenterAndType.xyz);
		return lerp(z, sphereDist, unity_ShadowFadeCenterAndType.w);
	}
	
	//得到根据 距离 得到  NearClip~FarClip区间 中的距离阴影
	half UnityComputeShadowFade(float fadeDist)
	{
		return saturate(fadeDist * _LightShadowData.z + _LightShadowData.w);
	}
	
	
	// ------------------------------------------------------------------
	//  Bias
	// ------------------------------------------------------------------
	
	/**
	* 计算屏幕空间中 给定阴影坐标 的接收器 平面深度偏差
	* 来自:
	* http://mynameismjp.wordpress.com/2013/09/10/shadow-maps/
	* http://amd-dev.wpengine.netdna-cdn.com/wordpress/media/2012/10/Isidoro-ShadowMapping.pdf
	*/
	float3 UnityGetReceiverPlaneDepthBias(float3 shadowCoord, float biasMultiply)
	{
		//是否应使用接收平面偏差？利用导数来估计接收器的斜率，
		//并尝试沿其倾斜PCF内核。但是，当从深度纹理在屏幕空间中执行此操作时
		//（即所有延迟光和方向光都是正向光和延迟光）导数是错误的
		//在对象的边或交点上，导致阴影瑕疵。所以默认情况下是禁用的。
		
		float3 biasUVZ = 0;
		
		#if defined(UNITY_USE_RECEIVER_PLANE_BIAS) && defined(SHADOWMAPSAMPLER_AND_TEXELSIZE_DEFINED)
			//ddx uv:(x,y) uv:(x+1,y) 像素的偏倒数
			float3 dx = ddx(shadowCoord);
			//ddx uv:(x,y) uv:(x,y+1) 像素的偏倒数
			float3 dy = ddy(shadowCoord);
			
			biasUVZ.x = dy.y * dx.z - dx.y * dy.z;
			biasUVZ.y = dx.x * dy.z - dy.x * dx.z;
			biasUVZ.xy *= biasMultiply / ((dx.x * dy.y) - (dx.y * dy.x));
			
			// 静态深度偏移，以弥补阴影贴图网格上不正确的分数采样。
			const float UNITY_RECEIVER_PLANE_MIN_FRACTIONAL_ERROR = 0.01f;
			float fractionalSamplingError = dot(_ShadowMapTexture_TexelSize.xy, abs(biasUVZ.xy));
			biasUVZ.z = -min(fractionalSamplingError, UNITY_RECEIVER_PLANE_MIN_FRACTIONAL_ERROR);
			#if defined(UNITY_REVERSED_Z)
				biasUVZ.z *= -1;
			#endif
		#endif
		
		return biasUVZ;
	}
	
	/**
	*合并阴影坐标的不同组件并返回最终坐标。
	*/
	float3 UnityCombineShadowcoordComponents(float2 baseUV, float2 deltaUV, float depth, float3 receiverPlaneDepthBias)
	{
		float3 uv = float3(baseUV + deltaUV, depth + receiverPlaneDepthBias.z);
		uv.z += dot(deltaUV, receiverPlaneDepthBias.xy);
		return uv;
	}
	
	/**
	*假设等高线矩形三角形的高度为“三角形高度”（如下图所示）。
	*此函数返回第一个texel上的三角形区域。
	* |\      <-- 45度斜等腰矩形三角形
	* | \     <--
	* ----    <-- 这一边的长度是“三角线”
	* _ _ _ _ <-- texels
	*/
	float _UnityInternalGetAreaAboveFirstTexelUnderAIsocelesRectangleTriangle(float triangleHeight)
	{
		return triangleHeight - 0.5;
	}
	
	/**
	* 假设等高线三角形的高度为1.5 texel，宽度为3 texel，位于4 texel上。
	* 此函数返回三角形在每个纹理上的面积。
	*   |    <-- 从-0.5到0.5的偏移量，0表示三角形正好位于中心
	*  / \   <-- 45度斜坡等腰三角形（即tent在二维投影）
	* /   \  <-- 面积 2.25
	*_ _ _ _ <-- texels
	* X Y Z W <-- 结果指标(在computedArea.xyzw和computedAreaUncut.xyzw中)
	* computedArea 切割部分
	* computedAreaUncut 未切割部分
	*/
	void _UnityInternalGetAreaPerTexel_3TexelsWideTriangleFilter(float offset, out float4 computedArea, out float4 computedAreaUncut)
	{
		//计算外部面积
		float offset01SquaredHalved = (offset +0.5) * (offset +0.5) * 0.5;
		computedAreaUncut.x = computedArea.x = offset01SquaredHalved - offset;
		computedAreaUncut.w = computedArea.w = offset01SquaredHalved;
		
		//计算中间区域
		//对于y：我们在y中找到面积，就好像相似三角形的左部分
		//使Y轴和Z轴相交（即偏移=0）。
		computedAreaUncut.y = _UnityInternalGetAreaAboveFirstTexelUnderAIsocelesRectangleTriangle(1.5 - offset);
		
		//if（offset<0）这个区域优于我们要查找的区域，因此我们需要
		//减去由（0,1.5-偏移量），（0,1.5+偏移量），（-偏移量，1.5）定义的三角形面积。
		float clampedOffsetLeft = min(offset, 0);
		float areaOfSmallLeftTriangle = clampedOffsetLeft * clampedOffsetLeft;
		computedArea.y = computedAreaUncut.y - areaOfSmallLeftTriangle;
		
		//我们对z做同样的操作，但是对相似三角形的右部分
		computedAreaUncut.z = _UnityInternalGetAreaAboveFirstTexelUnderAIsocelesRectangleTriangle(1.5 + offset);
		float clampedOffsetRight = max(offset, 0);
		float areaOfSmallRightTriangle = clampedOffsetRight * clampedOffsetRight;
		computedArea.z = computedAreaUncut.z - areaOfSmallRightTriangle;
	}
	
	/**
	*假设等高线三角形的高度为1.5 texel，宽度为3 texel，位于4 texel上。
	*此函数返回每个texels区域相对于整个三角形区域的权重。
	*/
	void _UnityInternalGetWeightPerTexel_3TexelsWideTriangleFilter(float offset, out float4 computedWeight)
	{
		float4 dummy;
		_UnityInternalGetAreaPerTexel_3TexelsWideTriangleFilter(offset, /*out*/computedWeight, /*out*/dummy);
		computedWeight *= 0.44444;//0.44 == 1/(三角面片面积)
	}
	
	
	// ------------------------------------------------------------------
	//  PCF 过滤
	// ------------------------------------------------------------------
	
	/**
	* 基于3x3内核的pcf高斯阴影图滤波(9 taps 但是 不支持pcf硬件)
	*/
	half UnitySampleShadowmap_PCF3x3NoHardwareSupport(float4 coord, float3 receiverPlaneDepthBias)
	{
		half shadow = 1;
		
		#ifdef SHADOWMAPSAMPLER_AND_TEXELSIZE_DEFINED
			//如果我们没有硬件PCF采样，那么上面的5x5优化PCF确实不起作用。
			//返回到一个简单的3x3采样，平均结果。
			float2 base_uv = coord.xy;
			float2 ts = _ShadowMapTexture_TexelSize.xy;
			shadow = 0;
			shadow += UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(base_uv, float2(-ts.x, -ts.y), coord.z, receiverPlaneDepthBias));
			shadow += UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(base_uv, float2(0, -ts.y), coord.z, receiverPlaneDepthBias));
			shadow += UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(base_uv, float2(ts.x, -ts.y), coord.z, receiverPlaneDepthBias));
			shadow += UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(base_uv, float2(-ts.x, 0), coord.z, receiverPlaneDepthBias));
			shadow += UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(base_uv, float2(0, 0), coord.z, receiverPlaneDepthBias));
			shadow += UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(base_uv, float2(ts.x, 0), coord.z, receiverPlaneDepthBias));
			shadow += UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(base_uv, float2(-ts.x, ts.y), coord.z, receiverPlaneDepthBias));
			shadow += UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(base_uv, float2(0, ts.y), coord.z, receiverPlaneDepthBias));
			shadow += UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(base_uv, float2(ts.x, ts.y), coord.z, receiverPlaneDepthBias));
			shadow /= 9.0;
		#endif
		
		return shadow;
	}
	
	/**
	* 基于3x3内核的PCF tent 阴影贴图过滤(使用4-tap优化)
	*/
	half UnitySampleShadowmap_PCF3x3Tent(float4 coord, float3 receiverPlaneDepthBias)
	{
		half shadow = 1;
		
		#ifdef SHADOWMAPSAMPLER_AND_TEXELSIZE_DEFINED
			
			//#ifndef SHADOWS_NATIVE  除了GLES的平台
			#ifndef SHADOWS_NATIVE
				//当我们 没有PCF硬件 支持采样的 时候,回退到简单的3x3取平均结果
				return UnitySampleShadowmap_PCF3x3NoHardwareSupport(coord, receiverPlaneDepthBias);
			#endif
			
			// tent base 是 3x3 base 因此覆盖 9 到 12 texels 因此我们需要4个双线 进行fetch
			float2 tentCenterInTexelSpace = coord.xy * _ShadowMapTexture_TexelSize.zw;
			float2 centerOfFetchesInTexelSpace = floor(tentCenterInTexelSpace + 0.5);
			float2 offsetFromTentCenterToCenterOfFetches = tentCenterInTexelSpace - centerOfFetchesInTexelSpace;
			
			//找到每个texel的权重
			float4 texelsWeightsU, texelsWeightsV;
			_UnityInternalGetWeightPerTexel_3TexelsWideTriangleFilter(offsetFromTentCenterToCenterOfFetches.x, /*out*/texelsWeightsU);
			_UnityInternalGetWeightPerTexel_3TexelsWideTriangleFilter(offsetFromTentCenterToCenterOfFetches.y, /*out*/texelsWeightsV);
			
			//每次fetch将覆盖一组2x2 texel，每组的权重是texel的权重之和
			float2 fetchesWeightsU = texelsWeightsU.xz + texelsWeightsU.yw;
			float2 fetchesWeightsV = texelsWeightsV.xz + texelsWeightsV.yw;
			
			//移动pcf双线性获取以 各自的texels权重
			float2 fetchesOffsetsU = texelsWeightsU.yw / fetchesWeightsU.xy + float2(-1.5, 0.5);
			float2 fetchesOffsetsV = texelsWeightsV.yw / fetchesWeightsV.xy + float2(-1.5, 0.5);
			fetchesOffsetsU *= _ShadowMapTexture_TexelSize.xx;
			fetchesOffsetsV *= _ShadowMapTexture_TexelSize.yy;
			
			// fetch !
			float2 bilinearFetchOrigin = centerOfFetchesInTexelSpace * _ShadowMapTexture_TexelSize.xy;
			shadow = fetchesWeightsU.x * fetchesWeightsV.x
			* UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(bilinearFetchOrigin, float2(fetchesOffsetsU.x, fetchesOffsetsV.x), coord.z, receiverPlaneDepthBias));
			shadow += fetchesWeightsU.y * fetchesWeightsV.x
			* UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(bilinearFetchOrigin, float2(fetchesOffsetsU.y, fetchesOffsetsV.x), coord.z, receiverPlaneDepthBias));
			shadow += fetchesWeightsU.x * fetchesWeightsV.y
			* UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(bilinearFetchOrigin, float2(fetchesOffsetsU.x, fetchesOffsetsV.y), coord.z, receiverPlaneDepthBias));
			shadow += fetchesWeightsU.y * fetchesWeightsV.y
			* UNITY_SAMPLE_SHADOW(_ShadowMapTexture, UnityCombineShadowcoordComponents(bilinearFetchOrigin, float2(fetchesOffsetsU.y, fetchesOffsetsV.y), coord.z, receiverPlaneDepthBias));
		#endif
		
		return shadow;
	}
	
	half UnitySampleShadowmap_PCF3x3(float4 coord, float3 receiverPlaneDepthBias)
	{
		return UnitySampleShadowmap_PCF3x3Tent(coord, receiverPlaneDepthBias);
	}
	
	// ------------------------------------------------------------------
	// 正向渲染和延迟渲染都用  使用利用实时的阴影和烘焙的阴影计算出 最后要的阴影
	half UnityMixRealtimeAndBakedShadows(half realtimeShadowAttenuation, half bakedShadowAttenuation, half fade)
	{
		// -- Static objects --
		// FWD BASE PASS
		// ShadowMask mode          = LIGHTMAP_ON + SHADOWS_SHADOWMASK + LIGHTMAP_SHADOW_MIXING
		// Distance shadowmask mode = LIGHTMAP_ON + SHADOWS_SHADOWMASK
		// Subtractive mode         = LIGHTMAP_ON + LIGHTMAP_SHADOW_MIXING
		// Pure realtime direct lit = LIGHTMAP_ON
		
		// FWD ADD PASS
		// ShadowMask mode          = SHADOWS_SHADOWMASK + LIGHTMAP_SHADOW_MIXING
		// Distance shadowmask mode = SHADOWS_SHADOWMASK
		// Pure realtime direct lit = LIGHTMAP_ON
		
		// DEFERRED LIGHTING PASS
		// ShadowMask mode          = LIGHTMAP_ON + SHADOWS_SHADOWMASK + LIGHTMAP_SHADOW_MIXING
		// Distance shadowmask mode = LIGHTMAP_ON + SHADOWS_SHADOWMASK
		// Pure realtime direct lit = LIGHTMAP_ON
		
		// -- Dynamic objects --
		// FWD BASE PASS + FWD ADD PASS
		// ShadowMask mode          = LIGHTMAP_SHADOW_MIXING
		// Distance shadowmask mode = N/A
		// Subtractive mode         = LIGHTMAP_SHADOW_MIXING (only matter for LPPV. Light probes occlusion being done on CPU)
		// Pure realtime direct lit = N/A
		
		// DEFERRED LIGHTING PASS
		// ShadowMask mode          = SHADOWS_SHADOWMASK + LIGHTMAP_SHADOW_MIXING
		// Distance shadowmask mode = SHADOWS_SHADOWMASK
		// Pure realtime direct lit = N/A
		
		//Static objects
		#if !defined(SHADOWS_DEPTH) && !defined(SHADOWS_SCREEN) && !defined(SHADOWS_CUBE)
			#if defined(LIGHTMAP_ON) && defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK)
					//在Subtractive mode下，如果没有阴影，我们会直接不用灯光贡献，使用光照贴图中的烘焙
				return 0.0;
			#else
				//否则用烘焙的的阴影
				return bakedShadowAttenuation;
			#endif
		#endif
		
		#if (SHADER_TARGET <= 20) || UNITY_STANDARD_SIMPLE
			//SM2.0由于指令计数限制,没有衰减或者混合
			#if defined(SHADOWS_SHADOWMASK) || defined(LIGHTMAP_SHADOW_MIXING)
				return min(realtimeShadowAttenuation, bakedShadowAttenuation);
			#else
				return realtimeShadowAttenuation;
			#endif
		#endif
		
		//Dynamic objects
		#if defined(LIGHTMAP_SHADOW_MIXING)
			//Subtractive or shadowmask mode
			realtimeShadowAttenuation = saturate(realtimeShadowAttenuation + fade);
			return min(realtimeShadowAttenuation, bakedShadowAttenuation);
		#endif
		
		//在“distance shadowmask”或“realtime shadow fadeout”中
		//我们会向烘焙阴影发出警报（如果没有烘焙阴影，则烘焙阴影衰减将为1）
		return lerp(realtimeShadowAttenuation, bakedShadowAttenuation, fade);
	}
	
	// ------------------------------------------------------------------
	// Spot light shadows
	// ------------------------------------------------------------------
	
	#if defined(SHADOWS_DEPTH) && defined(SPOT)
		
		// 声明 shadowmap
		#if !defined(SHADOWMAPSAMPLER_DEFINED)
			//_ShadowMapTexture .r 是深度
			UNITY_DECLARE_SHADOWMAP(_ShadowMapTexture);
			#define SHADOWMAPSAMPLER_DEFINED
		#endif
		
		// 阴影采样偏移和纹理像素大小
		#if defined(SHADOWS_SOFT)
			float4 _ShadowOffsets[4];
			float4 _ShadowMapTexture_TexelSize;
			#define SHADOWMAPSAMPLER_AND_TEXELSIZE_DEFINED
		#endif
		
		inline fixed UnitySampleShadowmap(float4 shadowCoord)
		{
			//如果使用了软阴影
			#if defined(SHADOWS_SOFT)
				
				half shadow = 1;
				
				//没有比较的采样器的硬件(即一些手机+ xbox360):简单的4-tap PCF
				//!defined(SHADOWS_NATIVE) 除了GLES的平台
				#if !defined(SHADOWS_NATIVE)
					float3 coord = shadowCoord.xyz / shadowCoord.w;
					float4 shadowVals;
					//SAMPLE_DEPTH_TEXTURE() -> tex2D(sampler,uv).r
					shadowVals.x = SAMPLE_DEPTH_TEXTURE(_ShadowMapTexture, coord + _ShadowOffsets[0].xy);
					shadowVals.y = SAMPLE_DEPTH_TEXTURE(_ShadowMapTexture, coord + _ShadowOffsets[1].xy);
					shadowVals.z = SAMPLE_DEPTH_TEXTURE(_ShadowMapTexture, coord + _ShadowOffsets[2].xy);
					shadowVals.w = SAMPLE_DEPTH_TEXTURE(_ShadowMapTexture, coord + _ShadowOffsets[3].xy);
					//当前灯光的阴影深度 和 物体的阴影深度 比较
					//如果 物体的比较小 则 是阴影
					//否则不是阴影
					half4 shadows = (shadowVals < coord.zzzz) ? _LightShadowData.rrrr: 1.0f;
					shadow = dot(shadows, 0.25f);//阴影累加/4
				#else
					// 带比较采样器的移动设备：4-tap 带比较的 线性 滤波 设备
					#if defined(SHADER_API_MOBILE)
						float3 coord = shadowCoord.xyz / shadowCoord.w;
						half4 shadows;
						//UNITY_SAMPLE_SHADOW() -> SAMPLE_DEPTH_TEXTURE (xy < zz) 然后把值进行比较 得出0或者1
						shadows.x = UNITY_SAMPLE_SHADOW(_ShadowMapTexture, coord + _ShadowOffsets[0]);
						shadows.y = UNITY_SAMPLE_SHADOW(_ShadowMapTexture, coord + _ShadowOffsets[1]);
						shadows.z = UNITY_SAMPLE_SHADOW(_ShadowMapTexture, coord + _ShadowOffsets[2]);
						shadows.w = UNITY_SAMPLE_SHADOW(_ShadowMapTexture, coord + _ShadowOffsets[3]);
						shadow = dot(shadows, 0.25f);
					#else
						//任何别的设备
						float3 coord = shadowCoord.xyz / shadowCoord.w;
						//UnityGetReceiverPlaneDepthBias() -> 平面深度偏差
						float3 receiverPlaneDepthBias = UnityGetReceiverPlaneDepthBias(coord, 1.0f);
						//通过阴影贴图波滤得到阴影
						shadow = UnitySampleShadowmap_PCF3x3(float4(coord, 1), receiverPlaneDepthBias);
					#endif
					shadow = lerp(_LightShadowData.r, 1.0f, shadow);
				#endif
			#else
				// 1-tap shadows
				#if defined(SHADOWS_NATIVE)
					//UNITY_SAMPLE_SHADOW_PROJ() -> SAMPLE_DEPTH_TEXTURE_PROJ(xy) < z/w 进行比较返回 0 or 1
					half shadow = UNITY_SAMPLE_SHADOW_PROJ(_ShadowMapTexture, shadowCoord);
					shadow = lerp(_LightShadowData.r, 1.0f, shadow);
				#else
					//GLES 为了省性能 所以没有lerp
					//UNITY_PROJ_COORD(x) -> x
					half shadow = SAMPLE_DEPTH_TEXTURE_PROJ(_ShadowMapTexture, UNITY_PROJ_COORD(shadowCoord)) < (shadowCoord.z / shadowCoord.w) ? _LightShadowData.r: 1.0;
				#endif
				
			#endif
			
			return shadow;
		}
		
	#endif // #if defined (SHADOWS_DEPTH) && defined (SPOT)
	
	
	// ------------------------------------------------------------------
	// Point light shadows
	// ------------------------------------------------------------------
	
	#if defined(SHADOWS_CUBE)
		
		#if defined(SHADOWS_CUBE_IN_DEPTH_TEX)
			//UNITY_DECLARE_TEXCUBE_SHADOWMAP -> samplerCUBE_float
			UNITY_DECLARE_TEXCUBE_SHADOWMAP(_ShadowMapTexture);
		#else
			UNITY_DECLARE_TEXCUBE(_ShadowMapTexture);
		#endif
		
	#endif // #if defined (SHADOWS_CUBE)
	
#endif // UNITY_BUILTIN_SHADOW_LIBRARY_INCLUDED
