//-----------------------------------------------------------------------------
//注意：
//此文件中的所有函数都已弃用且不应使用，它们将在更高版本中被删除。
//这里允许它们向后兼容。
//此文件收集与着色器代码不同部分（如brdf或基于图像的照明）相关的多个函数
//为了避免创建多个不推荐使用的文件，该文件包含基于
//包含此文件时，调用方应定义要启用的已弃用的函数组
//例如，下面的代码将包含所有不推荐使用的brdf函数：
// #define INCLUDE_UNITY_STANDARD_BRDF_DEPRECATED
// #include "UnityDeprecated.cginc"
// #undef INCLUDE_UNITY_STANDARD_BRDF_DEPRECATED
//-----------------------------------------------------------------------------

#ifdef INCLUDE_UNITY_STANDARD_BRDF_DEPRECATED
	inline half DotClamped(half3 a, half3 b)
	{
		#if (SHADER_TARGET < 30)
			//SM2.0 判断限制
			return saturate(dot(a, b));
		#else
			return max(0.0h, dot(a, b));
		#endif
	}
	
	inline half LambertTerm(half3 normal, half3 lightDir)
	{
		return DotClamped(normal, lightDir);
	}
	
#endif // INCLUDE_UNITY_IMAGE_BASED_LIGHTING_DEPRECATED