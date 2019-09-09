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
