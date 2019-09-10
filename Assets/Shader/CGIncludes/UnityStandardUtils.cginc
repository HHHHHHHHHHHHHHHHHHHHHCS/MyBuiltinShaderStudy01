#ifndef UNITY_STANDARD_UTILS_INCLUDED
	#define UNITY_STANDARD_UTILS_INCLUDED
	
	#include "CGIncludes/UnityCG.cginc"
	#include "UnityStandardConfig.cginc"
	
	//和白色进行Lerp
	half3 LerpWhiteTo(half3 b, half t)
	{
		half oneMiusT = 1 - t;
		//look like
		//half3 temp = half3(1,1,1)*(1-t) + b*t;
		return half3(oneMiusT, oneMiusT, oneMiusT) + b * t;
	}
	
	//和1进行Lerp
	half LerpOneTo(half b, half t)
	{
		half oneMinusT = 1 - t;
		//look like:
		// 1*(1-t)+b*t
		return oneMinusT + b * t;
	}
	
	//计算反射度 高光反射的 r/g/b 最大值
	half SpecularStrength(half3 specular)
	{
		#if (SHADER_TARGET < 30)
			//SM2.0 因为指令计数限制 所以简化了通道    制作贴图时正常都是用R通道
			return specular.r;
		#else
			return max(max(specular.r, specular.g), specular.b);
		#endif
	}
	
	//计算反射度 跟 1-金属度 近似
	inline half OneMinusReflectivityFromMetallic(half metallic)
	{
		// We'll need oneMinusReflectivity, so
		//   1-reflectivity = 1-lerp(dielectricSpec, 1, metallic) = lerp(1-dielectricSpec, 0, metallic)
		// store (1-dielectricSpec) in unity_ColorSpaceDielectricSpec.a, then
		//   1-reflectivity = lerp(alpha, 0, metallic) = alpha + metallic*(0 - alpha) =
		//                  = alpha - metallic * alpha
		half oneMinusDielectricSpec = unity_ColorSpaceDielectricSpec.a;
		return oneMinusDielectricSpec - metallic * oneMinusDielectricSpec;
	}
	
	//根据金属度得到满反射和高光反射的颜色
	inline half3 DiffuseAndSpecularFromMetallic(half3 alebdo, half metallic, out half3 specColor, out half oneMinusReflectivity)
	{
		specColor = lerp(unity_ColorSpaceDielectricSpec.rgb, alebdo, metallic);
		oneMinusReflectivity = OneMinusReflectivityFromMetallic(metallic);
		return alebdo * oneMinusReflectivity;
	}
	
	//预乘Alpha
	inline half3 PreMultiplyAlpha(half3 diffColor, half alpha, half oneMinusReflectivity, out half outModifiedAlpha)
	{
		#if defined(_ALPHAPREMULTIPLY_ON)
			//注意：着色器依赖于预乘alpha混合(_srcblund=one,_dstblund=oneminussrcalpha)
			//从漫反射组件中“移除”透明度
			diffColor *= alpha;
			
			#if (SHADER_TARGET < 30)
				//SM2.0:指令计数限制  所以使用为修改的Alpha
				//但是会牺牲部分基于物理的透明度,因为反射率的大小会影响透明度
				outModifiedAlpha = alpha;
			#else
				//reflectivity“移除”其他组件，包括透明度
				// outAlpha = 1-(1-alpha)*(1-reflectivity) =
				//			= 1-(1 - reflectivity - alpha + alpha*reflectivity) =
				//			= 1-((1 - reflectivity) - alpha * (1 - reflectivity)) =
				//			= 1-(oneMinusReflectivity - alpha*oneMinusReflectivity) =
				//			= 1-oneMinusReflectivity + alpha*oneMinusReflectivity
				outModifiedAlpha = 1 - oneMinusReflectivity + alpha * oneMinusReflectivity;
			#endif
		#else
			outModifiedAlpha = alpha;
		#endif
		
		return diffColor;
	}
	
	//计算球谐光----顶点状态
	half3 ShadeSHPerVertex(half3 normal, half3 ambient)
	{
		#if UNITY_SAMPLE_FULL_SH_PER_PIXEL
			//如果是完全按像素计算,则此处不做任何操作
		#elif (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE
			//完全按照顶点计算
			ambient += max(half3(0, 0, 0), ShadeSH9(half4(normal, 1.0)));
		#else
			//注意：sh数据始终是线性的，计算在顶点和像素之间分割
			//将环境光转换为线性，并在最后进行最终伽马校正(每像素)
			#ifdef UNITY_COLORSPACE_GAMMA
				ambient = GammaToLinearSpace(ambient);
			#endif
			//L2的贡献是叠加
			ambient += SHEvalLinearL2(half4(normal, 1.0));
		#endif
		
		return ambient;
	}
	
	half3 ShadeSHPerPixel(half3 normal, half3 ambient, float3 worldPos)
	{
		half3 ambient_contrib = 0.0;
		
		//完全按照像素球谐
		#if UNITY_SAMPLE_FULL_SH_PER_PIXEL
			#if UNITY_LIGHT_PROBE_PROXY_VOLUME
				//unity_ProbeVolumeParams.x == 1   启用了光照探针  则用探针的ambient
				//否则用普通的ambient
				if (unity_ProbeVolumeParams.x == 1.0)
					ambient_contrib = SHEvalLinearL0L1_SampleProbeVolume(half4(normal, 1.0), worldPos);
				else
				ambient_contrib = SHEvalLinearL0L1(half4(normal, 1.0));
			#else
				ambient_contrib = SHEvalLinearL0L1(half4(normal, 1.0));
			#endif
			
			//二级球谐
			ambient_contrib += SHEvalLinearL2(half4(normal, 1.0));
			
			//避免颜色负数
			ambient += max(half3(0, 0, 0), ambient_contrib);
			
			//颜色Gamma校对
			#ifdef UNITY_COLORSPACE_GAMMA
				ambient = LinearToGammaSpace(ambient);
			#endif
			
		#else if (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE
			//完全逐顶点
			//这里没什么事。从sh开始的环境光的gamma转换发生在顶点着色器中，请参见shadeshpervertex。
		#else
			#if UNITY_LIGHT_PROBE_PROXY_VOLUME
				//unity_ProbeVolumeParams.x == 1   启用了光照探针
				if (unity_ProbeVolumeParams.x == 1.0)
					ambient_contrib = SHEvalLinearL0L1_SampleProbeVolume(half4(normal, 1.0), worldPos);
				else
				ambient_contrib = SHEvalLinearL0L1(half4(normal, 1.0));
			#else
				ambient_contrib = SHEvalLinearL0L1(half4(normal, 1.0));
			#endif
			
			//因为已经在顶点中计算了L2的贡献  所以在像素中不用再加了
			ambient = max(half3(0, 0, 0), ambient + ambient_contrib);
			
			#ifdef UNITY_COLORSPACE_GAMMA
				ambient = LinearToGammaSpace(ambient);
			#endif
		#endif
		
		return ambient;
	}
	
	half3 UnpackScalenormalRGorAG(half4 packednormal, half bumpScale)
	{
		#if defined(UNITY_NO_DXT5nm)
			half3 normal = packednormal.xyz * - 1;
			#if (SHADER_TARGET >= 30)
				//SM2.0:因为指令计数器限制  所以normal scale 不支持
				normal.xy *= bumpScale;
			#endif
			return normal;
		#else
			//DXT5 压缩了z 然后用 z = sqrt(1-(x*x+y*y))
			//贴图格式规定 做欺骗用
			packednormal	.x *= packednormal.w;
			
			half3 normal;
			normal.xy = packednormal.xy * 2 - 1;
			#if (SHADER_TARGET >= 30)
				//SM2.0:因为指令计数器限制  所以normal scale 不支持
				normal.xy *= bumpScale;
			#endif
			normal.z = sqrt(1.0 - saturate(dot(normal.xy, normal.xy)));
			return normal;
		#endif
	}
	
	half3 UnpackScaleNormal(half4 packednormal, half bumpScale)
	{
		return UnpackScalenormalRGorAG(packednormal, bumpScale);
	}
	
	half3 BlendNormals(half3 n1, half3 n2)
	{
		return normalize(half3(n1.xy + n2.xy, n1.z * n2.z));
	}
	
#endif // UNITY_STANDARD_UTILS_INCLUDED
