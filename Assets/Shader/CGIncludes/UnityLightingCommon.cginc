#ifndef UNITY_LIGHTING_COMMON_INCLUDED
	#define UNITY_LIGHTING_COMMON_INCLUDED

	fixed4 _LightColor0;
	fixed4 _SpecColor;

	struct UnityLight
	{
		half3 color;
		half3 dir;
		half ndotl;//已弃用：ndotl现在是动态计算的，不再存储。不要用它。
	};

#endif
