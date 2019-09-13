#ifndef UNITY_CG_INCLUDED
	#define UNITY_CG_INCLUDED
	
	#include "CGIncludes/UnityInstancing.cginc"
	#include "CGincludes/UnityShaderVariables.cginc"
	
	#define UNITY_OPAQUE_ALPHA(outputAlpha) outputAlpha = 1.0
	
	#ifdef UNITY_COLORSPACE_GAMMA
		#define unity_ColorSpaceDouble fixed4(2.0, 2.0, 2.0, 2.0)
		#define unity_ColorSpaceDielectricSpec half4(0.220916301, 0.220916301, 0.220916301, 1.0 - 0.220916301)
	#else // Linear values
		#define unity_ColorSpaceDouble fixed4(4.59479380, 4.59479380, 4.59479380, 2.0)
		#define unity_ColorSpaceDielectricSpec half4(0.04, 0.04, 0.04, 1.0 - 0.04) // standard dielectric reflectivity coef at incident angle (= 4%)
	#endif
	
	//是否应进行SH（光探头/环境）计算？
	//-当静态和动态光照贴图都可用时，不执行sh求值
	//-当静态和动态光照贴图不可用时，始终执行sh求值
	//-对于低层lod，静态光照图和来自光探头的实时gi可以结合在一起
	//-不执行环境光的过程（附加、阴影投射等）也不应执行sh。
	#define UNITY_SHOULD_SAMPLE_SH (defined(LIGHTPROBE_SH) && !defined(UNITY_PASS_FORWARDADD) && !defined(UNITY_PASS_PREPASSBASE) && !defined(UNITY_PASS_SHADOWCASTER) && !defined(UNITY_PASS_META))
	
	
	//linear颜色转gamma
	inline half3 LinearToGammaSpace(half3 linRGB)
	{
		linRGB = max(linRGB, half3(0.h, 0.h, 0.h));
		return max(1.055h * pow(linRGB, 0.416666667h) - 0.055h, 0.h);
	}
	
	//gamma颜色转linear
	inline half3 GammaToLinearSpace(half3 sRGB)
	{
		// 近似做法 from http://chilliant.blogspot.com.au/2012/08/srgb-approximations-for-hlsl.html?m=1
		return sRGB * (sRGB * (sRGB * 0.305306011h + 0.682171111h) + 0.012522878h);
	}
	
	
	#define CREATE_BINORMAL float3 binormal = cross(normalize(v.normal), normalize(v.tangent.xyz)) * v.tangent.w
	#define CREATE_ROTATION float3x3 rotation = float3x3(v.tangent.xyz, binormal, v.normal)
	#define TANGENT_SPACE_ROTATION CREATE_BINORMAL; CREATE_ROTATION
	
	
	
	//解压HDR贴图
	//处理dLDR和RGBM格式
	inline half3 DecodeLightmapRGBM(half4 data, half4 decodeInstructions)
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
	
	//解压HDR
	inline half3 DecodeHDR(half4 data, half4 decodeInstructions)
	{
		half alpha = decodeInstructions.w * (data.a - 1.0) + 1.0;
		
		//gamma Color 则需要 alpha 解压
		#if defined(UNITY_COLORSPACE_GAMMA)
			return(decodeInstructions.x * alpha) * data.rgb;
		#else //linear Color
			//如果是普通的HDR 则无需怎么解压
			#if defined(UNITY_USE_NATIVE_HDR)
				return decodeInstructions.x * data.rgb;
			#else
				//否则就要pow
				return(decodeInstructions.x * pow(alpha, decodeInstructions.y)) * data.rgb;
			#endif
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
		
		return color * halfLambert / max(1e-4h, dirTex.w);
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
	
	//物体空间视野方向
	inline float3 ObjSpaceViewDir(in float4 v)
	{
		float3 objSpaceCameraPos = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos.xyz, 1)).xyz;
		return objSpaceCameraPos - v.xyz;
	}
	
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
		//_ProjectionParams.x 根据OPENGL和DX 所以投影翻转
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
	
	// ------------------------------------------------------------------
	// Fog helpers
	// UNITY_PASS_PREPASSBASE -> 延迟渲染base pass(renders normals & specular exponent)
	// UNITY_PASS_DEFERRED -> 延迟渲染G缓冲区
	// UNITY_PASS_SHADOWCASTER -> 阴影渲染
	// 如果不小心在延迟渲染要么阴影渲染中开启了,则关闭fog
	#if defined(UNITY_PASS_PREPASSBASE) || defined(UNITY_PASS_DEFERRED) || defined(UNITY_PASS_SHADOWCASTER)
		#undef FOG_LINEAR
		#undef FOG_EXP
		#undef FOG_EXP2
	#endif
	
	#define UNITY_FOG_COORDS_PACKED(idx, vectype) vectype fogCoord: TEXCOORD##idx;
	
	#if defined(UNITY_REVERSED_Z)
		//UNITY_Z_0_FAR_FROM_CLIPSPACE 是否需要翻转深度Z 之类的
		#if UNITY_REVERSED_Z == 1
			//D3d 翻转 Z => z Clip 范围 [near, 0] -> 重新映射 [0, far]
			//在斜矩阵的情况下，max 可以帮助 我们不受 不正确的近平面 或者 没有意义 的影响
			#define UNITY_Z_0_FAR_FROM_CLIPSPACE(coord) max(((1.0 - (coord) / _ProjectionParams.y) * _ProjectionParams.z), 0)
		#else
			//GL 翻转 Z => z Clip 范围 [near, -far] -> 在理论上应该重新映射，但在实践中不要这样做以节省一些性能（range足够接近）
			#define UNITY_Z_0_FAR_FROM_CLIPSPACE(coord) max( - (coord), 0)
		#endif
	#elif UNITY_UV_STARTS_AT_TOP
		//D3d 不用翻转 z => z Clip 范围 [0, far] -> 不用做
		#define UNITY_Z_0_FAR_FROM_CLIPSPACE(coord) (coord)
	#else
		//Opengl  z Clip 范围 [-near, far] -> 在理论上应该重新映射，但在实践中不要这样做以节省一些性能（范围足够近）
		#define UNITY_Z_0_FAR_FROM_CLIPSPACE(coord) (coord)
	#endif
	
	/*
	x = density / sqrt(ln(2)), by Exp2 mode
	y = density / ln(2), by Exp mode
	z = -1/(end-start), by Linear mode
	w = end/(end-start), by Linear mode
	*/
	
	#if defined(FOG_LINEAR)
		//UNITY_CALC_FOG_FACTOR_RAW 计算FOG 因子
		
		// factor = (end-z)/(end-start) = z * (-1/(end-start)) + (end/(end-start))
		#define UNITY_CALC_FOG_FACTOR_RAW(coord) float unityFogFactor = (coord) * unity_FogParams.z + unity_FogParams.w
	#elif defined(FOG_EXP)
		// factor = exp(-density*z)
		#define UNITY_CALC_FOG_FACTOR_RAW(coord) float unityFogFactor = unity_FogParams.y * (coord); unityFogFactor = exp2(-unityFogFactor)
	#elif defined(FOG_EXP2)
		// factor = exp(-(density*z)^2)
		#define UNITY_CALC_FOG_FACTOR_RAW(coord) float unityFogFactor = unity_FogParams.x * (coord); unityFogFactor = exp2(-unityFogFactor * unityFogFactor)
	#else
		#define UNITY_CALC_FOG_FACTOR_RAW(coord) float unityFogFactor = 0.0
	#endif
	
	//计算Fog因子
	#define UNITY_CALC_FOG_FACTOR(coord) UNITY_CALC_FOG_FACTOR_RAW(UNITY_Z_0_FAR_FROM_CLIPSPACE(coord))
	
	//Lerp Fog 颜色 根据Fog因子
	#define UNITY_FOG_LERP_COLOR(col, fogCol, fogFac) col.rgb = lerp((fogCol).rgb, (col).rgb, saturate(fogFac))
	
	
	#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
		#define UNITY_FOG_COORDS(idx) UNITY_FOG_COORDS_PACKED(idx, float1)
			
		#if (SHADER_TARGET < 30) || defined(SHADER_API_MOBILE)
			// 手机 或 SM2.0:
			//顶点阶段计算 fog因子
			#define UNITY_TRANSFER_FOG(o, outpos) UNITY_CALC_FOG_FACTOR((outpos).z); o.fogCoord.x = unityFogFactor
			//因为在顶点阶段已经计算了因子  ,所以只用在像素阶段lerp颜色就好了
			#define UNITY_APPLY_FOG_COLOR(coord, col, fogCol) UNITY_FOG_LERP_COLOR(col, fogCol, (coord).x)
			
		#else
			// 电脑/主机 或 SM3.0 :
			//顶点阶段只计算雾距离   其实就是屏幕空间的深度
			#define UNITY_TRANSFER_FOG(o, outpos) o.fogCoord.x = (outpos).z
			//在像素阶段计算 fog 因子 和 lerp颜色
			#define UNITY_APPLY_FOG_COLOR(coord, col, fogCOl) UNITY_CALC_FOG_FACTOR((coord).x); UNITY_FOG_LERP_COLOR(col, fogCol, unityFogFactor)
			
		#endif
	#else
		#define UNITY_TRANSFER_FOG(o, outpos)
		#define UNITY_APPLY_FOG_COLOR(coord, col, fogCol)
	#endif
	
	
	#ifdef UNITY_PASS_FORWARDADD
		#define UNITY_APPLY_FOG(coord, col) UNITY_APPLY_FOG_COLOR(coord, col, fixed4(0, 0, 0, 0))
	#else
		#define UNITY_APPLY_FOG(coord, col) UNITY_APPLY_FOG_COLOR(coord, col, unity_FogColor)
	#endif
	
#endif // UNITY_CG_INCLUDED
