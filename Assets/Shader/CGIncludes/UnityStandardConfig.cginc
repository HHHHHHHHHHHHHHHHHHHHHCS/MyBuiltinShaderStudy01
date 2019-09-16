#ifndef UNITY_STANDARD_CONFIG_INCLUDED
	#define UNITY_STANDARD_CONFIG_INCLUDED
	
	//mipmap step  * roughness -> mipmap等级
	#ifndef UNITY_SPECCUBE_LOD_STEPS
		#define UNITY_SPECCUBE_LOD_STEPS (6)
	#endif
	
	//orthnormalize每个像素的切线空间基
	//必须支持高质量的正常地图。与Maya和Marmoset兼容。
	//然而xnormal期望旧的非标准化基础-本质上防止好看的标准映射：（
	//由于Xnormal可能是目前最常用的烘焙法线贴图的工具，我们现在必须坚持使用旧方法。
	//默认情况下禁用，直到xnormal有权烘焙正确的法线贴图。
	#ifndef UNITY_TANGENT_ORTHONORMALIZE
		#define UNITY_TANGENT_ORTHONORMALIZE 0
	#endif
	
#endif // UNITY_STANDARD_CONFIG_INCLUDED
