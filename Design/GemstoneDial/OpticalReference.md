# 单颗蓝晶的光路基准

`ValidateOpticalTransport.metal` 直接使用生产着色程序中的介质转换、折射、全反射和实际行程吸收函数，检查嵌套介质、同材质不同物体、交叠物体逆序退出、全反射保持介质、等折射率界面与容量边界。

单颗蓝晶基准参考 [Drei 的 MeshRefractionMaterial](https://github.com/pmndrs/drei/blob/master/src/materials/MeshRefractionMaterial.tsx) 的逃逸光路：先进入晶体，内部遇到可折射出口时返回方向，无法折射时继续反射。对照用同一闭合蓝晶和几何法线，通过苹果图形接口的实际三角形求交运行。它验证单颗晶体的光路，不等于两套完整渲染器的像素级画质对照；生产渲染还包含菲涅耳权重、吸收、散射、相邻物体与金属。

原始材质作者：N8Programs，原始项目 https://github.com/N8python/diamonds 。

## 上游许可

MIT License

Copyright (c) 2020 react-spring

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## 局部光源的静态照明

局部照明采用从光源发射路径、再进行空间密度估计的思路，概念参考 [PBRT 的光子映射章节](https://pbr-book.org/3ed-2018/Light_Transport_III_Bidirectional_Methods/Stochastic_Progressive_Photon_Mapping)。这里没有复制其源代码，也没有实现完整的渐进光子映射：实现使用固定次数光源路径、有限体积网格、定点累积和过滤重建，作为实时材质的静态受光近似。光源分布按面积与亮度取样，路径穿过实际晶体界面，并验证相邻非发光晶体的受光会被吸光板阻断。
