#ifndef UNITY_CG_INCLUDED
	#define UNITY_CG_INCLUDED
	
	#include "CGIncludes/UnityInstancing.cginc"
	#include "CGincludes/UnityShaderVariables.cginc"
	
	
	#ifdef UNITY_COLORSPACE_GAMMA
		#define unity_ColorSpaceDouble fixed4(2.0, 2.0, 2.0, 2.0)
		#define unity_ColorSpaceDielectricSpec half4(0.220916301, 0.220916301, 0.220916301, 1.0 - 0.220916301)
	#else // Linear values
		#define unity_ColorSpaceDouble fixed4(4.59479380, 4.59479380, 4.59479380, 2.0)
		#define unity_ColorSpaceDielectricSpec half4(0.04, 0.04, 0.04, 1.0 - 0.04) // standard dielectric reflectivity coef at incident angle (= 4%)
	#endif
	
	
	//linear颜色转gamma
	inline half3 LinearToGammaSpace(half3 linRGB)
	{
		linRGB = max(linRGB, half3(0.h, 0.h, 0.h));
		return max(1.055h * pow(linRGB, 0.416666667h) - 0.055h, 0.h);
	}
	
	//解压HDR贴图
	//处理dLDR和RGBM格式
	inline half3 DecodeLightmapRGBM(half4 data, decodeInstructions)
	{
		//如果不支持线性模式，我们可以跳过指数部分
		#if defined(UNITY_COLORSPACE_GAMMA)
			//RGBM 线性读取
			#if defined(UNITY_FORCE_LINEAR_READ_FOR_RGBM)
				return(decodeInstructions.x * data.a) * sqrt(data.rgb);
			#else
				return(decodeInstructions.x * data.a) * data.rgb;
			#endif
		#else
			return(decodeInstructions.x * pow(data.a, decodeInstructions.y)) * data.rgb;
		#endif
	}
	
	//解码DoubleLDR
	//DLDR即doubleLDR，双倍低动态 （色值乘二...）
	inline half3 DecodeLightmapDoubleLDR(fixed4 color, half4 decodeInstructions)
	{
		//decodeInstructions.x在使用gamma颜色空间时包含2.0，或者在移动平台上使用线性颜色空间时包含pow(2.0,2.2)=4.59
		return decodeInstructions.x * color.rgb;
	}
	
	//lightmap 的 color.a 会被用于压缩   所以贴图格式的A 不能被使用
	inline half3 DecodeLightmap(fixed4 color, half4 decodeInstructions)
	{
		//Lightmap解析:https://zhuanlan.zhihu.com/p/35096536
		
		#if defined(UNITY_LIGHTRMAP_DLDR_ENCODING)
			return DecodeLightmapDoubleLDR(color, decodeInstructions);
		#elif defined(UNITY_LIGHTMAP_RGBM_ENCODING)
			//RGBM即 HDR的RGBM压缩格式
			//RGBM编码pack [0,8]的范围为[0, 1]，乘数存储在alpha通道中。最终值为RGB * A * 8。
			return DecodeLightmapRGBM(color, decodeInstructions);
		#else //defined(UNITY_LIGHTMAP_FULL_HDR)
			//当启用标准HDR的时直接返回颜色rgb不需要做额外处理
			return color.rgb;
		#endif
	}
	
	//物体lightmap_hdr的颜色   通常用于解码lightmap
	half4 unity_Lightmap_HDR;
	
	inline half3 DecodeLightmap(fixed4 color)
	{
		return DecodeLightmap(color, unity_Lightmap_HDR);
	}
	
	
	half4 unity_DynamicLightmap_HDR;
	
	/*
	解码Enlighten RGBM编码的lightmap
	注意：Enlighten动态纹理RGBM格式与标准Unity HDR纹理不同
	（例如烘焙的光照贴图、反射探测器和IBL图像）
	相反,在具有不同指数的线性颜色空间中,Enlighten提供了rgbm纹理。
	警告：3次POW操作，对手机来说可能非常昂贵！
	*/
	inline half3 DecodeRealtimeLightmap(fixed4 color)
	{
		//跟这个 DecodeLightmapRGBM()  方法差不多
		//这是暂时的，直到Geomerics给我们一个api，在上传纹理之前，在Enlighten线程上的gamma空间将光照贴图转换为rgbm。
		#if defined(UNITY_FORCE_LINEAR_READ_FOR_RGBM)
			return pow((unity_DynamicLightmap_HDR.x * color.a) * sqrt(color.rgb), unity_DynamicLightmap_HDR.y);
		#else
			return pow((unity_DynamicLightmap_HDR.x * color.a) * color.rgb, unity_DynamicLightmap_HDR.y);
		#endif
	}
	
	inline half3 DecodeDirectionalLightmap(half3 color, fixed4 dirTex, half3 normalWorld)
	{
		/*
		在定向（非镜面）模式中，照亮烘焙主光方向
		在某种程度上，用它来表示半兰伯特，然后除以“再平衡系数”
		给出的结果接近于纯漫反射响应光照贴图，但为法线贴图。
		注意，dir不是有意的单位长度。它的长度是“方向性”，就像用于定向高光照贴图。
		*/
		//dirTex.xyz  -> [0,1] - 0.5 -> [-0.5,0.5]   ==  0.5 * [-1,1] 就跟半兰伯特一样
		half halfLambert = dot(normalWorld, dirTex.xyz - 0.5) + 0.5;
		
		return col * halfLambert / max(1e-4h, dirTex.w);
	}
	
	
	//一级球谐    normal应该被归一化 并且W=1.0
	//线性+常量多项式
	half3 SHEvalLinearL0L1(half4 normal)
	{
		half3 x;
		
		//unity_SHAr/g/b 都在 UnityShaderVariables.cginc中
		x.r = dot(unity_SHAr, normal);
		x.g = dot(unity_SHAg, normal);
		x.b = dot(unity_SHAb, normal);
		
		return x;
	}
	
	//二级球谐    normal应该被归一化 并且W=1.0
	//平方多项式
	half3 SHEvalLinearL2(half4 normal)
	{
		half3 x1, x2;
		//4个二次(l2)的多项式
		half4 vB = normal.xyzz * normal.yzzx;
		x1.r = dot(unity_SHBr, vB);
		x1.g = dot(unity_SHBg, vB);
		x1.b = dot(unity_SHBb, vB);
		
		//最后第五个多项式
		half vC = normal.x * normal.x - normal.y * normal.y;
		x2 = unity_SHC.rgb * vC;
		
		return x1 + x2;
	}
	
	//计算球谐光
	half3 ShadeSH9(half4 normal)
	{
		half3 res = SHEvalLinearL0L1(normal);
		
		res += SHEvalLinearL2(normal);
		
		#ifdef UNITY_COLORSPACE_GAMMA
			res = LinearToGammaSpace(res);
		#endif
		
		return res;
	}
	
	#if UNITY_LIGHT_PROBE_PROXY_VOLUME
		
		//normal应该被标准化 w=1.0
		half3 SHEvalLinearL0L1_SampleProbeVolume(half4 normal, float3 worldPos)
		{
			const float transformToLocal = unity_ProbeVolumeParams.y;
			const float texelSizeX = unity_ProbeVolumeParams.z;
			
			//sh系数纹理和探针遮挡被打包到1个图集中。
			//—————————————————————
			//| SHR|SHG|SHB|遮挡系数|
			//—————————————————————
			
			float3 position = (transformToLocal == 1.0f)?mul(unity_ProbeVolumeWorldToObject, float4(worldPos, 1.0)).xyz: worldPos;
			float3 texCoord = (position - unity_ProbeVolumeMin.xyz) * unity_ProbeVolumeSizeInv.xyz;
			texCoord.x = texCoord.x * 0.25f;//因为是4X4
			
			//我们需要计算适当的x坐标来采样。
			//夹住坐标，否则rgb系数之间会有泄漏
			float texCoordX = clamp(texCoord.x, 0.5f * texelSizeX, 0.25f - 0.5f * texelSizeX);
			
			//采样器状态来自SHR(所有SH纹理共享同一采样器)
			//UNITY_SAMPLE_TEX3D_SAMPLER -> tex3D
			texCoord.x = texCoordX;
			half4 SHAr = UNITY_SAMPLE_TEX3D_SAMPLER(unity_ProbeVolumeSH, unity_ProbeVolumeSH, texCoord);
			
			texCoord.x = texCoordX + 0.25f;
			half4 SHAg = UNITY_SAMPLE_TEX3D_SAMPLER(unity_ProbeVolumeSH, unity_ProbeVolumeSH, texCoord);
			
			texCoord.x = texCoordX + 0.5f;
			half4 SHAb = UNITY_SAMPLE_TEX3D_SAMPLER(unity_ProbeVolumeSH, unity_ProbeVolumeSH, texCoord);
			
			//线性+常数多项式项
			half3 x1;
			x1.r = dot(SHAr, normal);
			x1.g = dot(SHAg, normal);
			x1.b = dot(SHAb, normal);
			
			return x1;
		}
		
	#endif
	
	// 用于ForwardBase过程:计算四个点光源的漫反射照明,数据以特殊方式打包
	float3 Shade4PointLights(
		float4 lightPosX, float4 lightPosY, float4 lightPosZ,
		float3 lightColor0, float3 lightColor1, float3 lightColor2, float3 lightColor3,
		float4 lightAttenSq,
		float3 pos, float3 normal)
	{
		//Light方向
		float4 toLightX = lightPosX - pos.x;
		float4 toLightY = lightPosY - pos.y;
		float4 toLightZ = lightPosZ - pos.z;
		// squared lengths
		float4 lengthSq = 0;
		lengthSq += toLightX * toLightX;
		lengthSq += toLightY * toLightY;
		lengthSq += toLightZ * toLightZ;
		//防止除以0的报错
		lengthSq = max(lengthSq, 0.000001);
		
		//NdotL
		float4 ndotl = 0;
		ndotl += toLightX * normal.x;
		ndotl += toLightY * normal.y;
		ndotl += toLightZ * normal.z;
		//rsqrt=1/sqrt(x)
		float4 corr = rsqrt(lengthSq);
		ndotl = max(float4(0, 0, 0, 0), ndotl * corr);
		// attenuation
		float4 atten = 1.0 / (1.0 + lengthSq * lightAttenSq);
		float4 diff = ndotl * atten;
		// 输出颜色
		float3 col = 0;
		col += lightColor0 * diff.x;
		col += lightColor1 * diff.y;
		col += lightColor2 * diff.z;
		col += lightColor3 * diff.w;
		return col;
	}
	
	#define TRANSFORM_TEX(tex, name) (tex.xy * name##_ST.xy + name##_ST.zw)
	
	
	inline float3 UnityObjectToWorldDir(in float3 dir)
	{
		return normalize(mul((float3x3)unity_ObjectToWorld, dir));
	}
	
	//如果使用了统一实例化缩放 则走UnityObjectToWorldDir
	inline float3 UnityObjectToWorldNormal(in float3 norm)
	{
		#ifdef UNITY_ASSUME_UNIFORM_SCALING
			return UnityObjectToWorldDir(norm);
		#else
			//如果不是等比例缩放 则用矩阵进行补偿 法线矩阵被定义为「模型矩阵左上角的逆矩阵的转置矩阵」。
			return normalize(mul(norm, (float3x3)unity_WorldToObject));
		#endif
	}
	
	inline float4 ComputeNonStereoScreenPos(float4 pos)
	{
		float4 o = pos * 0.5f;
		//x和y w 都是除以齐次缩放的 并且w已经乘以0.5过了
		//_ProjectionParams.x 根据OPENGL和DX所以乘
		//故 (-1~1)/2+0.5
		o.xy = float2(o.x, o.y * _ProjectionParams.x) + o.w;
		//ZW 不需要变动
		o.zw = pos.zw;
		return o;
	}
	
	inline float4 ComputeScreenPos(float4 pos)
	{
		float4 o = ComputeNonStereoScreenPos(pos);
		#if defined(UNITY_SINGLE_PASS_STEREO)//单通道立体渲染，目前主要用于VR 暂时用不到
			o.xy = TransformStereoScreenSpaceTex(o.xy, pos.w);
		#endif
		return o;
	}
	
	#define UNITY_FOG_COORDS_PACKED(idx, vectype) vectype fogCoord: TEXCOORD##idx;
	
	
	#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
		#define UNITY_FOG_COORDS(idx) UNITY_FOG_COORDS_PACKED(idx, float1)
			
		#if (SHADER_TARGET < 30) || defined(SHADER_API_MOBILE)
			// 手机 或 SM2.0: 计算每个顶点的雾因子
			#define UNITY_TRANSFER_FOG(o, outpos) UNITY_CALC_FOG_FACTOR((outpos).z); o.fogCoord.x = unityFogFactor
		#else
			// 电脑/主机 并且 SM3.0 :计算每个顶点的雾距离和每个像素的雾因子  其实就是屏幕空间的深度
			#define UNITY_TRANSFER_FOG(o, outpos) o.fogCoord.x = (outpos).z
		#endif
	#else
		#define UNITY_TRANSFER_FOG(o, outpos)
	#endif
	
	#ifdef LOD_FADE_CROSSFADE
		sampler2D unity_DitherMask;//LOD Fade 遮罩贴图
		
		void UnityApplyDitherCrossFade(float2 vpos)
		{
			vpos /= 4; //the dither mask texture is 4x4
			float mask = tex2D(unity_DitherMask, vpos).a;
			float sgn = unity_LODFade.x > 0?1.0f: - 1.0f;
			clip(unity_LODFade.x - mask * sgn);
		}
		
		#define UNITY_APPLY_DITHER_CROSSFADE(vpos) UnityApplyDitherCrossFade(vpos)
	#else
		#define UNITY_APPLY_DITHER_CROSSFADE(vpos)
	#endif
	
#endif // UNITY_CG_INCLUDED
