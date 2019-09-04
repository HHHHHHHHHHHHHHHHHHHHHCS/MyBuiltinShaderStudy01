#ifndef UNITY_CG_INCLUDED
	#define UNITY_CG_INCLUDED
	
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
	
#endif // UNITY_CG_INCLUDED
