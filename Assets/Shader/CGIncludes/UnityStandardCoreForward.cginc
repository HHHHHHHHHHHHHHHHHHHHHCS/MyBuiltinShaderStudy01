#ifndef UNITY_STANDARD_CORE_FORWARD_INCLUDED
	#define UNITY_STANDARD_CORE_FORWARD_INCLUDED
	
	#if defined(UNITY_NO_FULL_STANDARD_SHADER)
		#define UNITY_STANDARD_SIMPLE 1
	#endif //UNITY_NO_FULL_STANDARD_SHADER
	
	#include "UnityStandardConfig.cginc"
	
	#if UNITY_STANDARD_SIMPLE
		//如果应使用具有额外简化的标准着色器BRDF3，则设置UNITY_NO_FULL_STANDARD_SHADER。
		#include "CGIncludes/UnityStandardCoreForwardSimple.cginc"
		VertexOutputBaseSimple vertBase(VertexInput v)
		{
			return vertForwardBaseSimple(v);
		}
		
		VertexOutputForwardAddSimple vertAdd(VertexInput v)
		{
			return vertForwardAddSimple(v);
		}
		
		half4 fragBase(vertexOutputBaseSimple i): SV_TARGET
		{
			return fragForwardBaseSimpleInternal(i);
		}
		
		half4 fragAdd(VertexOutputForwardAddSimple i): SV_TARGET
		{
			return fragForwardAddSimpleInternal(i);
		}
		
	#else
		#include "UnityStandardCore.cginc"
		VertexOutputForwardBase vertBase(VertexInput v)
		{
			return vertForwardBase(v);
		}
		
		VertexOutputForwardAdd vertAdd(VertexInput v)
		{
			return vertForwardAdd(v);
		}
		
		half4 fragBase(VertexOutputForwardBase i): SV_TARGET
		{
			return fragForwardBaseInternal(i);
		}
		
		half4 fragAdd(VertexOutputForwardAdd i): SV_TARGET
		{
			return fragForwardAddInternal(i);
		}
		
	#endif //UNITY_STANDARD_SIMPLE
	
	
#endif // UNITY_STANDARD_CORE_FORWARD_INCLUDED