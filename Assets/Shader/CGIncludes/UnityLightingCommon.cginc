#ifndef UNITY_LIGHTING_COMMON_INCLUDED
	#define UNITY_LIGHTING_COMMON_INCLUDED

	fixed4 _LightColor0;
	fixed4 _SpecColor;

	//灯光结构体
	struct UnityLight
	{
		half3 color;
		half3 dir;
		half ndotl;//已弃用：ndotl现在是动态计算的，不再存储。不要用它。
	};

	//漫反射和高光反射结构体
	struct UnityIndirect
	{
		half3 diffuse;
		half3 specular;
	}

	//灯光结构体和反射结构体
	struct UnityGI
	{
		UnityLight light;
		UnityIndirect indirect;
	}

	struct UnityGIInput
	{
		UnityLight light;//像素灯光,信息来自引擎

		float3 worldPos;
		half3 worldViewDir;
		half atten;
		half3 ambient;
		
		//应该使用全浮点精度,以避免数据丢失
		float4 lightmapUV;// .xy = static lightmap UV, .zw = dynamic lightmap UV

		#if defined(UNITY_SPECCUBE_BLENDING) || defined(UNITY_SPECUBE_BOX_PROJECTION) || defined(UNITY_ENABLE_REFLECTION_BUFFERS)
			float4 boxMin[2];
		#endif

		#ifdef UNITY_SPECCUBE_BOX_PROJECTION
			float4 boxMax[2];
			float4 probePosition[2];
		#endif

		//HDR cubemap 属性,使用解压的HDR贴图
		float4 probeHDR[2];
	};

#endif
