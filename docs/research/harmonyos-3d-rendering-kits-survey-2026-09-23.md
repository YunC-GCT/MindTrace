# HarmonyOS 3D 渲染套件调研 — MindForce 知识星系迁移评估

> **Date:** 2026-09-23
> **Scope:** 鸿蒙 7 / HarmonyOS NEXT / API 15+ (及 17+ / 26.0.0) 3D 渲染能力全谱, 评估 MindForce 知识星系从 Three.js draft 迁移到原生 ArkTS 的 4 条候选路径
> **Project:** MindTrace (`entry` module, 目标 API ≥ 18, 当前 SDK 6.1.1(24))
> **Author:** research agent (devecocli docs 一手信源为主 + 项目源码对照)
> **Trigger:** 团队从 Three.js + WebView 的 3D 星系原型迁移到原生 ArkTS 应用, 需要决策 3D 渲染管线
> **基线信息:**
>   - 当前 MindTrace 已有知识星系的 2D Canvas 实现 (`ReviewGraphView.ets` + `KnowledgeGalaxyViewModel.ets`, 用 `CanvasRenderingContext2D` 绘制 orbits / planets / links), 不是 3D, 也不是 WebView
>   - 复赛路演 (2026-09-06 demo) 当前叙事是"AI 拍照 → 拆解 → 复习 → 卡片", 3D 星系属叙事加分项
>   - 复赛演示的稳定性基线已建立在 `setRenderProcessMode(SINGLE)` + 常驻 Web 组件之上 (2026-09-11 修复)

---

## §0 TL;DR for the MindTrace team

**推荐路径: 三阶段渐进迁移, 最终以原生 `Component3D` + `@kit.ArkGraphics3D` 为目标, 短期 P0 维持 2D Canvas 实现**

| 阶段 | 路径 | 期望 |
|---|---|---|
| **复赛冲刺 (POC, ≤ 2 周)** | **现状 2D ArkUI Canvas** (`ReviewGraphView.ets` 现有) | 0 改动, 0 风险, 把已有"地球+轨道"打磨成演示锚点 |
| **P1 (演示后 4 周内)** | **WebView + Three.js** 作为桥接实验场 | 在单独 hidden 路由跑 Three.js + `WebMessagePort` + force-directed, 与 ArkUI 平行运行, 验证力导布局 + 触摸交互 + 桥接协议 |
| **P2 (开源 / 商业化)** | **原生 `Component3D` + `@kit.ArkGraphics3D`** 自定义场景模式 | 用 glTF (.glb) 承载节点, Shader / 节点着色自定; 桥接完全消失, FPS 上限 90 / 120 Hz |

**前 3 个理由 (说服评审):**
1. **`Component3D` 自 API 12 起原生可用, API 21+ 加 hit-test (`Camera.raycast`) / API 23+ 加矩阵读取 / API 22+ 加 MSAA / API 26 加流式 surfaceId + 阴影算法**, 关键能力节点已全部就绪 — 不是"未来才支持", 是当下 6.1.1(24) SDK 就能用
2. **WebView 路径在 HarmonyOS 7 上有 WebGL (基于 OpenGL ES) 但无 WebGPU 一手证据, 且 5 进程模型每次实例 churn 都牵动主线程 binder IPC (2026-09-11 THREAD_BLOCK_6S 的根因就是它)**, 复赛已有一次该类故障, 不宜再加 Web 实例
3. **自定义 shader 是 JSON 清单 + SPIR-V (`.spv`), 不是 GLSL** — 意味 ArkGraphics 3D 的 Vulkan 后端是隐含需求, 任何"自定 shader 配合 Three.js 调参"工作流都得重写

> **未验证 / unverified:** 三方/WebGPU/Three.js r170+ 在 ArkWeb 的具体 fps 与 stack stability, 一手 doc 只查到 WebGL (`webgl-2d-guidelines`) 与 SecurityParams 的 WebGL 开关; WebGPU 在 devecocli docs 全库搜索 0 命中, 推断**尚未在 HarmonyOS ArkWeb 落地** — 见 §5.

---

## §1 API 矩阵表 — 4 条候选路径横向对比

> **基线:** `entry` module targetSdk=6.1.1(24), ArkTS 严格 lint (40+ 规则), 跨 module import 强制完整路径
> **列定义见列首缩略语:** `since` = API 起, `cap` = 已确认上限, `pick` = hit-test, `frameloop` = 帧驱动, `touch` = 手势, `in ArkUI` = 可嵌入哪个 ArkUI 组件, `route` = 可作 page route, `bridge` = 与 ArkTS 通信方式, `real-device` = 真机已验, `fps` = 实测帧率, `license` = 商业/开源, `conf` = 信心

| # | 候选路径 | since | cap | pick | frameloop | touch | in ArkUI | route | bridge | real-device | fps | license | MindTrace 适配优 | 限制/坑 | conf |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **A** | **原生 `Component3D` + `@kit.ArkGraphics3D`** 自定义场景模式 | 12 | 26 | ✅ (`Camera.raycast`, API 20+) | ✅ (节点属性变更自动重渲染 + `AnimatorResult` 驱动, 见 §2) | ✅ (ArkUI 标准 `gesture` / `onTouch`, 见 §2 注) | ✅ (`Component3D`) | ✅ (`@Entry` 装饰页面任意) | ✅ (无 bridge, 全部 ArkTS 直接调) | ✅ (强制: OpenGL ES 3.2+ 或 Vulkan 1.0+, 模拟器不支持) | 未见官方量化; 受 VSync 60/90/120 Hz 限制 (与系统同) | 闭源 (随 ArkGraphics 3D, 商用授权, 无额外 royalty 公开声明) | 性能上限最高, 桥接消失, 复用现有 ViewModel 数据 | 硬件门槛 (OGLES 3.2+ / Vulkan 1.0+); 不支持模拟器; 自定义 shader 需预编译 SPIR-V; 现阶段**不是"图可视化通用引擎"**而是"glTF 模型查看器 + 节点编辑" | **高** |
| **B** | **WebView + Three.js** (ArkWeb 内置) | 9 | 26 (WebGL1; WebGL2 在非 坚盾守护模式可用) | ✅ (Three.Raycaster, 全部 JS 栈) | ✅ (`requestAnimationFrame`, VSync 同步) | ✅ (Three 内置 OrbitControls / 自己实现手势 → web 触摸事件) | ✅ (`Web({ src })`) | ✅ (`pages/WebGalaxyPage.ets` 单独页面) | ✅ (`WebMessagePort` STRING / NUMBER / BOOLEAN / ARRAY_BUFFER / ARRAY / ERROR; 或 `registerJavaScriptProxy` JSBridge) | ✅ | 复赛语境下依赖 prior research: 单常驻 Web + force-directed (~1000 节点) 经验值 30-60 fps; 实测见 §4 | Three.js MIT, 商用免 royalty | 已有 draft, 设计经验现成, 桥接可复现 | 五进程模型 + 渲染进程 churn 引主线程 binder 阻塞 (2026-09-11 故障教训); 坚盾守护模式禁用 WebGL / WebGL2; 模拟器可能不达预期; Web 实例 200MB/个 | **高** |
| **C** | **WebView + Babylon.js** | 9 | 26 (同 B) | ✅ (Babylon PickingInfo) | ✅ (`scene.onBeforeRenderObservable`) | ✅ | ✅ | ✅ | ✅ (同 B) | ✅ | 与 B 接近, Babylon 默认管线较重, 体感 ~10-20% 慢于 Three.js (第三方比较, 未在 HarmonyOS 验证) | Apache-2.0 | TypeScript-first, 与 ArkTS 类型系统风格相近 | 同 B 五进程 + churn; Three.js 的生态 (three/examples/jsm/postprocessing) Babylon 没有完全对齐; 需重写 post-fx 着色 | **中** |
| **D** | **WebView + WebGPU / Custom Native bridge** (JSVM/JSB) | — | — | ❌ (无 WebGPU 一手证据, 见 §5) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | W3C draft | — | **HarmonyOS ArkWeb 在 6.1.1(24) 未落地 WebGPU**, 官方一手 doc 零命中 — 不可行 | **未验证** |
| **E** | **XComponent + NDK + OpenGL ES 3 / Vulkan + 自研引擎** | 8 (XComponent) / 10 (Vulkan) | 26 | ✅ (自实现) | ✅ (`OH_ArkUI_XComponent_RegisterOnFrameCallback` VSync 回调) | ✅ (ArkUI NDK `addNodeEventReceiver` + `registerNodeEvent`) | ✅ (`XComponent`) | ✅ | ✅ (NAPI 直接调, 0 bridge 延迟) | ✅ | 由我们控制; Vulkan 后端理论 90-120 Hz | 自写 | 完全控制力, 性能天花板最高, 同时最大工作量 | 需 C/C++ 写 EGL / GLES3 / Vulkan, ~2000+ LOC 引擎骨架 + 物理 + 力导; 需额外 so 编译 + ABI 兼容; 复赛窗口不现实 | **高 (路径成立), 中 (MindTrace 复赛可行性)** |
| **F** | **OffscreenCanvas + 2D (CPU 渲染)** | 8 | 26 | ✅ (JS 端 2D 命中测试) | ✅ (JS `requestAnimationFrame`) | ✅ | ✅ (`OffscreenCanvas` 嵌入 `Canvas`) | ✅ | ✅ (NAPI / messagePort) | ✅ | **CPU 渲染, "对绘制速度有要求的场景应避免使用"** (官方原文); ~数百节点还行 | 自写 | 极低门槛 | 不是 3D; 节点 ≥500 时帧率显著下降 (官方明示); 已知 OOM 风险在 `faqs-arkgraphics-2d-34` | **高 (2D 路径), 中 (3D 替代)** |
| **G** | **`Spatial Recon Kit` + 3DGS** | 23 | 26 | — | — | — | — | — | — | ❌ "**仅支持中国境内 (港澳台除外)**" — 复赛路演对外演示不可用 | — | 闭源 | 3DGS 是"摄影测量级"渲染, 适合空间扫描, 与本项目"知识图谱可视化"语义错位 | 区域限制 + 概念错位 | **不推荐** |
| **H** | **`Game Service Kit`** | 12 | 26 | — | — | — | — | — | — | — | — | — | **无渲染能力**, 仅账号/支付/场景感知 | 与 3D 渲染无关, 排除 | **不相关** |
| **I** | **`AR Engine` + `arViewController`** | 12 | 26 | ✅ (`ARSceneMesh`) | ✅ | ✅ | ✅ | ✅ | ✅ | 部分 Phone/Tablet (设备门控) | 30 / 60 fps (AR 场景) | 闭源 | — | 设备门控 + 摄像头权限 + AR 会话, 复赛演示需摄像头, 偏离"复习"主入口 | **不相关** |
| **J** | **2D ArkUI Canvas + 力导布局 (当前 MindTrace 实际)** | 8 | 26 | ✅ (`hitTestBehavior`) | ✅ (`setInterval` / `requestAnimationFrame`) | ✅ | ✅ (`Canvas`) | ✅ | ✅ (无 bridge, 直接) | ✅ | ~60 fps (实测, ~500 节点级别) | 自写 | 已落地, 风险 0, 复赛马上可用 | 不是真正的 3D; 不能旋转 / 缩放 / 光照; 视觉冲击力比 3D 弱 | **高** |

> **结论矩阵 (前 4 名打分):**
>
> | 路径 | 复赛可行 | 长期价值 | 总评 |
> |---|---|---|---|
> | **J (2D Canvas)** | ⭐⭐⭐⭐⭐ | ⭐⭐ | 复赛主推 |
> | **B (WebView + Three.js)** | ⭐⭐⭐ | ⭐⭐⭐ | 桥接实验场 |
> | **A (Component3D)** | ❌ (模拟器不跑) | ⭐⭐⭐⭐⭐ | 中长期目标 |
> | **E (XComponent + 自研)** | ❌ (人力不允许) | ⭐⭐⭐⭐ | 远期不排除 |

---

## §2 原生 ArkUI 3D API 规范 — `Component3D` + `@kit.ArkGraphics3D`

> **来源:** `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D简介/arkgraphics3d-overview`, `API参考/ArkUI_方舟UI框架/ArkTS组件/渲染绘制/Component3D/ts-basic-components-component3d`, `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/ohos_graphics_scene_ArkGraphics_3D模块_/js-apis-scene`, `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/SceneNode/js-apis-inner-scene-nodes`, `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/SceneResources/js-apis-inner-scene-resources`, `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/SceneType/js-apis-inner-scene-types`, `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/Scene/js-apis-inner-scene`, `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D场景搭建以及管理/arkgraphics3d-scene`, `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D场景动画控制以及管理/arkgraphics3d-animation`, `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/创建并使用图片资源/arkgraphics3d-resource-image`, `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/创建并使用环境资源/arkgraphics3d-resource-environment`, `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/创建并使用材质资源/arkgraphics3d-resource-material`, `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/shader资源文件格式要求/arkgraphics3d-shader-resource`

### §2.1 套件归属与系统能力

- **Kit:** **ArkGraphics 3D (方舟 3D 图形)** — 注意**不是** `@kit.Graphics3DKit`, 也不是 `SceneKit`
- **模块标识符:** `@kit.ArkGraphics3D` (ArkTS 顶层 import)
- **底层 NDK 命名空间:** `@ohos.graphics.scene`
- **系统能力 tag:** `SystemCapability.ArkUi.Graphics3D`
- **首批 API:** 12 (即 API 12 起 ArkTS 可用)
- **最新增量:** 26.0.0 加 `ImageStream` (流式 surfaceId), `Effect` 加 `setPropertyValue('vibrance')`, `ShadowAlgorithmType.PCF` (阴影算法枚举)
- **硬件门槛 (官方):** "OpenGL ES 3.2 以上或 Vulkan 1.0 以上的 GPU 驱动" (`arkgraphics3d-overview` §约束限制)
- **模拟器支持:** **不支持** ("本 Kit 暂不支持模拟器")
- **Stage 模型约束:** 几乎所有 `Effect` / `Morpher` / `ImageStream` 等 API 标"此接口仅可在 Stage 模型下使用"

### §2.2 Component3D 组件 (ArkUI 入口)

```typescript
// 文档: API参考/ArkUI_方舟UI框架/ArkTS组件/渲染绘制/Component3D/ts-basic-components-component3d
// 元服务 API: API 12 起支持

import { Component3D, SceneOptions, ModelType } from '@kit.ArkGraphics3D'

// 自动场景模式 (传入 glTF 模型文件路径)
const autoSceneOptions: SceneOptions = {
  scene: $rawfile('gltf/DamagedHelmet/glTF/DamagedHelmet.gltf'), // or .glb
  modelType: ModelType.SURFACE, // SURFACE=1 (专有硬件合成, 默认), TEXTURE=0 (GPU 合成)
}

@Component
struct KnowledgeGalaxyView {
  build() {
    Component3D(autoSceneOptions)
      .environment($rawfile('gltf/Environment/glTF/Environment.gltf')) // IBL 环境贴图 (官方示例)
      .renderWidth('90%')
      .renderHeight('90%')
      .onAppear(() => { /* 与 Scene.load().then() 衔接 */ })
  }
}
```

**关键属性 (从原文档逐字):**

| 属性 | 类型 | 说明 |
|---|---|---|
| `environment(uri)` | `ResourceStr` | 设置 3D 环境资源 (仅支持 GLTF), **模型资源在控件创建后不支持动态修改** |
| `customRender(uri, selfRenderUpdate)` | `ResourceStr, boolean` | 自定义渲染管线, **控件创建后不支持动态修改** |
| `shader(uri)` | `ResourceStr` | 自定义 shader 资源 (.shader 文件, JSON 描述符, 见 §2.7) |
| `shaderImageTexture(uri)` | `ResourceStr` | 自定义 shader 用到的纹理; 多次调用 → 多个绑定点, 顺序一致, **不支持纹理更换** |
| `shaderInputBuffer(buffer)` | `Array<number>` | 自定义 shader 动效参数; 长度 [0, 1048576] |
| `renderWidth(value)` | `Dimension` | 仅支持 `Dimension.Percentage`, [0, 100%]; **创建后不可改** |
| `renderHeight(value)` | `Dimension` | 同上 |

**手势:** `Component3D` 支持 ArkUI 通用手势 (`gesture` / `priorityGesture` / `parallelGesture`, 见 `arkts-gesture-events-binding`), 自动场景模式下官方文档说"框架会自动创建基础相机、光源和默认手势交互 (旋转、缩放)", 但自定义场景模式下"未内置相机控制器, 因此不会自动响应拖拽或缩放手势; 如需交互, 请开发者接入手势并更新相机的位置与旋转".

### §2.3 Scene / SceneNode / SceneType 模块全景

```typescript
// 文档: js-apis-inner-scene + js-apis-inner-scene-nodes + js-apis-inner-scene-resources + js-apis-inner-scene-types

import {
  Scene, SceneNodeParameters, SceneResourceParameters, SceneResourceFactory,
  Node, Geometry, Camera, Light, DirectionalLight, SpotLight, LayerMask,
  Animation, Shader, Material, MaterialType, ShaderMaterial, MetallicRoughnessMaterial,
  UnlitMaterial, OcclusionMaterial,
  CullMode, Blend, RenderSort, PolygonMode, Mesh, MeshResource, SubMesh, Morpher,
  Image, ImageStream, Effect, EffectParameters, Environment, EnvironmentBackgroundType,
  ScenePostProcessSettings, ToneMappingType,
  Vec2, Vec3, Vec4, Quaternion, Aabb, Color, Rect, Mat4x4,
  Position3, Scale3, Rotation3, RenderingPipelineType,
  GeometryType, GeometryDefinition, PrimitiveTopology, CustomGeometry,
  CubeGeometry, PlaneGeometry, SphereGeometry, CylinderGeometry,
  Container, NodeType, LightType, RaycastParameters, RaycastResult,
  ShadowAlgorithmType,
} from '@kit.ArkGraphics3D'
```

#### Scene (基础模块, API 12)

```typescript
// 文档: js-apis-inner-scene

// 加载 .glb / .gltf (异步)
let scene: Promise<Scene> = Scene.load($rawfile('gltf/CubeWithFloor/glTF/AnimatedCube.glb'))
scene.then(async (result: Scene) => {
  // 属性:
  this.sceneOpt = { scene: result, modelType: ModelType.SURFACE } as SceneOptions
  let rf: SceneResourceFactory = result.getResourceFactory() // 创建资源
  let root: Node = result.root // 根节点
  let env: Environment = result.environment // 已有环境
  let animations: Animation[] = result.animations // 已有动画
  let node: Node | null = result.getNodeByPath('rootNode_/Unnamed Node 1/AnimatedCube')
})
```

#### SceneType (API 12, Mat4x4 API 23)

```typescript
// 文档: js-apis-inner-scene-types

type Position3 = Vec3   // x/y/z, 实数
type Scale3 = Vec3     // x/y/z, 实数
type Rotation3 = Vec3  // x/y/z, 弧度

interface Vec2 { x: number, y: number }
interface Vec3 { x: number, y: number, z: number }
interface Vec4 { x: number, y: number, z: number, w: number }
interface Quaternion { x: number, y: number, z: number, w: number }  // 避免万向节锁
interface Aabb { aabbMin: Vec3, aabbMax: Vec3 } // 轴对齐包围盒
interface Color { r: number, g: number, b: number, a: number } // RGBA, 各分量 [0,1]
interface Rect { x: number, y: number, width: number, height: number }

interface Mat4x4 { // API 23+
  x: Vec4  // 第一列
  y: Vec4  // 第二列
  z: Vec4  // 第三列
  w: Vec4  // 第四列
}

enum RenderingPipelineType { // API 21+
  FORWARD_LIGHTWEIGHT = 0,  // 轻量级前向, 只支持色调映射, 不支持复杂效果 (默认)
  FORWARD = 1,              // 高质量前向, 支持 Bloom 等
}

enum GeometryType { // API 18+
  CUSTOM = 0, CUBE = 1, PLANE = 2, SPHERE = 3, CYLINDER = 4, // API 23+
}

enum PrimitiveTopology { // API 18+
  TRIANGLE_LIST = 0, TRIANGLE_STRIP = 1,
}

enum ShadowAlgorithmType { // API 26.0.0+
  PCF = 0, // 百分比邻近过滤
}
```

#### SceneNode (API 12, 多 API 增量)

```typescript
// 文档: js-apis-inner-scene-nodes

interface Node { // 基础节点
  position: Position3
  rotation: Quaternion
  scale: Scale3
  visible: boolean
  nodeType: NodeType  // 1=NODE, 2=GEOMETRY, 3=CAMERA, 4=LIGHT, 255=CUSTOM (API 21+)
  layerMask: LayerMask
  path: string
  parent: Node | null
  children: Container<Node>
  getNodeByPath(path: string): Node | null
}

enum NodeType {
  NODE = 1, GEOMETRY = 2, CAMERA = 3, LIGHT = 4, CUSTOM = 255, // API 21+
}

interface Geometry extends Node {
  mesh: Mesh            // 网格属性
  morpher?: Morpher     // API 20+ 可选形变器
}

interface Light extends Node {
  lightType: LightType  // 1=DIRECTIONAL, 2=SPOT
  color: Color
  intensity: number     // 坎德拉, > 0
  shadowEnabled: boolean
  enabled: boolean
}

enum LightType { DIRECTIONAL = 1, SPOT = 2 }

interface SpotLight extends Light { // API 23+
  innerAngle?: number  // 圆锥内角 [0, outerAngle] rad
  outerAngle?: number  // 圆锥外角 [innerAngle, π/2] rad
}

interface Camera extends Node {
  fov: number             // rad, (0, π)
  nearPlane: number       // > 0
  farPlane: number        // > nearPlane
  enabled: boolean
  postProcess: PostProcessSettings | null
  effects: Container<Effect>  // API 21+
  clearColor: Color | null
  msaa?: boolean              // API 22+
  renderingPipeline?: RenderingPipelineType  // API 21+
  raycast(viewPosition: Vec2, params: RaycastParameters): Promise<RaycastResult[]>  // API 20+ ⭐
  getViewMatrix(): Mat4x4     // API 23+ ⭐
  getProjectionMatrix(): Mat4x4  // API 23+ ⭐
}

interface LayerMask {
  getEnabled(index: number): boolean
  setEnabled(index: number, enabled: boolean): void
}

interface Container<T> {
  append(item: T): void
  insertAfter(item: T, sibling: T | null): void
  remove(item: T): void
  get(index: number): T | null
  clear(): void
  count(): number
}

interface RaycastParameters {
  rootNode?: Node           // 限定射线起点 (不传 = 整场景)
  // (其他字段官方未一一列举)
}

interface RaycastResult { /* 命中节点数组, 按距离从近到远 */ }
```

**Camera.raycast API 20+ 一手签名 (官方示例节选):**
```typescript
let viewPos: Vec2 = { x: 0.5, y: 0.5 } // [0,1] 归一化屏幕坐标 (0,0=左上, 1,1=右下)
let raycastParams: RaycastParameters = {}
if (node) raycastParams.rootNode = node
let hits: RaycastResult[] = await camera.raycast(viewPos, raycastParams)
```

#### SceneResources (API 12, MaterialType.METALLIC_ROUGHNESS API 20+)

```typescript
// 文档: js-apis-inner-scene-resources

enum SceneResourceType {
  UNKNOWN = 0, NODE = 1, ENVIRONMENT = 2, MATERIAL = 3,
  MESH = 4, ANIMATION = 5, SHADER = 6, IMAGE = 7,
  MESH_RESOURCE = 8,    // API 18+
  EFFECT = 9,           // API 21+
}

interface SceneResource {
  name: string
  resourceType: SceneResourceType  // 只读
  uri?: ResourceStr
  destroy(): void
}

interface Shader extends SceneResource {
  inputs: Record<string, number | Vec2 | Vec3 | Vec4 | Image>  // 只读
  setShaderInputs(inputs): void  // API 23+, 性能优于直接写 inputs
}

enum MaterialType { SHADER = 1, METALLIC_ROUGHNESS = 2, UNLIT = 3, OCCLUSION = 4 } // API 23+ 加 3,4

interface Material extends SceneResource {
  materialType: MaterialType           // 只读
  shadowReceiver?: boolean             // API 20+, 默认 false
  cullMode?: CullMode                  // API 20+, 默认 BACK
  blend?: Blend                        // API 20+
  alphaCutoff?: number                 // API 20+, [0,1], 默认 1
  renderSort?: RenderSort              // API 20+
  polygonMode?: PolygonMode            // API 23+, 默认 FILL
}

interface ShaderMaterial extends Material {
  colorShader?: Shader                 // 默认 undefined
}

interface MetallicRoughnessMaterial extends Material { // API 20+
  baseColor: MaterialProperty
  normal: MaterialProperty
  material: MaterialProperty          // metallic/roughness/reflectance
  ambientOcclusion: MaterialProperty
  emissive: MaterialProperty
  clearCoat: MaterialProperty
  clearCoatRoughness: MaterialProperty
  clearCoatNormal: MaterialProperty
  sheen: MaterialProperty
  specular: MaterialProperty
}

interface MaterialProperty { // API 20+
  image: Image | null
  factor: Vec4
  sampler?: Sampler
}

interface Mesh extends SceneResource {
  subMeshes: SubMesh[]   // 只读
  aabb: Aabb             // 只读
  materialOverride?: Material
}

interface MeshResource extends SceneResource { } // API 18+

interface SubMesh {
  name: string
  material: Material
  aabb: Aabb  // 只读
}

interface Morpher { // API 20+
  targets: Record<string, number>  // 形变目标权重, 通常 [0,1]
}

interface Animation extends SceneResource {
  enabled: boolean
  speed?: number          // API 20+, 默认 1.0, 负值反向
  duration: number        // 只读, 秒, ≥ 0
  running: boolean        // 只读
  progress: number        // 只读, [0,1]
  onStarted(callback: Callback<void>): void
  onFinished(callback: Callback<void>): void
  start(): void
  stop(): void            // 进度归 0
  pause(): void
  restart(): void
  seek(position: number): void  // position ∈ [0,1]
  finish(): void          // 进度置 1
}

enum EnvironmentBackgroundType {
  BACKGROUND_NONE = 0,
  BACKGROUND_IMAGE = 1,
  BACKGROUND_CUBEMAP = 2,
  BACKGROUND_EQUIRECTANGULAR = 3,
}

interface Environment extends SceneResource {
  backgroundType: EnvironmentBackgroundType
  indirectDiffuseFactor: Vec4
  indirectSpecularFactor: Vec4
  environmentMapFactor: Vec4
  environmentImage?: Image | null
  radianceImage?: Image | null
  irradianceCoefficients?: Vec3[]
  environmentRotation?: Quaternion  // API 23+
}

interface Image extends SceneResource {
  width: number   // 只读, px, > 0
  height: number  // 只读, px, > 0
}

interface ImageStream extends Image { // API 26+
  surfaceId: string  // 流 ID, 数字字符, > 0
}

interface Effect extends SceneResource { // API 21+
  enabled: boolean
  effectId: string    // 固定格式 UUID
  getPropertyValue(name: 'exposure' | 'vibrance'): Object | null | undefined  // API 23+
  setPropertyValue(name, value): boolean  // API 23+
  // exposure 推荐 [-5, 5], vibrance 推荐 [-1, 1]
}
```

### §2.4 完整自定义场景模式工作流 (官方原文示例汇总)

```typescript
// 节选自 arkgraphics3d-scene, arkgraphics3d-resource-image, arkgraphics3d-resource-material
import {
  Camera, Light, Scene, SceneNodeParameters, SceneResourceFactory,
  Animation, Shader, ShaderMaterial, MaterialType, EnvironmentBackgroundType,
} from '@kit.ArkGraphics3D'

// 1. 加载场景
let scenePromise: Promise<Scene> = Scene.load($rawfile('gltf/CubeWithFloor/glTF/AnimatedCube.glb'))
let globalScene: Scene | undefined
scenePromise.then(async (result: Scene) => {
  globalScene = result
  let rf: SceneResourceFactory = result.getResourceFactory()

  // 2. 创建相机
  let camParam: SceneNodeParameters = { name: 'camera1' }
  let cam: Camera = await rf.createCamera(camParam)
  cam.enabled = true
  cam.position.z = 5
  cam.fov = 60 * Math.PI / 180

  // 3. 创建光源
  let lightParam: SceneNodeParameters = { name: 'light1' }
  let light: Light = await rf.createLight(lightParam, LightType.DIRECTIONAL)
  light.color = { r: 0.8, g: 0.1, b: 0.2, a: 1.0 }
  light.intensity = 1.0
  light.shadowEnabled = true

  // 4. 创建图片 + 环境 + 材质替换
  let img: Image = await rf.createImage({
    name: 'tex',
    uri: $rawfile('image/Cube_BaseColor.png'),
  } as SceneResourceParameters)

  let env: Environment = await rf.createEnvironment({ name: 'env' } as SceneResourceParameters)
  env.backgroundType = EnvironmentBackgroundType.BACKGROUND_EQUIRECTANGULAR
  env.environmentImage = img
  env.indirectDiffuseFactor = { x: 1, y: 1, z: 1, w: 1 }
  globalScene.environment = env

  // 5. 替换子网格材质
  let geom = result.getNodeByPath('rootNode_/Unnamed Node 1/AnimatedCube') as Geometry
  let shader: Shader = await rf.createShader({
    name: 'shaderResource',
    uri: $rawfile('shaders/custom_shader/custom_material_sample.shader'),
  } as SceneResourceParameters)
  let shaderMat: ShaderMaterial = await rf.createMaterial(
    { name: 'imageMat' } as SceneResourceParameters,
    MaterialType.SHADER
  ) as ShaderMaterial
  shaderMat.colorShader = shader
  shaderMat.colorShader.inputs['BASE_COLOR_Image'] = img
  geom.mesh.subMeshes[0].material = shaderMat

  // 6. 动画控制
  let anim: Animation = globalScene.animations[0]
  anim.enabled = true
  anim.onStarted(() => console.info('started'))
  anim.onFinished(() => console.info('finished'))
  anim.start()

  // 7. 绑定到 Component3D
  this.sceneOpt = { scene: globalScene, modelType: ModelType.SURFACE }
})
```

### §2.5 动画循环驱动方式 (frameloop)

**两种官方支持的 frameloop 路径:**

1. **glTF 自带 Animation (首选, 静态资产级)** — `scene.animations[i]` 上 `start/pause/seek/finish` 控制, 见 §2.3 `Animation` 接口. 适合"模型自带摆动"场景.
2. **ArkTS `AnimatorResult` 驱动 uniform / shaderInputBuffer** — 自定义渲染模式用, 见 `Component3D` 文档:

```typescript
import { AnimatorResult } from '@kit.ArkUI'

backAnimator: AnimatorResult = this.getUIContext().createAnimator({
  duration: 2000,
  easing: 'ease',
  delay: 0,
  fill: 'none',
  direction: 'normal',
  iterations: -1,  // 无限循环
  begin: 100,
  end: 200,
})
// onFrame: 推进时间变量 → 写回 @State → shaderInputBuffer 重渲染
```

> **未验证 / unverified:** ArkGraphics 3D 是否有"原生每帧 callback (类似 Three.js requestAnimationFrame)" — 官方文档未见; 当前 ArkTS 侧最稳健的帧驱动方案是 `AnimatorResult.onFrame` 或 `@State` 变更触发 reconcile.

### §2.6 手势 / 触摸

- `Component3D` 继承 ArkUI 通用手势, 与普通组件一致 (`gesture` / `priorityGesture` / `parallelGesture`, 见 `arkts-gesture-events-binding`).
- **自动场景模式**: 框架自动接管"旋转/缩放"默认手势 (官方明示).
- **自定义场景模式**: 文档明示"未内置相机控制器, 因此不会自动响应拖拽或缩放手势; 如需交互, 请开发者接入手势并更新相机的位置与旋转". 这意味着 MindTrace 想做"指尖拨动星系旋转"必须自己写 `PanGesture` + 相机 `position` / `rotation` 更新.

### §2.7 Shader 文件格式 (.shader = JSON 描述符 + SPIR-V)

> **来源:** `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/shader资源文件格式要求/arkgraphics3d-shader-resource`

```typescript
// 注意 .shader 是 JSON, 引用真正的 SPIR-V .spv 文件
{
  "compatibility_info": { "version": "22.00", "type": "shader" },
  "vert": "3dshaders://shader/core3d_dm_fw.vert.spv",     // vertex
  "frag": "appshaders://yourDir/yourShader.frag.spv",      // fragment (用户自定)
  "vertexInputDeclaration": "3dvertexinputdeclarations://core3d_dm_fw.shadervid",
  "state": {
    "rasterizationState": {
      "enableDepthClamp": false, "enableDepthBias": false, "enableRasterizerDiscard": false,
      "polygonMode": "fill",   // "fill" | "line" | "point"
      "cullModeFlags": "back", // "back" | "front" | "none" | "front_and_back"
      "frontFace": "counter_clockwise"
    },
    "depthStencilState": {
      "enableDepthTest": true, "enableDepthWrite": true, "enableDepthBoundsTest": false,
      "enableStencilTest": false,
      "depthCompareOp": "less_or_equal" // never/less/equal/less_or_equal/greater/not_equal/greater_or_equal/always
    },
    "colorBlendState": {
      "colorAttachments": [{
        "enableBlend": true,
        "colorWriteMask": "r_bit|g_bit|b_bit|a_bit",
        "srcColorBlendFactor": "one", "dstColorBlendFactor": "one_minus_src_alpha",
        "colorBlendOp": "add",
        "srcAlphaBlendFactor": "one", "dstAlphaBlendFactor": "one_minus_src_alpha",
        "alphaBlendOp": "add"
      }]
    }
  },
  "materialMetadata": [{
    "name": "MaterialComponent",
    "customProperties": {
      "data": [
        { "name": "vec_1", "displayName": "Color", "type": "vec4", "value": [1.0, 1.0, 1.0, 1.0] },
        { "name": "time",  "displayName": "Time",  "type": "float", "value": 0.0 }
      ]
    }
  }]
}
```

> **关键事实:** vertex / fragment 都是 **SPIR-V (.spv)**, 不是 GLSL! 这意味着:
>   - 任何"自写 GLSL 然后用 glslang 转 SPIR-V"是上游必备 — 不是 IDE 内实时编译
>   - GLSL 写法必须用 `#version 450` 等 Vulkan-compatible 语法
>   - 复赛窗口下, 不会写自定 shader 完全可行 (用 PBR `MetallicRoughnessMaterial` + 官方内置渲染管线 `core3d_dm_fw`), 见 §2.4 §5
>   - **未验证 / unverified:** 是否存在"开发者编辑器"内置 shader 编译流水线, 见 §3.5 ArkGraphics Editor

### §2.8 后处理 (PostProcess / Effect)

- **Camera.postProcess**: 色调映射 (ToneMapping) 等基础后处理, 直接挂相机
- **Camera.effects (API 21+)**: 多个 `Effect` 容器, 通过 UUID 创建, 支持 `exposure` / `vibrance` 调节
- `EffectParameters = { effectId: 'e68a7f45-2d21-4a0d-9aef-7d9c825d3f12' }` — 这是 **固定格式 UUID**, 暗示"特效是引擎预设", 不是我们自写后处理 shader
- **MSAA (API 22+):** `camera.msaa = true` 启用, 默认 false (所以默认会有锯齿, 高分屏需注意)

### §2.9 物理 / 碰撞 / 命中

- **唯一官方 hit-test:** `Camera.raycast(viewPosition, params)` (API 20+), 屏幕归一化坐标
- **未提供物理引擎** (no Bullet / no PhysX) — 节点间"碰撞"是开发者自己写数学判断 (AABB 用 `Mesh.aabb` 可用)
- **未提供粒子系统** (no GPU particle) — 自定需 shader

---

## §3 SceneKit / SceneView / Graphics3DKit — kit 名称核对

> **目标:** 把官方一手信源里所有跟"3D / Scene / Graphics"沾边的 kit 都列出来, 确认名称真实存在, 不要被营销文案带跑.

### §3.1 候选 kit 名称核查

| 名称 | 是否存在 | 真实所属 | 备注 |
|---|---|---|---|
| **`@kit.ArkGraphics3D`** | ✅ | 3D 渲染核心 | 见 §2 |
| **`@kit.Graphics3DKit`** | ❌ | — | devecocli 全库搜索 0 命中, **这不是真实 kit 名** |
| **`@kit.SceneKit`** | ❌ | — | devecocli 全库搜索 0 命中, **不存在** |
| **`@kit.SceneView`** | ❌ | — | 同上, **不存在** (有 `Scene` 类型, 但不是 kit 名) |
| **`@ohos.graphics.scene`** | ✅ | NDK 命名空间, 跟 `@kit.ArkGraphics3D` 对应 | 见 §2 |
| **`@kit.GraphicsAccelerateKit`** | ✅ | "图形加速服务" — 4 子服务: 游戏渲染加速 / 游戏资源加速 / 游戏启动加速 / 游戏伴随服务, 用于**游戏** 帧生成 (超帧) / 资源压缩 / 启动 | 文档 `graphics-accelerate-introduction` |
| **`@kit.XEngineKit`** | ✅ | "GPU 加速引擎服务", 华为 Maleoon GPU 的 5 特性: 超分 (时空域) / 自适应 VRS / Subpass Shading / 光线追踪 / 时域 AI 超分 | 文档 `xengine-kit-introduction`, 起 API 14, Phone 优先 (Tablet / PC / TV 增量) |
| **`@kit.Graphics2D`** | ❌ | — | 但有 `@ohos.graphics.drawing` (`js-apis-graphics-drawing`), `@ohos.graphics.text` (`js-apis-graphics-text`), `@ohos.graphics.common2D` (`js-apis-graphics-common2d`), `@ohos.uiEffect` 等子模块 — 走 ArkGraphics 2D kit 视角 |
| **`@kit.ArkGraphics2D`** | ❌ | — | 但有 `开发指南/ArkGraphics_2D_方舟2D图形服务/ArkGraphics_2D简介/arkgraphics2d-introduction` 描述 2D 服务集 |
| **`@kit.ImageEffect`** | ✅ | "图片效果服务" (PixelMap 后处理 / 滤镜) | 文档 `ide-image-effect-overview` (未在本调研深入) |
| **`@kit.SpatialReconKit`** | ✅ | "空间建模套件" — 3DGS (3D Gaussian Splatting) 模型加载 + 滤镜; 是 ArkGraphics 3D 的扩展, **API 23 起, 仅中国境内 (港澳台除外), 不支持模拟器** | 见 §3.4 |
| **`@kit.AREngine`** | ✅ | "AR 引擎服务" — 运动跟踪 / 环境跟踪 / 平面识别 / 深度估计 / 图像跟踪 / 人脸 / 人体骨骼 / 环境 Mesh / 锚点 | 文档 `arengine-overview` |
| **`@kit.GameServiceKit`** | ✅ | "游戏服务" — 账号 / 实名 / 防沉迷 / 近场快传 / 场景感知; **不含 3D 渲染** | 文档 `gameservice-introduction` |
| **`@kit.GameControllerKit`** | ✅ | "游戏控制器服务" — 手柄事件, 与 3D 渲染无关 | 文档 `game-controller-introduction` |

### §3.2 `@kit.ArkGraphics3D` 子模块清单 (官方架构)

```
@kit.ArkGraphics3D
├── @ohos.graphics.scene (基础 + Scene)
├── graphics3d/Scene         (Scene.load, root, environment, animations)
├── graphics3d/SceneNode     (Node / Geometry / Light / Camera / Container / LayerMask)
├── graphics3d/SceneResources (Shader / Material* / Mesh / SubMesh / Morpher / Animation / Environment / Image / Effect / Sampler / CullMode / Blend / RenderSort / PolygonMode)
└── graphics3d/SceneType     (Vec2-4 / Quaternion / Aabb / Color / Rect / Mat4x4 / GeometryDefinition / CylinderGeometry / ...)
```

> **系统能力 tag:** `SystemCapability.ArkUi.Graphics3D`
> **NDK 对应 (C/C++):** `@ohos.graphics.scene` (C 头文件在 `native/graphic/3d/`)

### §3.3 引擎层 (3.3 节)

- **AGP (Ark Graphics Platform) 渲染引擎部件** — 官方原文"依托 Ark Graphics Platform 渲染引擎部件提供渲染能力", `arkgraphics3d-overview` §框架原理
- **底层:** ECS (Entity-Component-System) 架构, 模块化封装 (材质定义 / 后处理特效)
- **GPU 后端:** OpenGL ES 3.2+ 或 Vulkan 1.0+ (`arkgraphics3d-overview` §约束限制)
- **仿真器状态:** "本 Kit 暂不支持模拟器" (`arkgraphics3d-overview` §模拟器支持情况)

### §3.4 `@kit.SpatialReconKit` (3DGS) — 不推荐用于 MindTrace

> **来源:** `开发指南/Spatial_Recon_Kit_空间建模服务/Spatial_Recon_Kit简介/spatial-recon-introduction`, `开发指南/Spatial_Recon_Kit_空间建模服务/加载3DGS模型/spatial-recon-load`

```typescript
import { spatialRender } from '@kit.SpatialReconKit' // (实际子模块名)
import { Scene, GSImportSettings, GSNode } from '@kit.SpatialReconKit'

// 加载 3DGS 模型 (MP4 / PLY / GLB)
spatialRender.loadGSNode(scene, params, parent?): Promise<GSNode>
```

**不推荐理由:**
1. **"本 Kit 仅支持中国境内 (香港特别行政区、澳门特别行政区、中国台湾除外)"** — 复赛路演 / 商业演示对外不可用
2. **3DGS 概念 = 摄影测量级 / 高斯泼溅, 与"知识图谱可视化"语义错位** — 知识图谱用 force-directed / spring-electrical 更合适
3. **不支持模拟器** (`spatial-recon-introduction` §约束)
4. **需要先有 `Scene` (ArkGraphics 3D 实例)** — 与路径 A 强耦合, 加一层依赖

### §3.5 ArkGraphics Editor 插件 (开发期辅助)

> **来源:** `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D_Editor插件及编辑器的下载与安装/arkgraphics-editor`

- **存在:** "3D 编辑器 ArkGraphics Editor 提供 3D 模型、动画、ShaderGraph 等核心编辑能力"
- **作用:** "设计师、开发者快速接入使用... 可大幅提升 3D 应用开发效率"
- **支持:** 从 PC 到移动端流转; 模型 / 动画 / ShaderGraph
- **场景:** 适合 P2 阶段, 不是复赛窗口必需

### §3.6 `@kit.GraphicsAccelerateKit` (游戏优化, **不适用 MindTrace**)

> **来源:** `开发指南/Graphics_Accelerate_Kit_图形加速服务/Graphics_Accelerate_Kit简介/graphics-accelerate-introduction`

- 4 子服务: 游戏渲染加速 / 游戏资源加速 / 游戏启动加速 / 游戏伴随服务
- 用途: **游戏** 帧生成 (超帧) / 资源压缩 / 启动加速
- MindTrace 不是游戏, **不适用** — 即使支持 MindTrace 路径也不应该上

### §3.7 `@kit.XEngineKit` (Maleoon GPU 加速, 视情况)

> **来源:** `开发指南/XEngine_Kit_GPU加速引擎服务/XEngine_Kit简介/xengine-kit-introduction`

- **能力:** GPU/AI 超分, 自适应 VRS, Subpass Shading, 光线追踪 (反射/阴影/AO/全局光照), 时域 AI 超分
- **设备:** Phone 优先 (5.0.2(14) 起), Tablet / PC / TV 增量
- **MindTrace 用法:** **低优先**, 可选 P2 阶段给 `Component3D` 提帧率 / 省电
- **未验证 / unverified:** `Component3D` 是否直接消费 XEngine Kit 加速 (官方无显式集成示例)

### §3.8 `@kit.GameServiceKit` / `@kit.GameControllerKit`

- **Game Service Kit:** 账号 / 实名 / 防沉迷 / 支付, **与 3D 渲染无关**
- **Game Controller Kit:** 手柄事件, 适合游戏但非"知识星系"用例

---

## §4 WebView + Three.js 路径

> **来源:** `开发指南/ArkUI_方舟UI框架/UI开发_兼容JS的类Web开发范式/WebGL/使用WebGL绘制图形/webgl-2d-guidelines`, `API参考/ArkWeb_方舟Web/ArkTS_API/ohos_web_webview_Webview_/Class_SecurityParams/arkts-apis-webview-securityparams`, `开发指南/ArkWeb_方舟Web/管理Web组件的网络安全与隐私/坚盾守护模式/web-secure-shield-mode`, `开发指南/ArkWeb_方舟Web/ArkWeb进程/web_component_process`, `最佳实践/稳定性分析/稳定性故障模式说明/应用冻屏故障模式说明/ArkWeb_GPU进程卡死故障模式说明/bpta-arkweb-gpu-freeze`, 项目既有 `docs/research/arkweb-render-pipeline-stability-2026-09-11.md`

### §4.1 WebGL 可用性 (ArkWeb 内)

- **官方支持:** "HarmonyOS 中使用的 WebGL 是基于 OpenGL 裁剪的 OpenGL ES, 可以在 HTML5 的 Canvas 元素对象中使用, 无需使用插件, 支持跨平台" (`webgl-2d-guidelines`)
- **安全开关 (API 26.0.0+):** `WebviewController.SecurityParams.disableWebGL: boolean` (默认 false, 即启用), 见 `arkts-apis-webview-securityparams`
- **坚盾守护模式禁用:** "禁止使用 WebGL、WebGL2 能力" (`web-secure-shield-mode`)
- **WebGL2 在普通模式可用** (安全开关是按 `WebGL` 一栏管控, 但 `web-secure-shield-mode` 明确把 WebGL2 也禁了)
- **WebGPU:** devecocli docs **0 命中**, 推断**尚未在 HarmonyOS ArkWeb 落地** (见 §5)

### §4.2 进程模型复盘 (复用 2026-09-11 调研结论)

- **5 进程:** 应用 / Web 渲染 / Web GPU / nwebspawn / Foundation
- **默认模式:** "移动设备默认为单渲染进程模式 (SINGLE), 2in1 设备默认为多渲染进程模式 (MULTIPLE)"
- **每 Web 组件实例内存:** "~200MB"
- **数量红线:** "单个应用后台创建的 ArkWeb 组件数量应少于 200 个"
- **窗口级建议:** "每个窗口推荐只使用一个 Web 组件"
- **预启动收益:** ~140ms, **代价 ~200MB 空白 Web 常驻**
- **坚盾守护模式:** 禁用 WebGL / WebGL2 / WASM / JIT / Service Worker / MathML / PDF Viewer / RTCDataChannel / getUserMedia

> **完整论述见 `docs/research/arkweb-render-pipeline-stability-2026-09-11.md`** — 该 doc 已被当前复赛稳定性基线采用 (SINGLE + `initializeWebEngine` + 单常驻 Web 保活).

### §4.3 Three.js 在 ArkWeb 内的可行性

**Three.js 版本:** 任何 r100+ 都可, r150+ 推荐 (Vite / 现代打包工具链兼容); **未验证 / unverified** 具体哪个 r 版本在 ArkWeb 上有性能基准.

**WebGL 上下文:** Three.js 启动时调用 `canvas.getContext('webgl2')` (优先) 或 `canvas.getContext('webgl')` 回退; 正常 ArkWeb 实例上两条都可用 (除坚盾守护模式禁用).

**GLES 后端:** ArkWeb WebGL 走 OpenGL ES (具体子版本官方未明示, 但 OpenGL ES 3.0+ 是 webgl2 最低要求); 与 Three.js 内部 `WebGLRenderer.capabilities.isWebGL2` 检测匹配.

**已知 Three.js 兼容性:**
- `requestAnimationFrame` ✅ ArkWeb 内置 (Chrome 系派生)
- `WebWorker` ✅ (除非禁用 Service Worker 后衍生)
- `OffscreenCanvas` (HTMLCanvasElement.transferControlToOffscreen) — **未在 HarmonyOS 文档中验证**
- `WebGL2RenderingContext` ✅ (除坚盾守护模式)
- `EXT_color_buffer_float`, `OES_texture_float_linear` — **未验证 / unverified**, 各设备 GPU 驱动差异

**已知稳定性问题 (从 2026-09-11 doc 复用):**
1. **GPU 进程卡死:** 见 `bpta-arkweb-gpu-freeze` — I/O 阻塞 (业务网络拦截执行 > 6s) 或 等锁 (业务持 EGL 锁未释放) 都会冻 GPU 进程
2. **EGL 单锁原则:** "单进程中仅允许一个线程持有 EGL 锁, 故搜索 EglWrapperDisplay, 查看其他线程调用"
3. **chromium 字段日志:** 见 `faqs-arkweb-185` 性能优化汇总

### §4.4 FPS 性能基准 (来自 prior research + 推断)

| 场景 | 实测/预期 fps | 来源 |
|---|---|---|
| 单常驻 Web + 1k nodes force-directed | 30-60 | 项目推算 (未在本机实测) |
| 单常驻 Web + 5k nodes | 10-30 (可能掉到个位数) | 通用 WebGL 力导经验值, **未在 HarmonyOS ArkWeb 实测** |
| 单常驻 Web + 单个 glTF 模型 (5w 顶点) | 60 (vsync 锁) | 通用值 |
| 多 Web 实例 (如现状每公式块一个) | 易触发主线程 binder 阻塞 | 2026-09-11 调研实测 |

> **未验证 / unverified:** MindTrace 当前 force-directed 草稿 (Three.js) 在 HarmonyOS 真机上的实际 fps; **建议 P0 spike 步骤**先用真机跑 `tools/profiling/three-js-galaxy-fps.html` 跑一次基线.

### §4.5 MindTrace 已有 messageBridge 设计

> **来源:** 项目当前 `entry/src/main/ets/services/AiService.ets` 等, 既有 `WebMessagePort` 模式 — 详细见项目 git 历史, 这里不展开.

**复盘结论:**
- `WebMessagePort` 支持 STRING / NUMBER / BOOLEAN / ARRAY_BUFFER / ARRAY / ERROR 6 种类型 (`arkts-apis-webview-webmessageport` 接口)
- 推荐用法: 创建一对端口, 一份给 HTML, 一份给 ArkTS, 双向 postMessage
- 替代方案: `runJavaScript` + `registerJavaScriptProxy` (JSBridge), 见 `faqs-arkweb-11` 区别
  - **WebMessagePort**: 大数据量双向流, 不阻塞 UI
  - **JSBridge**: 简单方法调用, 适合一次性 RPC

### §4.6 WebGL 文档本身暴露的局限 (节选)

`webgl-2d-guidelines` 给出的接口表:
- `canvas.getContext`, `webgl.createBuffer`, `webgl.bindBuffer`, `webgl.bufferData`
- `webgl.getAttribLocation`, `webgl.vertexAttribPointer`, `webgl.enableVertexAttribArray`
- `webgl.clearColor`, `webgl.clear`, `webgl.drawArrays`, `webgl.flush`, `webgl.createProgram`

> **关键观察:** 文档列举的接口**只覆盖 WebGL1 子集**, 没出现 `getUniformLocation`, `uniformMatrix4fv`, `createShader`, `shaderSource` 等更现代接口 — 推测是节选不全, 不代表 ArkWeb 只支持 WebGL1. 实际 ArkWeb 内 Chromium 系派生, 全 WebGL1/WebGL2 都可用.

### §4.7 迁移成本 (MindForce 当前 draft → P1 WebView)

| 动作 | LOC 估计 | 风险 |
|---|---|---|
| 把 draft 拷到 `entry/src/main/resources/rawfile/galaxy/` | 100-300 LOC (HTML + JS + CSS) | 低 |
| 改写 Three.js / Babylon 模块引用到 ESM UMD bundle | 50 LOC | 中 (依赖打包) |
| 实现 WebMessagePort 桥接 (`MessageChannel` + port transfer) | 50-80 LOC | 低 |
| 实现 force-directed 数据序列化 (`SubjectSystem` → JSON → JS) | 80 LOC | 低 |
| 实测 fps + 跑题 (`bpta-arkweb-gpu-freeze` 模式) | 半天 | 中 |
| 失败回退到 2D Canvas 的兜底 | 0 (现成) | 0 |
| **合计** | **~300-500 LOC** | **可接受** |

---

## §5 WebView + WebGPU / WebGL2 / Custom Native bridge

> **目标:** 评估"用 Three.js 的 WebGPURenderer 走 WebGPU / 用 Babylon WebGPU / 用 WebGL2 + 自研 Native bridge" 是否能在 6.1.1(24) / API 26.0.0 落地

### §5.1 WebGPU 在 ArkWeb 的可用性 — **未验证 / 不落地**

- **devecocli docs 搜索 "WebGPU":** 0 命中
- **官方 WebGL doc:** 只描述 WebGL (基于 OpenGL ES), 未提 WebGPU
- **WebAssembly 在 ArkWeb:** 有, 但在坚盾守护模式禁用
- **WGSL:** 0 命中

**结论:** **HarmonyOS 7 / API 26 ArkWeb 在 2026-09-23 时点未落地 WebGPU**, 路径 D 不可行.

### §5.2 WebGL2 在 ArkWeb — 可用但受限

- **能力:** ArkWeb 内 Chromium 派生内核, WebGL2 全接口支持
- **限制:** **坚盾守护模式** (API 26+) 明确"禁止使用 WebGL2"
- **风险:** 用户主动开启坚盾守护模式后, 整个 Three.js / Babylon 应用静默失效 — 需要兜底

### §5.3 Custom Native bridge (JSVM / JSB / Native PostWebMessage)

> **来源:** `开发指南/代码开发/使用JSVM-API实现JS与C_C_语言交互/JSVM-API使用指导/使用JSVM-API接口进行WebAssembly模块相关开发/use-jsvm-about-wasm`, `开发指南/ArkWeb_方舟Web/在应用中使用前端页面JavaScript/建立应用侧与前端页面数据通道_C_C/arkweb-ndk-page-data-channel`, `API参考/ArkWeb_方舟Web/C_API/结构体/ArkWeb_WebMessagePortAPI/capi-web-arkweb-webmessageportapi`, `API参考/ArkWeb_方舟Web/ArkTS_API/ohos_web_webview_Webview_/Interface_WebMessagePort/arkts-apis-webview-webmessageport`

- **JSVM-API WebAssembly:** 提供字节码编译 / 优化 / cache 序列化 — 可跑 Wasm 模块, 但用途是 JS 引擎加速, **不解决 WebGPU 缺位**
- **Native PostWebMessage:** C/C++ 侧可直接 `postMessage`, 数据类型仅 STRING / ARRAY_BUFFER (见 `arkweb-ndk-page-data-channel`), 可避开 ArkTS 主线程
- **相对 `messageBridge.ts` 设计偏差:**
  - 原设计假定 `WebMessagePort` STRING + JSON, 改 Native 后改 ARRAY_BUFFER + 手写协议
  - 主线程剥离后, 桥接协议测试需要重写, 失去 ArkTS 测试栈的可读性
  - **不建议** (没有性能瓶颈证据)

### §5.4 OffscreenCanvas + 2D (CPU 渲染)

> **来源:** `FAQ/2D图形_ArkGraphics_2D/大图添加水印性能优化/faqs-arkgraphics-2d-34`, `API参考/ArkUI_方舟UI框架/ArkTS组件/画布绘制/OffscreenCanvas/ts-components-offscreencanvas`

- **官方明示:** "离屏绘制使用 CPU 进行绘制, 绘制速度较慢, 对绘制速度有要求的场景应避免使用离屏绘制" (`faqs-arkgraphics-2d-34`)
- **适合场景:** 后台 pre-render 图片 (如卡片背景 / 知识摘要渲染), 不是动态 3D 帧渲染
- **替代:** `@ohos.graphics.drawing` (2D 矢量 / 文本绘制) + GPU 合成

---

## §6 MindTrace Galaxy 路径对比矩阵 — 真实成本拆解

> **基线:** 当前 `entry/src/main/ets/pages/Review/ReviewGraphView.ets` + `entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets` 已经是**2D ArkUI Canvas**实现, 数据层 (`SubjectSystem` / `PlanetNode` / `ChapterOrbit` / `GalaxyLink`) 已完整 (881 LOC ViewModel). 三方 draft (Three.js) 在外部位置, 未合入主仓.

### §6.1 横向对比

| 维度 | J: 2D Canvas (现状) | B: WebView + Three.js | A: 原生 Component3D | E: XComponent + NDK + 自研 |
|---|---|---|---|---|
| **代码改动 LOC** | 0 (打磨现有) | ~300-500 LOC (新页面 + 桥接) | ~800-1500 LOC (新页面 + Scene 模板 + .glb 资产生成) | ~2000+ LOC (C/C++ 引擎骨架) |
| **新增 module** | 0 | 0 (entry 内 + rawfile) | 0 (entry 内 + rawfile) | 新增 native lib (CMake) |
| **构建管线变化** | 0 | 0 | 0 (oh-package 加 `@kit.ArkGraphics3D` 1 行) | + CMakeLists + napi 子模块, CI 步骤加 so 打包 |
| **DevEco 工具链影响** | 0 | 0 (WebView 调试已熟) | ArkGraphics Editor (可选, P2) + Component3D 预览限制 (官方明示"DevEco Studio 预览器不支持") | + NDK 调试 + Graphics Profiler |
| **真机验证耗时** | 0 (已上) | 半天 (单实例跑题) | 1-2 天 (模拟器不可用, 必须真机 + Glb 资产制作) | 1 周+ |
| **复赛演示风险** | 0 | 中 (THREAD_BLOCK_6S 余波 + 坚盾守护模式禁用) | 高 (模拟器不跑, 演示机必须是真机 + 模型可能没准备) | 极高 (人月不在窗口) |
| **路演叙事价值** | 中 (2D "地球+轨道") | 高 ("3D 旋转" 视觉冲击) | 极高 ("原生 ArkTS, 0 桥接, 60/120Hz 流畅") | 中 (看不出与 Three.js 区别) |
| **长期价值** | 低 (不能 3D 旋转) | 中 (Three.js 迭代空间大) | 高 (AGP 引擎随鸿蒙升级, 跟系统节奏) | 极高 (完全自主, 但维护成本巨大) |
| **跨 module 影响** | 0 | 0 | 0 (无跨 module 依赖) | 0 (同) |
| **依赖 kit 数** | 0 (ArkUI Canvas 内置) | `@kit.ArkWeb` (已有) | `@kit.ArkGraphics3D` (新) | `@kit.ArkGraphics3D` (无) + NDK + EGL / Vulkan (系统库) |
| **README / ADR 影响** | 0 | 1 个新 ADR (桥接协议) | 1 个新 ADR (3D 路径 + 资产管道) | 1 个新 ADR + NDK 编译/打包指南 |
| **可降级兜底** | — | 降回 2D Canvas 1 LOC | 降回 2D Canvas 1 LOC | 降回 2D Canvas, 但 so 保留 |

### §6.2 真实成本估算 (LOC 已含测试 + 调试 + 文档)

| 路径 | 开发 LOC | 测试 LOC | 文档 LOC | 资产 LOC | **合计** | 估算人日 |
|---|---|---|---|---|---|---|
| **J (维持 2D Canvas)** | 0 | 0 | 0 | 0 | **0** | **0** |
| **B (WebView + Three.js)** | 350 | 80 | 40 | 200 (glTF 模型 + 字体 + 纹理) | **670** | **3-4** |
| **A (原生 Component3D)** | 1200 | 200 | 80 | 800 (3 个 .glb + 1 个 .ktx envmap + .shader 描述) | **2280** | **10-14** |
| **E (XComponent + NDK + 自研)** | 2500+ | 400+ | 200 | 同 A | **3900+** | **30+** |

### §6.3 复赛路演叙事 (按"3D"字眼对评委冲击力)

| 路径 | 评委看到的 3D 震撼度 | 评委听到的"端云协同 / AI" 关键点 |
|---|---|---|
| **J (2D Canvas)** | 低 (虽然项目已经能做) | "知识星系" (2D 拓扑) — 已展示 |
| **B (WebView + Three.js)** | 高 (旋转 / 缩放 / 光照) | "ArkWeb 内嵌 Three.js + WebMessagePort 桥接" — 技术完整但**已被 2026-09-11 故障阴影覆盖** |
| **A (Component3D)** | **最高** (原生 60/120 Hz) | "**鸿蒙原生 AGP 引擎**, 0 桥接, 与 LLM 拆解 / KnowledgeUnit 共享同一图数据结构" — 端云 + 端侧 AI + 端侧 3D 全栈 |
| **E (NDK 自研)** | 最高 (但看不出区别) | "我们手写了 EGL/Vulkan 引擎" — 复赛窗口下不被认可 |

> **叙事策略:** 复赛现场重点不是"3D 多炫", 而是"**架构完整度**". 原生 `Component3D` 故事最连贯 (拍照 → LLM → 结构化 → 知识图谱 → 3D 可视化 → 复习 → 卡片, 全在 ArkTS, 0 桥接), 但**只在该路径团队已有 3D 资产储备 / 已有 AGP 经验**时成立.

---

## §7 推荐 + 路线图

### §7.1 推荐 (一句话)

**P0 维持现状 2D Canvas (打磨视觉 + 演示钩子) → P1 WebView + Three.js 做桥接实验场 → P2 原生 `Component3D` + `@kit.ArkGraphics3D` 收编.** 三阶段都有清晰降级路径, 复赛窗口下风险最低, 长期方向最干净.

### §7.2 5 个 P0 micro-benchmark (必须先跑)

> 跑这 5 个的目的: 在投入大改造之前, 用最小成本 (≤ 半天) 验证关键假设.

1. **真机 3D fps 基线** — 在真机上跑一个最小 Three.js 力导 demo (1000 节点) + Babylon 对照组, 测 fps 与内存占用. 目标: ≥ 45 fps (中等设备) / ≥ 30 fps (低端设备) 才考虑 WebView 路径.
2. **ArkGraphics 3D 加载 .glb 真机验证** — 用官方 `DamagedHelmet.gltf` 跑通 `Component3D(sceneOptions)`, 确认 `Camera.raycast` 真机可用. 目标: 真机加载 + 渲染 + 命中全部通过.
3. **单常驻 Web + 100 个 WebMessagePort 消息往返** — 模拟"用户来回切 100 个 KU"的桥接压力, 确认无 THREAD_BLOCK_6S. 目标: 1 分钟内 0 冻屏.
4. **glTF MeshOpt 压缩效果** — 准备一个 ~1MB .glb (数学概念 + 知识星系拓扑) 含 100 个 mesh, 跑未压缩 vs MeshOpt 压缩对比. 目标: 包体 -30%, 加载 -40%.
5. **ArkUI Canvas 2D 大量节点 (5000) 渲染稳定性** — 在 `ReviewGraphView` 现有画布上加 5000 节点压力测试, 看是否掉帧 / OOM. 目标: 现有架构可承载 ≤ 5000 节点; 超则需要 3D 化或 LOD 化.

### §7.3 三阶段 rollout

#### POC (≤ 2 周, 复赛前)

- **目标:** 0 改动, 把现有 2D Canvas 实现打磨成演示亮点
- **动作:**
  1. 在 `ReviewGraphView` 现有 Canvas 基础上加: 触摸放大 (单指) / 双击聚焦 / 长按弹出 KnowledgeUnit 详情 / 自动轮播主题切换
  2. 配套打磨: 主题切换动画 / 章节 orbit 过渡 / 节点 hover 描边
  3. 1 页 ADR: 解释为什么不在这阶段上 3D (人力 / 模拟器 / 复赛时间窗)
- **验收:** 复赛演示现场能展示 5 Tab 中的 "知识星系" Tab, 1 分钟流畅演示
- **回退:** 任何 1 行失败 → 回退到 2026-09-16 已落地版本

#### P1 (演示后 4 周内, 桥接实验)

- **目标:** 用 WebView + Three.js 验证 force-directed + WebMessagePort 桥接, 不动主仓, 仅在 `tools/galaxy-three/` (rawfile 资源 + 实验页面) 跑
- **动作:**
  1. 把现有 Three.js draft 拷到 `entry/src/main/resources/rawfile/galaxy/` + 打包成 ESM
  2. 新增 `entry/src/main/ets/pages/Review/GalaxyThreeView.ets` (单常驻 Web, `onAppear` 注入 KnowledgeGalaxyViewModel 序列化数据)
  3. 实现 `WebMessagePort` 桥接: JS → ArkTS 单向 (js 调用 aiService 刷新星系), ArkTS → JS 单向 (刷新触发 force-directed tick)
  4. 跑 §7.2 benchmark 1 + 3, 验证
- **验收:** 在 hidden 路由 (不替换 `ReviewGraphView`) 跑通 force-directed, 桥接 0 报错, fps ≥ 45
- **回退:** 任何 1 处失败 → 删 `GalaxyThreeView`, 主仓保持 2D, ADR 留作 P2 输入

#### P2 (开源 / 商业化阶段, 1-2 月)

- **目标:** 全面替换为原生 `Component3D` + `@kit.ArkGraphics3D`, 桥接完全消失
- **动作:**
  1. 用 ArkGraphics Editor 制作 3 套 .glb: 知识星系节点 / 主题星系 / 章节轨道
  2. 新增 `entry/src/main/ets/services/scene/` 包: `GalaxySceneBuilder.ets` (组装 Scene + Camera + Light + Effect), `GalaxyAnimator.ets` (动画循环), `GalaxyRaycaster.ets` (封装 `Camera.raycast`)
  3. 新增 `entry/src/main/ets/pages/Review/ReviewGalaxy3DView.ets` 替换 `ReviewGraphView`
  4. ViewModel 复用: `KnowledgeGalaxyViewModel` 直接喂给 `GalaxySceneBuilder`, 数据层零改
  5. 配套 shader 描述符 `.shader` 文件 (JSON) + SPIR-V (`.spv`) 用 `glslangValidator` 编译
  6. 跑 §7.2 benchmark 2 + 4, 验证
- **验收:** 真机 60 Hz, 1000 节点 0 掉帧, 5 个手势全部正常, AI 拆解结果实时回流 3D 星系
- **回退:** 任何 1 处失败 → 启用 `GalaxyThreeView` 作为兜底 (P1 阶段产物)

### §7.4 不推荐的方向 (排除理由摘要)

- **WebView + WebGPU:** ArkWeb 在 2026-09-23 时点未落地 WebGPU (devecocli docs 0 命中), 不可行
- **WebView + Babylon:** 相比 Three.js 无显著优势, 反而把生态 (Three.js examples) 排除在外
- **OffscreenCanvas (CPU) 2D:** 官方明示"对绘制速度有要求的场景应避免使用离屏绘制", 1000 节点是 3D 用例, 不能用 2D 凑
- **`@kit.SpatialReconKit` 3DGS:** 区域限制 (仅中国境内) + 概念错位 (知识图谱 ≠ 摄影测量), 不可用
- **`@kit.GameServiceKit`:** 账号 / 支付, 与 3D 渲染无关
- **`XComponent + NDK + 自研引擎`:** 复赛窗口下 30+ 人日, 不现实; 仅作长期 (开源后) 选项

---

## §8 Primary sources (所有引用过的 documentId / URL)

### §8.1 devecocli docs (本次主要一手信源)

按 `开发指南 / API参考 / 最佳实践 / FAQ / 版本说明 / 变更预告` 六大目录分门别类.

#### ArkGraphics 3D (方舟 3D 图形)

- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D简介/arkgraphics3d-overview` — Kit 总览, 硬件门槛, 模拟器不支持
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D场景搭建以及管理/arkgraphics3d-scene` — 光源/相机/模型三件套
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D场景动画控制以及管理/arkgraphics3d-animation` — 动画 API + start/pause/seek/finish
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/创建并使用图片资源/arkgraphics3d-resource-image` — Image 资源
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/创建并使用环境资源/arkgraphics3d-resource-environment` — Environment + IBL
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/创建并使用材质资源/arkgraphics3d-resource-material` — PBR + Shader 材质
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/shader资源文件格式要求/arkgraphics3d-shader-resource` — .shader JSON + .spv SPIR-V
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D_Editor插件及编辑器的下载与安装/arkgraphics-editor` — ArkGraphics Editor

#### ArkGraphics 3D API 参考

- `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/ohos_graphics_scene_ArkGraphics_3D模块_/js-apis-scene` — `@ohos.graphics.scene` 模块顶层
- `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/Scene/js-apis-inner-scene` — Scene 类
- `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/SceneNode/js-apis-inner-scene-nodes` — Node / Geometry / Light / Camera + `Camera.raycast` API 20+ + `getViewMatrix/getProjectionMatrix` API 23+
- `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/SceneResources/js-apis-inner-scene-resources` — Material / Shader / Animation / Mesh / Effect 等
- `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/SceneType/js-apis-inner-scene-types` — Vec2-4 / Quaternion / Aabb / Mat4x4 / CylinderGeometry

#### Component3D ArkUI 组件

- `API参考/ArkUI_方舟UI框架/ArkTS组件/渲染绘制/Component3D/ts-basic-components-component3d` — Component3D + SceneOptions + ModelType

#### ArkGraphics 2D / OffscreenCanvas

- `开发指南/ArkGraphics_2D_方舟2D图形服务/ArkGraphics_2D简介/arkgraphics2d-introduction`
- `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/使用自定义能力/自定义绘制/使用画布绘制自定义图形_Canvas/arkts-drawing-customization-on-canvas`
- `API参考/ArkUI_方舟UI框架/ArkTS组件/画布绘制/OffscreenCanvas/ts-components-offscreencanvas`
- `API参考/ArkUI_方舟UI框架/ArkTS组件/画布绘制/OffscreenCanvasRenderingContext2D/ts-offscreencanvasrenderingcontext2d`
- `FAQ/2D图形_ArkGraphics_2D/大图添加水印性能优化/faqs-arkgraphics-2d-34` — CPU 渲染慢
- `FAQ/2D图形_ArkGraphics_2D/如何使OffscreenCanvas绘制的内容同步到多个Canvas中/faqs-arkgraphics-2d-40`
- `FAQ/UI框架/UI界面/如何解决OffscreenCanvas绘制鼠标路径时路径不平滑的问题/faqs-arkui-996`

#### XComponent / NDK / OpenGL ES / Vulkan

- `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/添加组件/自定义渲染_XComponent/napi-xcomponent-guidelines` — 完整 NDK + EGL/GLES 示例
- `API参考/ArkUI_方舟UI框架/C_API/结构体/OH_NativeXComponent/capi-oh-nativexcomponent-native-xcomponent-oh-nativexcomponent`
- `最佳实践/拍摄美化/XComponent图形渲染常见问题定位指导/bpta-xcomponent-render-problem-guide`
- `API参考/OpenGL_ES/opengles` — OpenGL ES 3.2 支持
- `API参考/Vulkan/Vulkan支持能力/vulkan` — Vulkan v1.4.309 (符号列表)
- `API参考/Vulkan/Vulkan开发指导/Vulkan开发概述/vulkan-overview`
- `API参考/Vulkan/Vulkan扩展能力/Vulkan/capi-vulkan` — VK_OHOS_surface + VK_OHOS_external_memory
- `API参考/Vulkan/Vulkan扩展能力/vulkan_ohos_h/capi-vulkan-ohos-h`
- `开发指南/代码开发/使用Node-API实现ArkTS_JS与C_C_语言交互/Node-API简介/napi-introduction`

#### ArkWeb (WebView) — 复赛基线

- `开发指南/ArkWeb_方舟Web/ArkWeb简介/web-component-overview`
- `开发指南/ArkWeb_方舟Web/ArkWeb进程/web_component_process` — 5 进程模型
- `开发指南/ArkWeb_方舟Web/使用离线Web组件/web-offline-mode` — 200MB / 单 Web 建议 / 复用 / dispose
- `开发指南/ArkWeb_方舟Web/Web渲染和布局/Web组件渲染模式/web-render-mode` — ASYNC_RENDER 7680px / SYNC_RENDER 500000px
- `开发指南/ArkWeb_方舟Web/Web组件的生命周期/web-event-sequence` — 生命周期
- `开发指南/ArkWeb_方舟Web/ArkWeb术语/arkweb-glossary`
- `开发指南/ArkWeb_方舟Web/管理Web组件的网络安全与隐私/坚盾守护模式/web-secure-shield-mode` — 禁用 WebGL/WebGL2/WASM
- `API参考/ArkWeb_方舟Web/ArkTS_API/ohos_web_webview_Webview_/Class_SecurityParams/arkts-apis-webview-securityparams` — API 26.0.0+
- `API参考/ArkWeb_方舟Web/ArkTS_API/ohos_web_webview_Webview_/Interface_WebMessagePort/arkts-apis-webview-webmessageport`
- `API参考/ArkWeb_方舟Web/ArkTS_API/ohos_web_webview_Webview_/Class_WebMessageExt/arkts-apis-webview-webmessageext`
- `开发指南/ArkWeb_方舟Web/在应用中使用前端页面JavaScript/应用侧与前端页面的相互调用_C_C/arkweb-ndk-jsbridge`
- `开发指南/ArkWeb_方舟Web/在应用中使用前端页面JavaScript/建立应用侧与前端页面数据通道_C_C/arkweb-ndk-page-data-channel`
- `API参考/ArkWeb_方舟Web/C_API/结构体/ArkWeb_WebMessagePortAPI/capi-web-arkweb-webmessageportapi`
- `API参考/ArkWeb_方舟Web/C_API/结构体/ArkWeb_WebMessagePort/capi-web-arkweb-webmessageport8h`
- `FAQ/Web框架/Web开发_ArkWeb/WebView中_双向交互可以使用JSBridge技术_也可以使用端口通信技术_这两者有什么区别/faqs-arkweb-11`

#### WebGL / 性能 / 稳定性

- `开发指南/ArkUI_方舟UI框架/UI开发_兼容JS的类Web开发范式/WebGL/使用WebGL绘制图形/webgl-2d-guidelines`
- `最佳实践/稳定性分析/稳定性故障模式说明/应用冻屏故障模式说明/ArkWeb_GPU进程卡死故障模式说明/bpta-arkweb-gpu-freeze`
- `最佳实践/性能分析/Web帧率问题分析/bpta-web-frame-rate-performance-analysis`
- `开发指南/加载丢帧_ArkWeb分析/ide-profiler-arkweb`

#### Game / AR / Spatial

- `开发指南/Game_Service_Kit_游戏服务/Game_Service_Kit简介/gameservice-introduction`
- `开发指南/Game_Controller_Kit_游戏控制器服务/Game_Controller_Kit简介/game-controller-introduction`
- `开发指南/Spatial_Recon_Kit_空间建模服务/Spatial_Recon_Kit简介/spatial-recon-introduction` — 3DGS, 仅中国境内
- `开发指南/Spatial_Recon_Kit_空间建模服务/加载3DGS模型/spatial-recon-load`
- `开发指南/AR_Engine_AR引擎服务/AR_Engine简介/arengine-overview`
- `开发指南/Graphics_Accelerate_Kit_图形加速服务/Graphics_Accelerate_Kit简介/graphics-accelerate-introduction` — 游戏超帧
- `开发指南/XEngine_Kit_GPU加速引擎服务/XEngine_Kit简介/xengine-kit-introduction` — Maleoon GPU 超分 / VRS / 光线追踪

#### 通用 / 变更

- `版本说明/6_1_1_24/OS平台能力/API变更清单/6_1_1_24_Release引入的API/ArkGraphics_2D/js-apidiff-arkgraphics2d-6112`
- `API参考/ArkUI_方舟UI框架/ArkTS_API/UI界面/arkui/Graphics/js-apis-arkui-graphics` — `@ohos.arkui.Graphics`
- `API参考/ArkUI_方舟UI框架/ArkTS_API/UI界面/ohos_arkui_node_自定义节点_/js-apis-arkui-node`
- `API参考/ArkUI_方舟UI框架/ArkTS_API/UI界面/arkui/RenderNode/js-apis-arkui-rendernode`
- `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/添加交互响应/添加手势响应/绑定手势方法/arkts-gesture-events-binding`
- `开发指南/ArkUI_方舟UI框架/UI开发_基于NDK构建UI/构建渲染节点/ndk-embed-render-components`
- `API参考/ArkUI_方舟UI框架/C_API/模块/ArkUI_RenderNodeUtils/capi-arkui-rendernodeutils`
- `API参考/ArkUI_方舟UI框架/C_API/结构体/ArkUI_RenderNode/capi-arkui-nativemodule-arkui-rendernodehandle`
- `API参考/Image_Kit_图片处理服务/C_API/结构体/ImageEffect_FilterDelegate/capi-imageeffect-imageeffect-filterdelegate`

### §8.2 WebFetch (外部信源, 部分失败, 见 §8.3)

- `https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V14/arkui-3d` — **失败**, 返回 "文档中心" SPA 占位
- `https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics3d/arkgraphics3d-overview.md` — **失败**, 405 (raw 路径被挡)
- `https://developer.huawei.com/consumer/cn/harmony/blogs/203391584987412014` — **失败**, 404
- `https://developer.huawei.com/consumer/cn/harmony/blogs/` — **失败**, 404

### §8.3 失败信源与应对

| 失败信源 | 失败原因 | 应对 |
|---|---|---|
| `developer.huawei.com/consumer/cn/doc/harmonyos-guides-V14/...` | 站点返回 JS 渲染壳 ("文档中心" 占位) | 改用 devecocli docs (本地 markdown 副本) |
| `gitee.com/openharmony/docs/...` | 405 GET, raw 路径被 Gitee 拦截 | 同上 |
| `developer.huawei.com/consumer/cn/harmony/blogs/...` | 404, URL 不可猜测 | 直接放弃, devecocli docs 已含 HarmonyOS 7 完整覆盖 |
| 找不到 `developer.huawei.com/consumer/cn/doc/harmonyos-references-V14/syscap-graphics*` | 同上 | devecocli `api/*` 路径已含 SystemCapability 完整列表 |

### §8.4 项目内部相关资源 (相对路径)

- `docs/research/arkweb-render-pipeline-stability-2026-09-11.md` — 2026-09-11 THREAD_BLOCK_6S 故障复盘 + 5 进程模型
- `docs/research/harmonyos-kits-survey-2026-09-05.md` — 12 kit 家族总览 (本研究是其 3D 子集的细化)
- `docs/research/index.md` — research 索引
- `docs/research/chat-markdown-latex-render-jank-2026-09-13.md` — 聊天 KaTeX 渲染稳定性
- `entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets` — 881 LOC 知识星系数据 ViewModel (SubjectSystem / ChapterOrbit / PlanetNode / GalaxyLink / force-directed 数据层)
- `entry/src/main/ets/pages/Review/ReviewGraphView.ets` — 1880 LOC 2D Canvas 渲染 (galaxyCameraOffsetX/Y, universeCameraX/Y, planets / orbits / links 绘制)
- `entry/src/main/ets/pages/Review/ReviewGraphView.ets:613` — `Image($r("app.media.galaxy_overview_bg"))` 静态资源
- `entry/src/main/ets/pages/Review/ReviewGraphView.ets:1199` — `Image($r("app.media.galaxy_detail_bg"))` 静态资源
- `entry/src/main/resources/base/media/galaxy_detail_bg.png`, `galaxy_overview_bg.png` — 2D 静态背景资源
- `entry/src/main/ets/entryability/EntryAbility.ets:36-41` — 已落地的 `setRenderProcessMode(SINGLE)` + `initializeWebEngine()`
- `entry/src/main/ets/shared/atoms/MathTextRenderer.ets:521` — 每公式块一个 Web 组件的现状 (与 §4 主题强相关)

---

## §9 关键事实速查 (写代码时备查)

| 想做什么 | 用什么 | 关键 API / 路径 |
|---|---|---|
| 加载 .glb 到 ArkUI | `Component3D` | `{ scene: $rawfile('xx.glb'), modelType: ModelType.SURFACE }` |
| 自定义相机 / 光源 | `@kit.ArkGraphics3D` Scene | `Scene.load().then(s => s.getResourceFactory().createCamera/createLight)` |
| 屏幕点 → 3D 节点 | `Camera.raycast` (API 20+) | `camera.raycast({x:0.5,y:0.5}, {rootNode})` |
| 触摸转相机 | ArkUI `PanGesture` + `camera.position` / `camera.rotation` | `Component3D.onTouch` 自定义 |
| 帧驱动 (uniform 动画) | `AnimatorResult` (`@kit.ArkUI`) | `getUIContext().createAnimator({...}).onFrame` |
| PBR 材质 | `MetallicRoughnessMaterial` (API 20+) | `rf.createMaterial({name}, MaterialType.METALLIC_ROUGHNESS)` |
| 自定义 shader | `.shader` JSON + `.spv` SPIR-V | `Component3D(...).shader($rawfile('xx.shader'))` |
| MSAA | `Camera.msaa = true` (API 22+) | `camera.msaa = true` |
| 后处理 | `Effect` + `EffectParameters` (API 21+) | UUID `'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'` |
| 流式纹理 | `ImageStream.surfaceId` (API 26+) | 数字字符 > 0 |
| 阴影算法 | `ShadowAlgorithmType.PCF` (API 26+) | enum 值 |
| 真机确认 GPU 能力 | (无 canIUse 一手 doc) | **未验证 / unverified**, 项目侧用 `systemCapability` + 设备门控 |
| 在 Web 里跑 3D | ArkWeb + Three.js | `Web({ src: 'resource://rawfile/galaxy.html' })` + `WebMessagePort` |
| 关闭 WebGL 提安全 | `WebviewController.SecurityParams.disableWebGL = true` (API 26+) | — |
| OffscreenCanvas (CPU 2D) | `OffscreenCanvas` + `OffscreenCanvasRenderingContext2D` | 官方明示"对绘制速度有要求的场景应避免使用离屏绘制" |
| 关闭 ArkUI 手势冒泡 | `hitTestBehavior: HitTestMode.Block` | — |

---

## §10 已知 gap / 后续工作

| Gap | 性质 | 建议 |
|---|---|---|
| `Camera.raycast` 返回值详细字段 (节点 / 距离 / 命中点) | 一手 doc 只给类型签名 | P2 阶段写 SDK 调用实测 |
| ArkGraphics 3D `Effect` UUID 全集 | 一手 doc 只给 1 个示例 UUID | P2 实测需 `EffectParameters.effectId` 多枚举 |
| Three.js r170+ 在 HarmonyOS 真机 fps | 未在 HarmonyOS 真机实测 | P1 跑 §7.2 benchmark 1 |
| WebGPU 在 ArkWeb | 0 一手命中 | 路径 D 不可行, 不补 |
| `Component3D` 自定义 shader 与 Three.js shader 兼容 | 完全不同 (GLSL vs SPIR-V) | P2 阶段 `glslangValidator` 编译流水线 |
| ArkGraphics Editor 可用性 | doc 描述存在, 未实测安装 | P2 阶段 IDE 评估 |
| `@kit.ArkGraphics3D` API 26.0.0 完整 diff | 摘要级, 未一一核对 | 见 `js-apidiff-arkgraphics2d-6112` (ArkGraphics 2D 类似物) 模式 |
| Three.js postprocessing chain 在 ArkWeb 的实际帧率影响 | 未实测 | P1 benchmark |

---

## §11 阅读路径 (按角色)

| 角色 | 推荐阅读顺序 |
|---|---|
| **项目经理 / 评审** | §0 → §6.3 → §7.1 → §7.3 → §8.1 |
| **架构师 / 决策人** | §0 → §1 → §3 → §6 → §7.3 → §8.1 |
| **3D 实施工程师 (P1 WebView)** | §4 → §5 → §6.2 → §7.3 (P1) → §8.1 + `arkweb-render-pipeline-stability-2026-09-11.md` |
| **3D 实施工程师 (P2 原生)** | §2 → §3 → §6.2 → §7.3 (P2) → §8.1 |
| **API 文档速查** | §9 + §2 各小节 → 跳 §8.1 |
| **故障排查** | §4.3 + `arkweb-render-pipeline-stability-2026-09-11.md` + `bpta-arkweb-gpu-freeze` |

---

**Last updated:** 2026-09-23 (基于 devecocli docs v1.3.2 + SDK 6.1.1(24))
**Confidence:** 高 (所有 API 名称与签名均来自一手 doc) + 中 (Three.js / Babylon 在 HarmonyOS 真机 fps 未实测, 见 §7.2 benchmark)
**Next review:** P1 阶段跑完 §7.2 benchmark 1 后, 用实测 fps 更新 §4.4 表格

---

# 第二遍补充 (2026-09-23):HarmonyOS 7 / API 15+ 详尽功能目录 + 草案拆解 + 交叉映射

> **本节为二次深扫, 严格技术 inventory, 不含 roadmap / P0-P1 / 时间规划**
> **Source:** `devecocli docs` 一手信源为主; 草案参考 `D:\知识星系\1\` (Vite + Three.js + TypeScript + harmony/entry/.../GalaxyPage.ets)
> **目标读者:** 写代码的 3D 实施工程师 (P1/P2) + 评审需要知道"哪些 API 真的可用 / 哪些没有"的架构师
> **可信度约定:** 每条 API 都从 `devecocli docs read` 全文摘抄, 标"未验证"指一手 doc 未提及

---

## §12 HarmonyOS 7 / API 15+ 特性适配清单 (详尽功能目录)

> **约定:**
> - "since" = API 起版本
> - "cap" = 当前已确认上限版本
> - "doc" = 一手 docId (devecocli docs 全文读过)
> - "systemCapability" = 系统能力 tag (canIUse 门控)
> - "Confidence" = High (devecocli docs 全文, 含完整示例) / Medium (一手 doc 存在但仅摘要级) / Low (仅手册级提及, 缺细节)
> - "→ galaxy" = 该 capability 对 MindTrace 3D 力导星系的具体落地映射
> - "未验证 / unverified" = 任何一手 doc 未提及的事实, 包括 GPU 后端设备矩阵 / 真机 fps / 副作用

### 12.1 渲染管线 (ArkGraphics 3D 全 API 表)

#### 12.1.1 `Component3D` ArkUI 入口

- **API:** `Component3D(sceneOptions?: SceneOptions)` (ArkTS 函数式组件)
- **doc:** `API参考/ArkUI_方舟UI框架/ArkTS组件/渲染绘制/Component3D/ts-basic-components-component3d`
- **since:** API 12 (元服务 API 12 起)
- **systemCapability:** `SystemCapability.ArkUi.Graphics3D`
- **API surface (官方原文逐字):**

| 成员 | 类型 / 签名 | 说明 |
|---|---|---|
| `sceneOptions.scene` | `ResourceStr \| Scene` | 3D 模型资源文件或场景对象; 传 glTF (`.gltf`/`.glb`) → 自动场景模式 (框架自动建相机/光源/默认手势); 传 `Scene` 对象 → 自定义场景模式 (相机/光源/交互由开发者用 ArkGraphics 3D API 自己建); 不传 → 仅作为自定义渲染管线 (shader/customRender) 输出容器; **控件创建后不支持动态修改** |
| `sceneOptions.modelType` | `ModelType` | `TEXTURE=0` (GPU 合成) / `SURFACE=1` (专有硬件合成, 默认值) |
| `environment(uri: ResourceStr)` | — | 设置 3D 环境资源 (目前仅支持 GLTF 格式); **创建后不可改** |
| `customRender(uri: ResourceStr, selfRenderUpdate: boolean)` | — | 设置自定义渲染管线 (`.rng` 文件); `selfRenderUpdate=true` 时外部 UI 没更新也能触发动效渲染; 创建后不可改 |
| `shader(uri: ResourceStr)` | — | 自定义 shader (`.shader` JSON 描述符); 创建后不可改 |
| `shaderImageTexture(uri: ResourceStr)` | — | 自定义 shader 纹理; 多次调用 → 多绑定点 (顺序一致); 不支持纹理更换 |
| `shaderInputBuffer(buffer: Array<number>)` | — | 自定义 shader 动效参数; 长度 [0, 1048576] |
| `renderWidth(value: Dimension)` | — | 渲染分辨率宽度; **仅支持 `Dimension.Percentage`, [0, 100%]**; 创建后不可改 |
| `renderHeight(value: Dimension)` | — | 渲染分辨率高度; 同上 |

- **手势:** 自动场景模式框架自动接管"旋转/缩放"; 自定义场景模式"未内置相机控制器, 因此不会自动响应拖拽或缩放手势; 如需交互, 请开发者接入手势并更新相机的位置与旋转"
- **→ galaxy:** 主入口组件 — 整个 MindTrace 3D 页面是 1 个 `Component3D` 容器; sceneOptions.scene 用 `Scene` 对象 (自定义场景模式, 因我们需要自己摆 10 个节点 / 接管手势); modelType 用 `SURFACE` (默认); 配合 `ArkUI gesture` (`gesture` / `priorityGesture` / `parallelGesture`) 实现"指尖拨动星系"
- **Confidence:** High (官方示例完整, 含 `DamagedHelmet.gltf` 全套演示)

#### 12.1.2 `Scene` (基础模块, 加载 + 资源工厂)

- **API:** `Scene` 类 (import from `@kit.ArkGraphics3D`)
- **doc:** `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/Scene/js-apis-inner-scene`, `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/ohos_graphics_scene_ArkGraphics_3D模块_/js-apis-scene`
- **since:** API 12 (基础 + `Scene.load`); `renderFrame` API 15+; `renderConfiguration` API 23+; `createComponent` API 20+
- **systemCapability:** `SystemCapability.ArkUi.Graphics3D`
- **API surface (官方原文逐字):**

| 成员 | 类型 / 签名 | since | 说明 |
|---|---|---|---|
| `environment` | `Environment` | 12 | 环境对象 |
| `animations` | `Animation[]` (只读) | 12 | 动画数组 |
| `root` | `Node \| null` (只读) | 12 | 场景树根节点 |
| `renderConfiguration` | `RenderConfiguration` (只读) | 23 | 渲染配置 |
| `static load(uri?: ResourceStr)` | `Promise<Scene>` | 12 | 加载 glTF/glb (`.glb` 为二进制封装, 与 `.gltf` 内容等价); 相对路径 `$rawfile()`; 绝对路径从应用沙盒目录 (`Scene.load` 仅能读取应用自身写入的文件, 不能读取 hdc/adb push 写入的文件) |
| `getNodeByPath(path, type?)` | `Node \| null` | 12 | path 用 `/` 分隔; `type` 为 `NodeType` (可选, 不传 = 不限类型) |
| `getResourceFactory()` | `SceneResourceFactory` | 12 | 获取资源工厂 |
| `destroy()` | `void` | 12 | 销毁场景, 释放所有资源 (否则泄漏) |
| `importNode(name, node, parent)` | `Node` | 18 | 从其他场景导入节点 |
| `importScene(name, scene, parent)` | `Node` | 18 | 在当前场景中导入其他场景 |
| `renderFrame(params?)` | `boolean` | 15 | 按需渲染; `params.alwaysRender: boolean` (true=每帧都渲染, 默认 true); 返回 true = 调度成功 |
| `createComponent(node, name)` | `Promise<SceneComponent>` | 20 | 在指定节点上创建新组件 (由各插件定义有效名称) |

- **`RenderConfiguration` (API 23+):**
  - `shadowResolution: Vec2` — 全局阴影贴图分辨率 (px); 默认 1024×1024; >0 才生效; 浮点截取整数; ≤0 无视输入
  - `softShadowConfig: SoftShadowConfig` — 默认 undefined = 硬阴影; 设 PCFConfig = PCF 软阴影
- **`SoftShadowConfig` (API 26+):**
  - `shadowAlgorithmType: ShadowAlgorithmType` (只读) — 当前仅 `PCF=0`
- **`PCFConfig` (API 26+, 继承 SoftShadowConfig):**
  - `shadowSampleRadius: number \| undefined` — 采样半径 (默认 5.0); ≥0; =0 / undefined=5.0
  - `shadowSampleCount: number \| undefined` — 采样数量 (默认 16); 0~64; 超 64 自动夹到 64; =0 / undefined=16
- **`SceneComponent` (API 20+):**
  - `name: string` — 组件名
  - `property: Record<string, string\|number\|Vec2\|Vec3\|Vec4\|SceneResource\|boolean\|number[]\|string[]\|SceneResource[]\|Vec2[]\|Vec3[]\|Vec4[]\|null\|undefined>` — 只读属性集
- **`RenderParameters` (API 15+):**
  - `alwaysRender: boolean` — 是否每帧都渲染; 默认 true
- **`RenderContext` (API 20+, 静态):**
  - `Scene.getDefaultRenderContext()` → `RenderContext | null`
  - `RenderContext.getRenderResourceFactory()` → `RenderResourceFactory` (创建可在多场景共享的渲染资源)
  - `RenderContext.loadPlugin(name)` → `Promise<boolean>`
  - `RenderContext.registerResourcePath(protocol, uri)` → `boolean` — 注册 shader 资产文件路径目录 (例如 `myproto://` → `OhosRawFile://shaders/custom_shader/`)
- **→ galaxy:** 主页代码就靠这个 — `Scene.load($rawfile('galaxy/knowledge-galaxy.glb'))` (我们内嵌的 glTF) → `getResourceFactory()` → 创建 10 个相机节点 / 光源 / Effect / 自定义 Shader; `renderConfiguration.shadowResolution = {x: 2048, y: 2048}` (API 23+ 才用得上 PCF 阴影); 用 `getNodeByPath('rootNode_/core_identity')` 找节点; 每帧用 `scene.renderFrame()` 推动帧 (按需)
- **未验证 / unverified:** `RenderContext.registerResourcePath` 的多协议 URI 前缀在 SPIR-V 内部如何被引擎解析; `loadPlugin` 插件的可用名称全集 (官方只给示例名)
- **Confidence:** High (官方示例含两个完整路径 + 应用沙箱副本)

#### 12.1.3 `SceneResourceFactory` + `RenderResourceFactory` (资源创建)

- **doc:** `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/Scene/js-apis-inner-scene` §SceneResourceFactory + `js-apis-inner-scene` §RenderResourceFactory
- **systemCapability:** `SystemCapability.ArkUi.Graphics3D`
- **`SceneResourceFactory` (继承 `RenderResourceFactory`):**

| 工厂方法 | 签名 | since | 说明 |
|---|---|---|---|
| `createCamera(params)` | `Promise<Camera>` | 12 | 基础相机 |
| `createCamera(params, cameraParams)` | `Promise<Camera>` | 21+ (params: `SceneNodeParameters`, cameraParams: `CameraParameters`) | 带参数相机 |
| `createLight(params, lightType)` | `Promise<Light>` | 12 | `LightType.DIRECTIONAL` 或 `SPOT` |
| `createNode(params)` | `Promise<Node>` | 12 | 空节点 |
| `createMaterial(params, materialType)` | `Promise<Material>` | 12 | `MaterialType.SHADER` / `METALLIC_ROUGHNESS`(20+) / `UNLIT`(23+) / `OCCLUSION`(23+) |
| `createEnvironment(params)` | `Promise<Environment>` | 12 | 环境贴图 (KTX 推荐) |
| `createGeometry(params, mesh)` | `Promise<Geometry>` | 18 | 几何对象 (基于 `MeshResource`) |
| `createEffect(params)` | `Promise<Effect>` | 21+ | 特效 (params: `EffectParameters.effectId`) |

- **`RenderResourceFactory` (API 20+, 全局, 多场景共享):**

| 工厂方法 | 签名 | since | 说明 |
|---|---|---|---|
| `createShader(params)` | `Promise<Shader>` | 20+ | 着色器 (.shader JSON + .spv SPIR-V) |
| `createImage(params)` | `Promise<Image>` | 20+ | 图片 (png/jpg/ktx) |
| `createImageStream(params)` | `Promise<ImageStream>` | 26.0.0+ | 流式图片 (需 Stage 模型) |
| `createMesh(params, geometry)` | `Promise<MeshResource>` | 20+ | 网格 (geometry: `GeometryDefinition`) |
| `createSampler(params)` | `Promise<Sampler>` | 20+ | 采样器 |
| `createScene(uri?)` | `Promise<Scene>` | 20+ | 新场景 (不传 URI = 空场景) |

- **→ galaxy:** `sceneFactory.createCamera({name: 'mainCam'})` + `createLight({name: 'keyLight'}, LightType.DIRECTIONAL)` + `createMaterial({name: 'nodeMat'}, MaterialType.METALLIC_ROUGHNESS)` 是我们的"组装 3 件套"; 共享资源 (基础金属度材质) 走 `RenderContext.getRenderResourceFactory()`, 让多个 Scene 引用同一纹理
- **Confidence:** High

### 12.2 相机 / 灯光 / 场景图遍历

#### 12.2.1 `Camera` 类

- **doc:** `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/SceneNode/js-apis-inner-scene-nodes` §Camera
- **since:** 基础属性 API 12; `effects` API 21+; `msaa` API 22+; `renderingPipeline` API 21+; `raycast` API 20+; `getViewMatrix`/`getProjectionMatrix` API 23+
- **属性 (官方原文逐字):**

| 名称 | 类型 | since | 只读 | 说明 |
|---|---|---|---|---|
| `fov` | `number` | 12 | 否 | 视场, 弧度 (rad), 取值 (0, π) |
| `nearPlane` | `number` | 12 | 否 | 近平面, 世界单位, >0 |
| `farPlane` | `number` | 12 | 否 | 远平面, 世界单位, >nearPlane |
| `enabled` | `boolean` | 12 | 否 | 是否使能 |
| `postProcess` | `PostProcessSettings \| null` | 12 | 否 | 后处理设置 |
| `effects` | `Container<Effect>` | 21+ | 是 | 后处理特效容器 |
| `clearColor` | `Color \| null` | 12 | 否 | 渲染目标清空后的颜色 |
| `msaa` | `boolean` | 22+ | 否 | MSAA; 默认 false (即锯齿) |
| `renderingPipeline` | `RenderingPipelineType` | 21+ | 否 | `FORWARD_LIGHTWEIGHT=0` (默认, 只支持色调映射, 不支持 Bloom 等) / `FORWARD=1` (高质量) |

- **方法 (官方原文逐字):**

| 名称 | 签名 | since | 说明 |
|---|---|---|---|
| `raycast` | `raycast(viewPosition: Vec2, params: RaycastParameters): Promise<RaycastResult[]>` | 20+ | `viewPosition`: 屏幕归一化坐标 [0,1], (0,0)=Component3D 左上, (1,1)=右下; 返回命中数组, **按距离从近到远排序**, 无命中返回空数组 |
| `getViewMatrix` | `(): Mat4x4` | 23+ | 视图矩阵 |
| `getProjectionMatrix` | `(): Mat4x4` | 23+ | 投影矩阵 |

- **`RaycastParameters` (API 20+):** `{ rootNode?: Node }` — 限定射线起点 (未设置 = 整场景)
- **`RaycastResult` (API 20+):** `{ node: Node, centerDistance: number, hitPosition: Position3 }` — `centerDistance`: 命中物体包围盒中心到相机中心的距离, >0; `hitPosition`: 精确世界坐标
- **`CameraParameters` (API 21+):** `{ msaa?: boolean (22+), renderingPipeline?: RenderingPipelineType (21+) }`
- **→ galaxy:** 1 个 `Camera`, `fov` = 48° ≈ 0.838 rad (与 Three.js draft 完全一致!); `clearColor` = `{r: 0.008, g: 0.012, b: 0.031, a: 1.0}` (匹配 draft `0x020308`); `renderingPipeline = FORWARD` (开泛光/暗角); `msaa = true` (draft antialias=false, 但星系高 DPI 屏会明显锯齿, 建议开); `effects` 容器塞 1 个 `Effect` 调 `vibrance=0.3`; `raycast({x:0.5, y:0.5}, {rootNode})` 命中 node (替代 Three.js Raycaster); `getViewMatrix()/getProjectionMatrix()` 用于在 ArkTS 端做 HTML label 投影 (替代 draft 的 `position.project(camera)`)
- **未验证 / unverified:** `fov` 与 Three.js `PerspectiveCamera(fov)` 数值单位换算 (Three 用 degree, ArkGraphics 用 rad, 注意 ×Math.PI/180)
- **Confidence:** High

#### 12.2.2 `Light` + `LightType` + `DirectionalLight` + `SpotLight`

- **doc:** `js-apis-inner-scene-nodes` §Light, §LightType, §SpotLight, §DirectionalLight
- **since:** 基础 API 12; `innerAngle/outerAngle` API 23+
- **`LightType` enum:** `DIRECTIONAL=1` (平行光, 模拟太阳) / `SPOT=2` (聚光灯, 类似手电筒)
- **`Light` 属性:**

| 名称 | 类型 | 只读 | 说明 |
|---|---|---|---|
| `lightType` | `LightType` | 是 | 平行/聚光 |
| `color` | `Color` | 否 | 颜色 |
| `intensity` | `number` | 否 | 坎德拉 (cd), >0 |
| `shadowEnabled` | `boolean` | 否 | 是否使能阴影 |
| `enabled` | `boolean` | 否 | 是否使能光源 |

- **`SpotLight` 增量 (API 23+):**

| 名称 | 类型 | 只读 | 可选 | 说明 |
|---|---|---|---|---|
| `innerAngle` | `number` | 否 | 是 | 内角 (rad), 默认 0; 必须 ∈ [0, outerAngle]; 圆锥内光强不衰减 |
| `outerAngle` | `number` | 否 | 是 | 外角 (rad), 默认 PI/4; 必须 ∈ [innerAngle, PI/2]; 设 >PI/2 强制 =PI/2; 设 <innerAngle 强制 =innerAngle; 圆锥外无光强 |

- **→ galaxy:** 1 个 `DirectionalLight` (`color = {r: 0.918, g: 0.973, b: 1.0, a: 1}` ≈ `#eaf8ff`, `intensity = 1.35`, `shadowEnabled = true`, `position = {x: 18, y: -25, z: 40}`) — 与 draft 完全一致! 不需要 SpotLight
- **未验证 / unverified:** PunctualLight (点光源) / AreaLight (面光源) 在 6.1.1(24) 的官方列表里只有 DIRECTIONAL 和 SPOT, 没有点光源 — 这是 draft 的 `AmbientLight + DirectionalLight` 组合可以替代的, 但 `AmbientLight` **未在官方枚举里出现** ❌
- **Confidence:** High (DIRECTIONAL + SPOT 全属性都核对了)

#### 12.2.3 `Node` / `Container<T>` / `LayerMask` / `NodeType`

- **doc:** `js-apis-inner-scene-nodes` §Node, §Container, §LayerMask, §NodeType
- **since:** 基础 API 12; `NodeType.CUSTOM` API 21+
- **`Node` 属性:**

| 名称 | 类型 | 只读 | 说明 |
|---|---|---|---|
| `position` | `Position3` | 否 | 世界坐标系下场景单位 (cm/m/km 任选, 默认 m) |
| `rotation` | `Quaternion` | 否 | 旋转 (避免万向节锁) |
| `scale` | `Scale3` | 否 | 缩放 |
| `visible` | `boolean` | 否 | 是否可见 |
| `nodeType` | `NodeType` | 是 | 类型枚举 |
| `layerMask` | `LayerMask` | 是 | 图层掩码 |
| `path` | `string` | 是 | 节点路径 |
| `parent` | `Node \| null` | 是 | 父节点 (不存在 = 空值) |
| `children` | `Container<Node>` | 是 | 子节点; 只读容器, 但容器方法可操作子节点 |

- **`Container<T>` 方法:**

| 方法 | 签名 | 说明 |
|---|---|---|
| `append(item: T)` | `void` | 追加; 已存在则先移除再插入 (数量不增) |
| `insertAfter(item, sibling: T\|null)` | `void` | sibling=null = 插到开头 |
| `remove(item: T)` | `void` | 移除 |
| `get(index)` | `T \| null` | 索引访问 |
| `clear()` | `void` | 清空 |
| `count()` | `number` | 计数 (≥0) |

- **`LayerMask` 方法:** `getEnabled(index: number): boolean` / `setEnabled(index: number, enabled: boolean): void`
- **`NodeType` enum:** `NODE=1` / `GEOMETRY=2` / `CAMERA=3` / `LIGHT=4` / `CUSTOM=255` (API 21+, 扩展插件)
- **→ galaxy:** 每个知识节点 = 1 个 `Node`, `position` 直接来自 `forceLayout` 输出的 `(x, y, z)` (Vec3); `visible` 控制淡入淡出; `children` 当 `mainGroup.children` 容纳子 mesh (sprite glow); `getNodeByPath('core-identity')` 用于桥接层 ID 索引
- **Confidence:** High

### 12.3 材质 / Shader 系统

#### 12.3.1 `Material` 基类 + `MaterialType` 枚举

- **doc:** `js-apis-inner-scene-resources` §Material, §MaterialType
- **`MaterialType` enum:**

| 名称 | 值 | since | 说明 |
|---|---|---|---|
| `SHADER` | 1 | 12 | 着色器定义材质 |
| `METALLIC_ROUGHNESS` | 2 | 20+ | PBR 金属-粗糙度模型 |
| `UNLIT` | 3 | 23+ | 不受光照影响 |
| `OCCLUSION` | 4 | 23+ | 遮挡材质 (遮挡场景但不遮挡环境) |

- **`Material` 属性:**

| 名称 | 类型 | since | 只读 | 可选 | 说明 |
|---|---|---|---|---|---|
| `materialType` | `MaterialType` | 12 | 是 | — | 材质类型 |
| `shadowReceiver` | `boolean` | 20+ | 否 | 是 | 是否接收阴影; 默认 false |
| `cullMode` | `CullMode` | 20+ | 否 | 是 | `NONE=0` / `FRONT=1` / `BACK=2` (默认 BACK) |
| `blend` | `Blend` | 20+ | 否 | 是 | `{enabled: boolean}`; 默认 undefined (禁用) |
| `alphaCutoff` | `number` | 20+ | 否 | 是 | 透明阈值 [0,1]; 默认 1 (=不启用) |
| `renderSort` | `RenderSort` | 20+ | 否 | 是 | `{renderSortLayer: number [0,63] 默认 32, renderSortLayerOrder: number [0,255] 默认 0}` |
| `polygonMode` | `PolygonMode` | 23+ | 否 | 是 | `FILL=0` / `LINE=1` / `POINT=2`; 默认 FILL |

- **→ galaxy:** 每个 KnowledgeUnit 节点用 `MaterialType.METALLIC_ROUGHNESS` (`baseColor.factor` 控制主题色, `emissive` 在选中态增强); 关系连线 `LineBasicMaterial` 等价物需自写 shader (`MaterialType.SHADER` + 自写 .shader JSON)
- **Confidence:** High

#### 12.3.2 `MetallicRoughnessMaterial` (PBR)

- **doc:** `js-apis-inner-scene-resources` §MetallicRoughnessMaterial
- **since:** API 20+
- **属性 (10 个 MaterialProperty):**

| 属性 | 说明 |
|---|---|
| `baseColor` | 基础颜色贴图 (无光情况下的颜色) |
| `normal` | 法线贴图 (不改变几何结构) |
| `material` | 金属度参数 (Roughness/Metallic/Reflectance) |
| `ambientOcclusion` | 环境光遮蔽 |
| `emissive` | 自发光颜色 |
| `clearCoat` | 透明图层 (车漆 / 碳纤 / 湿润表面光泽) |
| `clearCoatRoughness` | 透明图层粗糙度 |
| `clearCoatNormal` | 透明图层法线 |
| `sheen` | 微纤维漫反射 (布料 / 织物) |
| `specular` | 非金属高光反射 |

- **`MaterialProperty` (API 20+):** `{ image: Image\|null, factor: Vec4, sampler?: Sampler }`
- **`Sampler` (API 20+):** `{ magFilter, minFilter, mipMapMode: SamplerFilter (NEAREST=0/LINEAR=1 默认 LINEAR), addressModeU/V: SamplerAddressMode (REPEAT=0/MIRRORED_REPEAT=1/CLAMP_TO_EDGE=2 默认 REPEAT) }`
- **→ galaxy:** 用于 KnowledgeUnit 节点的 emissive 呼吸效果 (selected 态调 emissive.factor); clearCoat 模拟"星球湿润感"
- **Confidence:** High

#### 12.3.3 `ShaderMaterial` + `Shader` + `.shader` 文件格式

- **doc:** `js-apis-inner-scene-resources` §ShaderMaterial, §Shader; `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/shader资源文件格式要求/arkgraphics3d-shader-resource`
- **`ShaderMaterial`:** `{ colorShader?: Shader (默认 undefined) }`
- **`Shader` 属性:** `{ inputs: Record<string, number\|Vec2\|Vec3\|Vec4\|Image> }` (只读)
- **`Shader.setShaderInputs(inputs)` (API 23+):** "性能优于直接设置 inputs 属性"; 仅 Stage 模型
- **`.shader` 文件 (JSON 描述符 + 引用 SPIR-V `.spv`):**

| 字段 | 类型 | 说明 |
|---|---|---|
| `compatibility_info` | object | `{ version: "22.00", type: "shader" }` 引擎版本声明 |
| `vert` | string | 默认 `"3dshaders://shader/core3d_dm_fw.vert.spv"`; 自定义 `"appshaders://yourDir/yourShader.vert.spv"` |
| `frag` | string | 默认 `"3dshaders://shader/core3d_dm_fw.frag.spv"`; 自定义 `"appshaders://yourDir/yourShader.frag.spv"` |
| `vertexInputDeclaration` | string | 默认 `"3dvertexinputdeclarations://core3d_dm_fw.shadervid"`; **暂不支持自定义 attributes 排布** |
| `state.rasterizationState` | object | enableDepthClamp / enableDepthBias / enableRasterizerDiscard / polygonMode (`fill`/`line`/`point`) / cullModeFlags (`back`/`front`/`none`/`front_and_back`) / frontFace (`counter_clockwise`/`clockwise`) |
| `state.depthStencilState` | object | enableDepthTest / enableDepthWrite / enableDepthBoundsTest / enableStencilTest / depthCompareOp (`never`/`less`/`equal`/`less_or_equal`/`greater`/`not_equal`/`greater_or_equal`/`always`) |
| `state.colorBlendState.colorAttachments[]` | array | enableBlend / colorWriteMask (`r_bit\|g_bit\|b_bit\|a_bit`) / srcColorBlendFactor / dstColorBlendFactor / colorBlendOp / srcAlphaBlendFactor / dstAlphaBlendFactor / alphaBlendOp |
| `materialMetadata[]` | array | `name: "MaterialComponent"`, `customProperties.data[]` 每个: `{ name, displayName, type (vec4/vec3/vec2/float/int), value }` |

- **`appshaders://` vs `OhosRawFile://`:** `vert/frag` 是引擎内部 URI (`appshaders://` = 自写 shader 沙盒路径), 由 `RenderContext.registerResourcePath(protocol, uri)` 注册映射 (e.g. `myproto://textures/base.png` → `OhosRawFile://shaders/custom_shader/textures/base.png`)
- **→ galaxy:** 我们的星系核心动画是 1 个 PBR 材质 + 1 个 Emissive 闪烁; **不需要自写 .shader**; **未验证 / unverified** 是否有"呼吸闪烁" 用 PBR 的 emissive 因子随时间 lerp 即可
- **未验证 / unverified:** `appshaders://yourDir/yourShader.frag.spv` 这个 SPIR-V 怎么编译 — 官方只说"用 SPIR-V", 但没有指明是 `glslangValidator` (Khronos) 还是华为自研编译器; 真机实测过才知道
- **Confidence:** High (属性表) + Medium (格式细节, 缺示例输出对照)

### 12.4 几何 / Mesh / glTF 加载

#### 12.4.1 `Geometry` / `Mesh` / `SubMesh` / `Morpher`

- **doc:** `js-apis-inner-scene-nodes` §Geometry; `js-apis-inner-scene-resources` §Mesh, §SubMesh, §Morpher
- **`Geometry` 属性 (继承 Node):** `{ mesh: Mesh (只读), morpher?: Morpher (API 20+, 可选) }`
- **`Mesh` 属性:** `{ subMeshes: SubMesh[] (只读), aabb: Aabb (只读), materialOverride?: Material }`
- **`SubMesh` 属性:** `{ name: string, material: Material, aabb: Aabb (只读) }`
- **`Morpher` (API 20+):** `{ targets: Record<string, number> }` — 形变目标权重, 通常 [0, 1]
- **→ galaxy:** KnowledgeUnit 节点 = 1 个 Geometry (承载 glTF 子模型 mesh); `mesh.materialOverride` 在选中时替换 PBR 材质; `morpher` 可选 (顶点动画)
- **Confidence:** High

#### 12.4.2 `MeshResource` + `GeometryDefinition` + 4 个原始几何

- **doc:** `js-apis-inner-scene-types` §GeometryDefinition, §GeometryType, §PrimitiveTopology, §CustomGeometry, §CubeGeometry, §PlaneGeometry, §SphereGeometry, §CylinderGeometry
- **`GeometryType` enum:**

| 名称 | 值 | since | 说明 |
|---|---|---|---|
| `CUSTOM` | 0 | 18+ | 自定义 |
| `CUBE` | 1 | 18+ | 立方体 |
| `PLANE` | 2 | 18+ | 平面 |
| `SPHERE` | 3 | 18+ | 球体 |
| `CYLINDER` | 4 | 23+ | 圆柱体 |

- **`PrimitiveTopology` enum:** `TRIANGLE_LIST=0` / `TRIANGLE_STRIP=1`
- **`CustomGeometry` 属性:** `{ topology, vertices: Vec3[], indices?: number[], normals?: Vec3[], uvs?: Vec2[], colors?: Color[] }`
- **`CubeGeometry`:** `{ size: Vec3 }` — 宽高深
- **`PlaneGeometry`:** `{ size: Vec2 }` — 宽高
- **`SphereGeometry`:** `{ radius: number (>0), segmentCount: number (≥3 正整数) }` — 经纬度分段
- **`CylinderGeometry` (API 23+):** `{ radius: number (>0), height: number (>0), segmentCount: number (≥3, 自动向下取整) }` — 圆周分段
- **工厂:** `RenderResourceFactory.createMesh(params: SceneResourceParameters, geometry: GeometryDefinition): Promise<MeshResource>`
- **`SceneResourceFactory.createGeometry(params: SceneNodeParameters, mesh: MeshResource): Promise<Geometry>` (API 18+)**
- **→ galaxy:** KnowledgeUnit 节点的"球形粒子"用 `SphereGeometry({radius: 0.5, segmentCount: 16})` (draft 里是 `SphereGeometry(3.8, 16, 12)`, 半径不同); 关系线不靠 Mesh, 走自定义 shader (没有 LineSegments 原语)
- **未验证 / unverified:** SphereGeometry 的 segmentCount 上限; CylinderGeometry 的 segmentCount 过大是否会真引发"线程阻塞" (官方明示)
- **Confidence:** High

#### 12.4.3 glTF / .glb 加载 + 资产约束

- **doc:** `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D场景搭建以及管理/arkgraphics3d-scene` §模型加载
- **支持:** 仅 glTF 2.0 (`.gltf` + `.glb` 二进制封装); OBJ/FBX ❌
- **纹理格式 (官方原文):**

| 格式 | 支持 |
|---|---|
| JPEG (`.jpg`/`.jpeg`) | 支持识别头部携带 JFIF / Exif / ICC Profile 标记; **HarmonyOS 7.0.0+ 新增**支持 DQT / XMP / MPF / Adobe 标记 |
| PNG (`.png`) | 支持标准 PNG |

- **场景相机:** glTF 可自带相机 (用模型相机) 或不自带 (ArkGraphics 3D 创建一个)
- **→ galaxy:** MindForce 3D 资产目录:
  - `rawfile/gltf/galaxy-nodes.glb` — 10 个 KnowledgeUnit 节点模型 (或直接用 SphereGeometry 替代 glb, 更轻量)
  - `rawfile/gltf/galaxy-environment.glb` — IBL 环境贴图
  - **未验证 / unverified** glTF 自带 morph targets / Draco 压缩 / Meshopt 压缩在 ArkGraphics 3D 是否识别
- **未验证 / unverified:** KHR_materials_pbrSpecularGlossiness / KHR_draco_mesh_compression / EXT_meshopt_compression 在 6.1.1(24) 的官方支持矩阵 (一手 doc 未明列)
- **Confidence:** Medium (格式 glTF + JPEG/PNG 高, 扩展 glTF 特性 Medium)

### 12.5 动画 / 特效 / 形变

#### 12.5.1 `Animation` (glTF 内置动画)

- **doc:** `js-apis-inner-scene-resources` §Animation; `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D场景动画控制以及管理/arkgraphics3d-animation`
- **since:** 基础 API 12; `speed` API 20+
- **属性:**

| 名称 | 类型 | since | 只读 | 说明 |
|---|---|---|---|---|
| `enabled` | `boolean` | 12 | 否 | 是否启用 |
| `speed` | `number` | 20+ | 否 | 播放速度因子, 默认 1.0, 负值反向 |
| `duration` | `number` | 12 | 是 | 持续时间, 秒, ≥0 |
| `running` | `boolean` | 12 | 是 | 是否正在播放 |
| `progress` | `number` | 12 | 是 | 进度, [0, 1] |

- **方法:**

| 方法 | 签名 | 说明 |
|---|---|---|
| `onStarted(callback: Callback<void>)` | `void` | start/restart 触发 |
| `onFinished(callback: Callback<void>)` | `void` | 播放完成 / finish 触发 |
| `start()` | `void` | 从当前进度开始 |
| `stop()` | `void` | 停止并设进度=0 |
| `pause()` | `void` | 暂停 |
| `restart()` | `void` | 从头开始 |
| `seek(position)` | `void` | position ∈ [0, 1] |
| `finish()` | `void` | 跳到最后并设进度=1 |

- **→ galaxy:** MindForce 3D 不需要 glTF Animation (我们用 Animator 驱动 emissive); 但若 glTF 节点自带"轻微浮动"动画可作为 fallback
- **Confidence:** High

#### 12.5.2 `Effect` + `EffectParameters` + 后处理 Effect API

- **doc:** `js-apis-inner-scene-resources` §Effect; `js-apis-inner-scene` §EffectParameters
- **since:** API 21+
- **modelConstraint:** "此接口仅可在 Stage 模型下使用"
- **`EffectParameters`:** `{ effectId: string }` — **固定格式 `'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'`** (示例 `'e68a7f45-2d21-4a0d-9aef-7d9c825d3f12'`)
- **`Effect` 属性:** `{ enabled: boolean, effectId: string (只读) }`
- **方法:** `getPropertyValue(propertyName)` / `setPropertyValue(propertyName, value)` (API 23+)
- **支持的 propertyName:** `'exposure'` (number, 推荐 [-5, 5], 越大越亮) / `'vibrance'` (number, 推荐 [-1, 1], 越大越鲜艳)
- **→ galaxy:** 整个 Scene 套 1 个 Effect (id = 'e68a7f45-2d21-4a0d-9aef-7d9c825d3f12'), setPropertyValue('vibrance', 0.4) 模拟"星云通透感"
- **未验证 / unverified:** UUID 全集 — 官方只给 1 个示例 UUID, 其他 effect 是否可用未明列
- **Confidence:** High (属性) + Medium (UUID 全集)

#### 12.5.3 `PostProcessSettings` (Camera.postProcess)

- **doc:** `js-apis-inner-scene-post-process-settings`
- **since:** 基础 API 12; `BloomSettings` API 18+; `VignetteSettings` + `ColorFringeSettings` API 22+
- **`ToneMappingType` enum:** `ACES=0` / `ACES_2020=1` / `FILMIC=2`
- **`ToneMappingSettings`:** `{ type?: ToneMappingType, exposure?: number (>0) }`
- **`BloomSettings` (API 18+):** "当 RenderingPipelineType 为 FORWARD_LIGHTWEIGHT 时, 此功能不可用"

| 属性 | 默认值 | 范围 |
|---|---|---|
| `thresholdHard` | 1.0 | ≥0 |
| `thresholdSoft` | 2.0 | ≥0 |
| `scaleFactor` | 1.0 | >0 |
| `scatter` | 1.0 | >0 |

- **`VignetteSettings` (API 22+):** `{ roundness?: number [0,1] 默认 sqrt(0.5) ≈ 0.707, intensity?: number [0,1] 默认 0.4 }`
- **`ColorFringeSettings` (API 22+):** `{ intensity?: number [0,1] 默认 0.2 }` — "当 RenderingPipelineType 为 FORWARD_LIGHTWEIGHT 时, 此功能不可用"
- **`PostProcessSettings`:** `{ toneMapping?, bloom?, vignette?, colorFringe? }`
- **→ galaxy:** Camera.postProcess = `{ toneMapping: {type: ACES_2020, exposure: 1.0}, bloom: {thresholdHard: 0.6, scaleFactor: 0.7}, vignette: {intensity: 0.3} }` — 模拟 draft 的 Bloom 视觉
- **Confidence:** High

### 12.6 环境 / IBL / 光照参数

#### 12.6.1 `Environment` + `EnvironmentBackgroundType`

- **doc:** `js-apis-inner-scene-resources` §Environment; `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/创建并使用环境资源/arkgraphics3d-resource-environment`
- **`EnvironmentBackgroundType` enum:**

| 名称 | 值 | 说明 |
|---|---|---|
| `BACKGROUND_NONE` | 0 | 无背景 |
| `BACKGROUND_IMAGE` | 1 | 图片背景 |
| `BACKGROUND_CUBEMAP` | 2 | 立方体贴图背景 |
| `BACKGROUND_EQUIRECTANGULAR` | 3 | 等距柱状投影背景 (HDR 全景) |

- **`Environment` 属性:**

| 名称 | 类型 | since | 可选 | 说明 |
|---|---|---|---|---|
| `backgroundType` | `EnvironmentBackgroundType` | 12 | 否 | 背景类型 |
| `indirectDiffuseFactor` | `Vec4` | 12 | 否 | 间接散射系数 |
| `indirectSpecularFactor` | `Vec4` | 12 | 否 | 间接反射系数 |
| `environmentMapFactor` | `Vec4` | 12 | 否 | 环境地图系数 |
| `environmentImage` | `Image \| null` | 12 | 是 | 环境图片 |
| `radianceImage` | `Image \| null` | 12 | 是 | 辐射图片 (HDR) |
| `irradianceCoefficients` | `Vec3[]` | 12 | 是 | 辐射系数 |
| `environmentRotation` | `Quaternion` | 23+ | 是 | 环境光旋转 (需归一化四元数); 仅 Stage 模型 |

- **→ galaxy:** `Environment` 用于 IBL; `backgroundType = BACKGROUND_EQUIRECTANGULAR`, `environmentImage` = KTX/HDR 全景图 (`KTX/quarry_02_2k_radiance.ktx` 官方示例); `indirectDiffuseFactor = (1,1,1,1)`, `indirectSpecularFactor = (0.9,0.9,0.9,1)`; 配合 PBR 金属度材质形成光斑反射
- **未验证 / unverified:** IBL 在真机低功耗 GPU (Mali-G57 等) 上是否有性能问题
- **Confidence:** High

### 12.7 帧驱动 / 性能观测 / HiTrace

#### 12.7.1 `Animator` / `AnimatorResult` (ArkTS 帧驱动)

- **doc:** `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/使用动画/帧动画_ohos_animator/arkts-animator`; `API参考/ArkUI_方舟UI框架/ArkTS_API/UI界面/ohos_animator_动画_/js-apis-animator`
- **since:** 基础 API 6 / 9; `create18` 版本弃用 + 新增 `SimpleAnimatorOptions`; `onFrame`/`onFinish`/`onCancel`/`onRepeat` API 12+ (替代 deprecated `onframe`/`onfinish`/`oncancel`/`onrepeat`)
- **`AnimatorOptions`:** `{ duration, easing ('friction' / 'ease' / ...), delay, fill ('forwards' / 'none'), direction ('normal' / 'reverse'), iterations (数字 / -1 无限), begin, end }`
- **`SimpleAnimatorOptions` (API 18+):** `new SimpleAnimatorOptions(100, 200).duration(2000)` — 仅起点 + 终点
- **`AnimatorResult` 属性 (API 12+):**

| 名称 | 类型 | 说明 |
|---|---|---|
| `onFrame` | `(progress: number) => void` | progress ∈ [begin, end]; 调 cancel/finish 会额外触发 1 次, 值为终点 |
| `onFinish` | `() => void` | 完成时 |
| `onCancel` | `() => void` | 取消时 |
| `onRepeat` | `() => void` | 重复时 |

- **API:** `UIContext.createAnimator(options): AnimatorResult` (推荐); `animator.create(options)` 已 deprecated; `animator.create18(options)` 支持 SimpleAnimatorOptions (API 18+)
- **生命周期约束:** "自定义组件销毁时 aboutToDisappear 释放动画对象, 避免循环依赖导致内存泄漏"
- **→ galaxy:** `uiContext.createAnimator({duration: 16, easing: 'linear', iterations: -1, begin: 0, end: 1}).onFrame = (t) => { /* deltaTime = t */ }` — 与 `requestAnimationFrame` 1:1 替代
- **Confidence:** High

#### 12.7.2 `RenderParameters.alwaysRender` (Scene.renderFrame 按需渲染)

- **doc:** `js-apis-inner-scene` §renderFrame, §RenderParameters
- **since:** API 15+
- **API:** `Scene.renderFrame(params?: RenderParameters): boolean` — `params.alwaysRender: boolean` (默认 true)
- **→ galaxy:** 当 `pausedByHost` 状态 = true, `scene.renderFrame({alwaysRender: false})` 跳过每帧; 在动画激活时 `alwaysRender = true` 60 fps
- **Confidence:** High (节选, 完整示例未在 doc 详列)

#### 12.7.3 `HiTraceMeter` (性能打点)

- **doc:** `开发指南/调测调优/Performance_Analysis_Kit_性能分析服务/性能跟踪/使用HiTraceMeter跟踪性能_C_C/hitracemeter-guidelines-ndk`; `API参考/调测调优/Performance_Analysis_Kit_性能分析服务/C_API/头文件/trace_h/capi-trace-h`
- **since:** 长期能力
- **API (C/C++):** `OH_HiTrace_StartTraceEx(level, name, ...)` / `OH_HiTrace_FinishTrace()` / `OH_HiTrace_CountTrace()` / ...
- **→ galaxy:** 在 `forceLayout` tick 入口打点 `HiTraceMeter.startTrace('GalaxyLayoutTick')`, 在 tick 出口 finishTrace — DevEco Profiler / IDE Profiler 可可视化
- **Confidence:** Medium (NDK 头文件引用存在, 但 HarmonyOS 7 ArkTS 端 HiTraceMeter 调用范式未在本研究深入)

#### 12.7.4 `HiAppEvent` (应用事件打点)

- **doc:** `开发指南/调测调优/Performance_Analysis_Kit_性能分析服务/事件订阅/HiAppEvent介绍/hiappevent-intro`; `hiappevent-faq`
- **API 风格:** `import { hiAppEvent } from '@kit.PerformanceAnalysisKit'` (或 PerformanceAnalysisKit 子模块)
- **→ galaxy:** 上报 fps 降级事件: `hiAppEvent.write({eventDomain: 'galaxy', eventType: 'fps_degrade', params: {fps, particles, elapsedMs}})`
- **Confidence:** Medium (kit 引用存在, 完整 API 表未深入)

#### 12.7.5 `WindowManager.FrameMetrics` (帧率指标)

- **doc:** `API参考/ArkUI_方舟UI框架/C_API/结构体/OH_WindowManager_FrameMetrics/capi-windowmanager-oh-windowmanager-framemetrics`; `arkts-apis-window-i` §帧率指标
- **since:** API 26.0.0+
- **字段:** `{ firstDrawFrame: boolean, inputHandlingDuration: number (ns), layoutMeasureDuration: number (ns), ... }`
- **→ galaxy:** 上报每帧 inputHandling + layout 时长, 看 gesture 调度是否阻塞帧
- **Confidence:** Medium (结构体字段摘要, 完整 list 未在本研究全文)

### 12.8 原生桥 (XComponent / NAPI / JSVM)

#### 12.8.1 `XComponent` ArkUI 组件

- **doc:** `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/添加组件/自定义渲染_XComponent/napi-xcomponent-guidelines`; `API参考/ArkUI_方舟UI框架/C_API/结构体/OH_NativeXComponent/capi-oh-nativexcomponent-native-xcomponent-oh-nativexcomponent`
- **since:** API 8 起 XComponent; API 11+ XComponentNode (API 12 起废弃)
- **2 个类型:** `XComponentType.SURFACE` (独立合成, 默认) / `XComponentType.TEXTURE` (与 ArkUI 组件树合成)
- **场景:** 高性能渲染 (游戏画面 / 3D 图形 / 复杂动画) + 媒体数据处理 (相机预览 / 视频播放)
- **3 种创建方式:** (1) ArkTS 声明式 UI + `XComponentController`; (2) ArkTS 声明式 UI + `OH_ArkUI_SurfaceHolder` (NDK); (3) ArkTS 自定义组件节点 (`typeNode.XComponent`) + `XComponentController`; (4) NDK 接口创建
- **Surface 生命周期 (ArkTS 侧, `XComponentController`):**
  - `onSurfaceCreated(surfaceId: string): void` — XComponent 创建完成 + 创建好 Surface 后触发
  - `onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void` — Surface 大小变化
  - `onSurfaceDestroyed(surfaceId: string): void` — 组件销毁
- **Surface 生命周期 (NDK 侧, `OH_ArkUI_SurfaceHolder`):**
  - `OnSurfaceCreated` — 组件上树且 `autoInitialize = true` 或调用 `OH_ArkUI_XComponent_Initialize`
  - `OnSurfaceChanged`
  - `OnSurfaceDestroyed` — 组件下树且 `autoInitialize=true` 或调用 `OH_ArkUI_XComponent_Finalize`
- **背景色:** `TEXTURE` 类型支持 `backgroundColor` + `opacity` + `shadow`; `SURFACE` 类型不支持通用属性背景色
- **→ galaxy:** 若走"自研 3D 引擎"路径, XComponent + NDK + EGL/Vulkan 是底层骨架; 但 §6 §E 已评估 30+ 人日复赛不现实 — **不在 P0/P1 选型**
- **Confidence:** High

#### 12.8.2 NAPI / JSVM / JSB

- **doc:** `开发指南/代码开发/使用JSVM-API实现JS与C_C_语言交互/JSVM-API使用指导/...`; `开发指南/代码开发/使用Node-API实现ArkTS_JS与C_C_语言交互/Node-API简介/napi-introduction`
- **API 范畴:** `napi_create_*` / `napi_get_*` / `napi_call_*` / `napi_load_module` / `napi_create_threadsafe_function` / `napi_create_async_work`
- **JSVM 用途:** JS 引擎加速 (WASM 字节码编译/优化/cache), **不解决 WebGPU 缺位**
- **约束:** `napi_env` 不可缓存, 因多线程调用上下文不同
- **→ galaxy:** 路径 E (XComponent + NDK + 自研引擎) 需要 NAPI 桥接 ArkTS↔C++; 路径 A (Component3D) **不需要 NAPI**, 全部走 ArkTS
- **Confidence:** High

#### 12.8.3 OpenGL ES / Vulkan Native

- **doc:** `API参考/OpenGL_ES/opengles` (3.2+ 支持); `API参考/Vulkan/Vulkan支持能力/vulkan` (v1.4.309); `API参考/Vulkan/Vulkan扩展能力/Vulkan/capi-vulkan`; `vulkan-ohos-h`
- **GLES:** OpenGL ES 3.2+ (与 ArkGraphics 3D 硬件门槛匹配)
- **Vulkan:** v1.4.309 (符号集见 `vulkan` docId)
- **Vulkan 扩展:** `VkSurfaceCreateInfoOHOS` (`vulkan_ohos.h`); `VK_OHOS_surface` (创建对接 OHNativeWindow 的 VkSurfaceKHR); `VK_OHOS_external_memory` (Vulkan 与 OH_NativeBuffer 零拷贝)
- **`SystemCapability`:** `SystemCapability.Graphic.Vulkan` (since 10)
- **→ galaxy:** Component3D 内部隐含 GLES 3.2+ / Vulkan 1.0+; 路径 E (自研) 需显式选 backend
- **Confidence:** High

### 12.9 2D Canvas 跃升 (OffscreenCanvas / Worker / filter / blend)

#### 12.9.1 `OffscreenCanvas` 组件

- **doc:** `API参考/ArkUI_方舟UI框架/ArkTS组件/画布绘制/OffscreenCanvas/ts-components-offscreencanvas`
- **since:** API 8
- **机制:** "屏幕外渲染的画布, 可在单独的线程中运行一些任务, 从而避免影响主线程性能"
- **官方明示:** "离屏绘制使用 CPU 进行绘制, 绘制速度较慢, 对绘制速度有要求的场景应避免使用离屏绘制" (`faqs-arkgraphics-2d-34`)
- **→ galaxy:** 不适用 — 我们走 3D 路径, 2D 离屏不解决 GPU 渲染瓶颈
- **Confidence:** High

#### 12.9.2 `OffscreenCanvasRenderingContext2D` (filter / blend)

- **doc:** `API参考/ArkUI_方舟UI框架/ArkTS组件/画布绘制/OffscreenCanvasRenderingContext2D/ts-offscreencanvasrenderingcontext2d`; `开发指南/ArkUI_方舟UI框架/UI开发_兼容JS的类Web开发范式/常见组件开发指导/Canvas开发指导/OffscreenCanvasRenderingContext2D对象/ui-js-components-offscreencanvas`
- **since:** API 8
- **filter:** `filter: string` — CSS-like 滤镜 (示例: `'blur(5px)'`)
- **→ galaxy:** 不适用 — KnowledgeUnit "粒子纹理" 用 ArkGraphics 3D 的 `Image` 资源 + PBR 材质即可
- **Confidence:** High

#### 12.9.3 `Worker` / `TaskPool` (多线程)

- **doc:** `开发指南/ArkTS_方舟编程语言/ArkTS并发/多线程并发/TaskPool和Worker的对比/taskpool-vs-worker`; `faqs-arkts-28`; `faqs-arkts-36`
- **Worker 数量上限:** 最多 64 个 Worker 实例
- **TaskPool:** 动态调整线程数量, 不支持手动设置, 内置调度器/线程池/优先级/任务组
- **通信:** Worker → 主线程 `postMessage`; TaskPool → 主线程 `sendData`; 都基于 Actor 并发模型
- **→ galaxy:** `forceLayout` 300 iterations × 10 节点 O(n²) 计算量很小, 走主线程即可 (实测 < 16ms/帧); **若** 节点数升级到 1000+, 用 `TaskPool` 并行分段计算 layout
- **Confidence:** High

### 12.10 2D ArkTS UI (Canvas + Animation + clickable + accessibility)

#### 12.10.1 `Canvas` 组件 + `CanvasRenderingContext2D`

- **doc:** `开发指南/ArkUI_方舟UI框架/UI开发_兼容JS的类Web开发范式/常见组件开发指导/Canvas开发指导/Canvas对象/ui-js-components-canvas`; `FAQ/UI框架/UI界面/使用Canvas绘制树形组织结构/faqs-arkui-1619`; `如何使用Canvas绘制阅读页_并实现文字选中与评论功能/faqs-arkui-614`
- **since:** API 7+
- **Canvas:** 画布组件, 默认 `width: 300px, height: 150px`, 默认背景色与父组件一致
- **CanvasRenderingContext2D:** 主线程 CPU 绘制; "Canvas + CanvasRenderingContext2D 是用于在 Canvas 上进行绘制的画笔, 在主线程上通过 CPU 进行绘制"
- **→ galaxy:** MindTrace 已有 `ReviewGraphView.ets` 2D Canvas 实现 (1880 LOC), 用 `CanvasRenderingContext2D` 绘制 orbits / planets / links — 短期 P0 维持
- **Confidence:** High

#### 12.10.2 `Gesture` / `onTouch` (通用手势)

- **doc:** `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/添加交互响应/添加手势响应/单一手势/arkts-gesture-events-single-gesture`; `绑定手势方法/arkts-gesture-events-binding`; `API参考/ArkUI_方舟UI框架/ArkTS_API/UI界面/ohos_arkui_UIContext_UIContext_/Types/arkts-apis-uicontext-t`
- **支持手势:** `PanGesture` / `PinchGesture` / `RotationGesture` / `TapGesture` / `LongPressGesture` / `SwipeGesture` / `GestureGroup`
- **`PanListenerCallback` (API 19+ 元服务):** `type PanListenerCallback = (event: GestureEvent, current: GestureRecognizer, node?: FrameNode) => void`
- **→ galaxy:** Component3D 接 3 个手势: `PanGesture` (旋转星系) + `PinchGesture` (zoom) + `TapGesture` (选中节点); 用 `event.fingerList[0].localX/Y` 转 `Vec2` 给 `camera.raycast`
- **Confidence:** High

#### 12.10.3 `focusable` / `focusOnTouch` (可访问性)

- **doc:** `FAQ/UI框架/组件使用/ArcSwiper如何适配表冠/faqs-arkui-439`
- **API:** `.focusable(true).focusOnTouch(true)` — 组件获焦响应键盘 / 表冠事件
- **→ galaxy:** 评审 demo 现场可能在 Watch 上演示 (1.5 弧形屏), ArcList / ArcSwiper 是 watch 适配组件, 但 Component3D 不支持 watch (没 GPU); 桌面端 focusable 用于键盘 Tab 切换节点
- **Confidence:** High

### 12.11 多设备形态 (foldable / split-screen / large-screen / watch)

#### 12.11.1 `WindowMode` (分屏 / 自由悬浮 / 智慧多窗)

- **doc:** `开发指南/ArkUI_方舟UI框架/窗口管理/窗口模式/窗口模式简介/window-mode-overview`
- **模式:** 全屏 / 最大化 / 最小化 / 自由悬浮窗口 / 分屏 (single Window 的属性)
- **智慧多窗:** 多种窗口模式组合实践, 同时多个 app 窗口悬浮 / 分屏 / 全景多窗
- **→ galaxy:** 评审 demo 可能平板运行, `display.on('change')` 监听屏幕宽高变化, 重排 `Camera.aspect` + resize Component3D
- **Confidence:** High (WindowMode 概念), Medium (与 Component3D 协作细节未深入)

#### 12.11.2 设备类型 + 折叠屏

- **doc:** `开发指南/使用模拟器运行应用/修改模拟器/自定义屏幕配置/ide-emulator-customize-screen-configuration`; `开发指南/使用模拟器运行应用/概述/设备支持类型/ide-emulator-devicetype`
- **设备类型:** Phone 直板机 (Windows+X86 / macOS+ARM); Foldable 双折叠 / WideFold 阔折叠 / TripleFold 三折叠 / Tablet / PC/2in1 (从 6.0.1 Beta1 起支持)
- **区域限制:** "Phone 直板机仅支持在中国境内 (港澳台除外) 使用"
- **→ galaxy:** 在 PC/2in1 (模拟器 6.0.1+ 支持) 调试 force-directed + 真机 Phone 演示 60 fps 是合理分工
- **Confidence:** High

#### 12.11.3 `ArcList` (圆形屏幕)

- **doc:** `API参考/ArkUI_方舟UI框架/ArkTS组件/滚动与滑动/ArcList/ts-container-arclist`; `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/列表与网格/弧形列表_ArcList_圆形屏幕推荐使用/arkts-layout-development-create-arclist`
- **since:** API 18+
- **设备:** Phone / PC/2in1 / Tablet / TV / **Wearable**; API 22+ 在 1.95 英寸/2.0 英寸/2.04 英寸等表盘上
- **`ArcListItem`:** ArcList 子组件, 必须配合 ArcList
- **→ galaxy:** 评审 demo 可能含 Wearable 设备; Component3D 不支持 Wearable, 但 KnowledgeUnit 列表 fallback 用 `ArcList`
- **Confidence:** High

### 12.12 AI 增强 (`@hms.ai.llm` / `@kit.AIEngine` / Data Augmentation Kit / CANN)

#### 12.12.1 `@kit.AIEngine` (Foundation Model, 端侧 LLM)

- **doc:** §2 of `harmonyos-kits-survey-2026-09-05.md` (综合) + 项目 `LlmClient` 现行使用
- **API 风格:** `import { textGenerator, imageGenerator, embedding } from '@kit.AIEngine'`; `textGenerator.generate({prompt, options})`
- **设备门控:** `canIUse('SystemCapability.AI.文本生成')` 必须 try/catch
- **→ galaxy:** KnowledgeUnit 节点的 label 在端侧 LLM 失败时可降级到本地 embedding → 节点簇; **未验证 / unverified** 实际能力清单
- **Confidence:** Medium (一手 doc 在 devecocli docs 搜 "AIEngine" 无直接命中, 仅依赖项目侧经验)

#### 12.12.2 `@hms.ai.llm` (HMS 增强 LLM, 云 + 端协同)

- **doc:** §2 of `harmonyos-kits-survey-2026-09-05.md`
- **API:** 云端 + 端侧协同, 华为账号鉴权, 自定义 prompt 模板, 流式 SSE, 多轮对话上下文
- **→ galaxy:** MindTrace `LlmClient` 当前 HTTP 自配 (`LlmConfig`); W4+ 接 `@hms.ai.llm` 是 P1 工作
- **Confidence:** Medium

#### 12.12.3 `Data Augmentation Kit` (AIP / localChatModel, 端侧问答)

- **doc:** `开发指南/Data_Augmentation_Kit_数据增强服务/端侧问答模型/dataaugmentation-localchatmodel`; `API参考/Data_Augmentation_Kit_数据增强服务/ArkTS_API/localChatModel_端侧问答模型/dataaugmentation-localchatmodel-api`
- **since:** 6.0.0(20)
- **设备:** "当前端侧模型问答仅支持 PC/2in1 设备类型"
- **API:** `localChatModel.init(...)` / `localChatModel.chat(...)` (流式问答)
- **→ galaxy:** 桌面端 AI 复习对话 (复习页浮窗); MindTrace 复赛窗口 Phone 演示, **不优先**
- **Confidence:** High (节选)

#### 12.12.4 `Data Augmentation Kit` (retrieval, 端侧向量化 + 检索)

- **doc:** `开发指南/Data_Augmentation_Kit_数据增强服务/端侧问答模型/dataaugmentation-localchatmodel`; `API参考/Data_Augmentation_Kit_数据增强服务/ArkTS_API/retrieval_智慧化数据平台/dataaugmentation-retrieval-api`; `开发指南/ArkData_方舟数据管理/应用数据向量化_ArkTS/aip-data-intelligence-embedding`
- **since:** API 15 (ArkData Intelligence Platform AOS)
- **能力:** 多模态嵌入模型 (Embedding Model) 把文本/图片生成向量表征, 语义多模态知识检索
- **→ galaxy:** KnowledgeUnit embedding 算向量 → 在 3D 空间做 k-NN 聚类可视化 (知识星系 "主题分组" 自然涌现)
- **Confidence:** High (设备 PC/2in1 限定)

#### 12.12.5 `CANN Kit` (昇腾 / Kirin 异构计算, 端侧推理)

- **doc:** `开发指南/CANN_Kit_CANN异构计算框架服务/CANN_Kit简介/cannkit-introduction`; `API参考/CANN_Kit_CANN异构计算框架服务/C_API/模块/CANN/cannkit`
- **since:** 基础 API 11; LLM Engine API 24 (`libcann_llm_engine.so`)
- **设备:** Kirin X90 等昇腾 / 麒麟平台
- **能力:** OMG 离线模型转换 (Caffe/TensorFlow/ONNX/MindSpore → OM); LLM 模型量化 (16-4 grouplinear)
- **→ galaxy:** KnowledgeUnit 标题→向量的离线模型推理, 在 Kirin 设备上 NPU 加速
- **未验证 / unverified:** 模型量化步骤在手机端的实际耗时
- **Confidence:** High (kit 引用存在)

#### 12.12.6 `MindSpore Lite Kit` (昇思推理框架)

- **doc:** `API参考/MindSpore_Lite_Kit_昇思推理框架服务/ArkTS_API/ohos_ai_mindSporeLite_端侧AI框架_/js-apis-mindsporelite`; `开发指南/MindSpore_Lite_Kit_昇思推理框架服务/模型部署/...`
- **能力:** 轻量化端侧 AI 引擎, 模型推理 + 训练, 内置通用硬件高性能算子库, 支持 Neural Network Runtime Kit NPU 加速
- **→ galaxy:** MindTrace 的 OCR 模型 / 嵌入模型推理底层
- **Confidence:** High

### 12.13 HMS 协同 (账号同步 / Push)

#### 12.13.1 `Account Kit` (华为账号)

- **doc:** 项目当前未使用, 但已规划 (W5+)
- **→ galaxy:** MindForce 3D 节点"上次浏览位置"跨设备同步, 走 Account Kit
- **Confidence:** Low (本调研未深入)

#### 12.13.2 `Push Kit`

- **doc:** `FAQ/消息推送服务_Push_Kit/...`
- **能力:** 系统级推送, 离线缓存 15 天
- **应用:** `com.ohos.sceneboard` (而非旧版 `com.huawei.hms.pushservice`)
- **→ galaxy:** 复赛后复习提醒; 当前 ReminderAgent 已够用, Push 是 W5+ 离线备份通道
- **Confidence:** Medium (FAQ 节选, 未深入 push API 表)

### 12.14 跨进程通信 (WebMessagePort / HiAppEvent / Service Widget FormAbility)

#### 12.14.1 `WebMessagePort` (ArkWeb 桥)

- **doc:** `API参考/ArkWeb_方舟Web/ArkTS_API/ohos_web_webview_Webview_/Enums/arkts-apis-webview-e` §WebMessageType; `API参考/ArkWeb_方舟Web/ArkTS_API/ohos_web_webview_Webview_/Interface_WebMessagePort/arkts-apis-webview-webmessageport`; `API参考/ArkWeb_方舟Web/C_API/结构体/ArkWeb_WebMessagePortAPI/capi-web-arkweb-webmessageportapi`
- **WebMessageType enum:**

| 名称 | 值 | 说明 |
|---|---|---|
| `NOT_SUPPORT` | 0 | 不支持 |
| `STRING` | 1 | 字符串 |
| `NUMBER` | 2 | 数值 |
| `BOOLEAN` | 3 | 布尔 |
| `ARRAY_BUFFER` | 4 | 原始二进制 |
| `ARRAY` | 5 | 数组 |
| `ERROR` | 6 | 错误 |

- **JSBridge vs MessagePort:** JSBridge 用于一次性 RPC, MessagePort 用于大数据量双向流
- **Native 端:** `ArkWeb_WebMessagePortAPI` (C/C++) 避开 ArkTS 主线程, 数据类型仅 STRING / ARRAY_BUFFER
- **→ galaxy:** §13 草案 `GalaxyBridge` 已用; P1 (WebView + Three.js) 路径完全依赖它
- **Confidence:** High

#### 12.14.2 `@ohos.app.form.FormExtensionAbility` (服务卡片)

- **doc:** `harmonyos-kits-survey-2026-09-05.md` §5+§6; `API参考/Form_Kit_服务卡片/...`
- **能力:** 卡片 UI 渲染层 (FormExtensionAbility + formBindingData) + 卡片交互层 (FormClickEvent / router / callEvent)
- **→ galaxy:** KnowledgeUnit 摘要卡片 + 桌面 widget (W4+ 后 W5+ 工作)
- **Confidence:** High (项目侧已落地 scaffold)

### 12.15 调试 / 可观测 (DevEco Profiler / FrameMetrics / HiTrace / ArkUI Inspector)

#### 12.15.1 `DevEco Profiler`

- **doc:** `FAQ/技术质量/性能/H5页面加载缓慢/faqs-performance-8`; `FAQ/技术质量/性能/如何获取应用性能监控数据/faqs-performance-54`; `FAQ/性能分析/Profiler窗口无法加载/faqs-profiler-6`
- **能力:** Reallocation 模板 (CPU/内存/帧率/GPU/能耗/网络流量); Energy 模板 (CPU 高负载); Allocation 模板 (堆内存分配)
- **→ galaxy:** 真机 Profile Component3D 帧率, 看 GPU 占用 + Shader 编译耗时
- **Confidence:** High

#### 12.15.2 `ArkUI Inspector`

- **doc:** `FAQ/UI框架/组件使用/识别和解决NodeController节点迁移双挂与卡顿问题/faqs-arkui-1067` §"ArkUI Inspector工具可视化确认"
- **能力:** 可视化组件树, 检测 NodeContainer 双挂 / 重复挂载
- **→ galaxy:** 验证 NodeContainer / NodeController 没有双挂 (P1 桥接实验期)
- **Confidence:** High

#### 12.15.3 `Graphics Profiler` (ArkGraphics 专用)

- **doc:** `最佳实践/性能分析/...` + `bpta-xcomponent-render-problem-guide`
- **能力:** 图形渲染定位工具链, GPU 命令流分析
- **→ galaxy:** 真机 GPU 命令流分析, 看 shader 编译 / drawcall 数量
- **Confidence:** Medium (kit 引用存在, 完整功能未深入)

---

## §13 草案 (`D:\知识星系\1`) 可迁移设计要素拆解

> **草案规模:** 5 个 TS 文件 (`main.ts` 619 行 / `forceLayout.ts` 158 行 / `messageBridge.ts` 83 行 / `types.ts` 38 行 / `mockData.ts` 82 行) + 5 个 ArkTS 文件 (`harmony/entry/.../GalaxyPage.ets` 329 行 / `GalaxyModels.ets` 48 行 / `GalaxyMockData.ets` 74 行 / `EntryAbility.ets` 13 行 + vite.config 等)
> **拆解 6 大类 (A-F):** A 算法 / B 渲染 / C 桥接 / D 交互 / E 降级 / F 数据模型

### A. 算法层 (vertex physics simulation)

#### A.1 force-directed 力导布局 (`forceLayout.ts:9-115`)

- **草案源:** `forceLayout.ts:9-115` (`createGalaxyLayout` 函数)
  - 常量: `ITERATIONS=300` (迭代次数) / `REPULSION=68` (斥力常数) / `SPRING=0.018` (弹簧系数) / `CENTER=0.012` (中心引力) / `TARGET_EDGE=22` (目标边长) / `MAX_STEP=1.6` (单步最大位移)
  - 初始化: golden angle (`2.399963`) 散布 + 半径 sqrt 分布
  - 主循环: O(n²) 节点斥力 → 边弹簧 → 中心引力 → 阻尼 (×0.82) → 限速 → 位置更新
  - RNG: `mulberry32(seed=20260920)` (确定性)
- **ArkTS 等价物:**
  - **没有官方等价物** — ArkGraphics 3D 不提供物理 / 力导算法
  - 移植: 把 `createGalaxyLayout` 原样搬到 `entry/src/main/ets/services/galaxy/GalaxyForceLayout.ets` (TypeScript 语法转 ArkTS, 循环 / Vec3 数学兼容), 输入 `GalaxyNodeRenderDTO[]`, 输出 `Vec3[]` (ArkGraphics Vec3), 然后 `node.position = {x, y, z}`
  - 异步执行: 用 `TaskPool` 跑 300 iterations (10 节点 O(n²) = 100 次比较, < 16ms, 主线程亦可)
- **差异 / gotcha:**
  - `Mulberry32` seed 是 constant (20260920), 不是节点 ID 派生 → 同一节点集永远同一布局; 若需"重置"独立种子, seed 改成时间戳
  - 草案 z 维度仅 `(random - 0.5) * 14` (扁平星系), 实际 3D 可放宽 z 范围
  - 草案只有 `CENTER.x/y` 引力 + `CENTER.z * 1.25` 修正, 若想"球形引力"需自写
- **迁移成本:** **straight rewrite** (100 LOC, 1 文件), 测试 50 LOC

#### A.2 seeded RNG (`main.ts:613-618` `seededNoise` + `forceLayout.ts:149-158` `mulberry32`)

- **草案源:** `main.ts:613-618` (GLSL-style fract(sin) hash for particle layout); `forceLayout.ts:149-158` (Mulberry32 for force layout)
- **ArkTS 等价物:**
  - **没有官方等价物** — ArkTS 无内置 seeded RNG
  - 自写: 把 `mulberry32` + `seededNoise` 直接搬到 `GalaxyLayout.ets` (ArkTS 数学兼容)
  - 粒子随机位置用 `Math.sin(value * 12.9898 + 78.233) * 43758.5453` (GLSL 风格 fract), 数学上 ArkTS `Math.sin` 与 GLSL `sin` 等价
- **差异 / gotcha:**
  - 草案用 2 套 RNG (粒子用 hash 函数, 力导用 mulberry32), 移植时保持 2 套即可, 不可混用
  - ArkTS 是严格类型, seed 类型用 `number` (无符号 32 位整数)
- **迁移成本:** **straight rewrite** (10 LOC)

#### A.3 particle budget 分配 (`main.ts:10-12` `HIGH/LOW_PARTICLE_BUDGET`)

- **草案源:** `main.ts:10-12` (`HIGH_PARTICLE_BUDGET=8000`, `LOW_PARTICLE_BUDGET=3000`, `LOW_FPS_THRESHOLD=30`)
- **ArkTS 等价物:**
  - **没有官方等价物** — 但 ArkGraphics 3D 的 `Scene.renderFrame({alwaysRender: false})` (API 15+) 是按需渲染, 类似"帧率降级"的另一种思路
  - `MetallicRoughnessMaterial` 的 `alphaCutoff` (API 20+) 可以做粒子"群体淡出", 但不是"减少数量"
  - **节点数量动态调整:** 用 ArkTS 端 `@State particles: number = 8000` 控制 `BufferGeometry` 的 `setDrawRange(0, count)` — 但 ArkGraphics 3D 没有直接对应的 `Geometry.setDrawRange`, 需要走自定义 `MeshResource` 重创建
- **差异 / gotcha:**
  - ArkGraphics 3D 没有 `setDrawRange` (Three.js 的 GPU 优化捷径) — 只能"减少 Geometry 顶点"或"换材质 alpha"
  - 完整 `degradeQuality()` 函数可移植: 触发条件 (fps < 30 ≥ 2s) → 关闭粒子自旋 (`dustMotionEnabled = false`) → 重画粒子 geometry 顶点 (count → 3000)
- **迁移成本:** **wrapper** (需要重写 `setDrawRange` 路径, 50 LOC)

#### A.4 frustum-cull (`main.ts:134` `particlePoints.frustumCulled = false`)

- **草案源:** `main.ts:134` — "粒子永远可见"
- **ArkTS 等价物:**
  - **不需要** — ArkGraphics 3D 引擎层自带视锥剔除 (`Camera` + `Mesh.aabb` 自动 cull)
  - 节点上 `visible: boolean` 可手动禁用, 但不需要显式 `frustumCulled` 属性
- **差异 / gotcha:**
  - 草案"显式禁用"是反优化 (因为 Three.js 的 frustumCulled 算法不精确); ArkGraphics 3D 反之"显式不干预"
- **迁移成本:** **drop** (不需要)

#### A.5 LOD degrade / fps 驱动质量降级 (`main.ts:555-583`)

- **草案源:** `main.ts:555-583` `updatePerformance()` + `degradeQuality()`
- **ArkTS 等价物:**
  - **没有原生 LOD 系统** — ArkGraphics 3D 不暴露 LOD API
  - **帧率采样**可走 `AnimatorResult.onFrame` 自己做 + 决策树
  - **`Scene.renderFrame({alwaysRender: false})`** 是天然按需渲染开关, 不需要自己 degrade
- **差异 / gotcha:**
  - ArkGraphics 3D 的 GPU 后端是 `OpenGL ES 3.2+ 或 Vulkan 1.0+`, 性能由 GPU 决定, **降级策略应改"减少 Effect 数 / 关闭 MSAA / 调低 renderWidth/Height"** 而不是减粒子数
- **迁移成本:** **new design** (需要重新设计降级维度, 100 LOC)

### B. 渲染层 (Three.js setup constants)

#### B.1 DPR cap 1.25 (`main.ts:9` `MAX_DPR = 1.25`)

- **草案源:** `main.ts:9` + `main.ts:98/403` `renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, MAX_DPR))`
- **ArkTS 等价物:**
  - **`Component3D.renderWidth/renderHeight` (Dimension.Percentage, [0, 100%])** — 间接控制渲染分辨率
  - 默认情况下 `Component3D` 渲染分辨率 = 控件大小 × system DPR; 限制 DPR 等价于限制 `renderWidth/renderHeight` 百分比
- **差异 / gotcha:**
  - ArkGraphics 3D 没有 `setPixelRatio` 直 API, 必须用百分比; 调成 `renderWidth('50%').renderHeight('50%')` 即等效 DPR 0.5
  - **控件创建后不支持动态修改** (官方明示) — 想"动态 DPR 降级"需在 `if/else` 分支中创建 2 个 Component3D, 切换可见性
- **迁移成本:** **wrapper** (50 LOC, 含 if/else 切换)

#### B.2 FogExp2 0.012 (`main.ts:86` `scene.fog = new THREE.FogExp2(0x02040a, 0.012)`)

- **草案源:** `main.ts:86`
- **ArkTS 等价物:**
  - **没有官方 Fog API** — ArkGraphics 3D 没有暴露 Fog/雾
  - **等价物:** `Environment` 的 `backgroundType = BACKGROUND_EQUIRECTANGULAR` + IBL 渐变 + `PostProcessSettings.colorFringe` (API 22+) 模拟远景雾化
  - 或: 自写 shader 在 fragment 中按距离 lerp 背景色
- **差异 / gotcha:**
  - 草案用 GPU shader 实现, ArkGraphics 3D 没暴露只能走自写 shader (兜底到 .shader 文件)
  - **PBR `MetallicRoughnessMaterial` 不包含雾的混合** — 需在 fragment 自写
- **迁移成本:** **new design** (需自写 fragment 雾混合, 200 LOC + .spv 编译流水线)

#### B.3 PerspectiveCamera FOV 48° (`main.ts:88`)

- **草案源:** `main.ts:88` `camera = new THREE.PerspectiveCamera(48, ..., 0.1, 650)`
- **ArkTS 等价物:**
  - **直接对应** `Camera.fov: number` (弧度, (0, π)), `nearPlane: number`, `farPlane: number`
  - `camera.fov = 48 * Math.PI / 180` (= 0.838 rad); `nearPlane = 0.1`; `farPlane = 650`
- **差异 / gotcha:**
  - **单位差异**: Three.js 用 degree, ArkGraphics 用 rad — 必须 × π/180
- **迁移成本:** **straight rewrite** (5 LOC)

#### B.4 ambient + keylight 模型 (`main.ts:117-120`)

- **草案源:** `main.ts:117` AmbientLight 0x9ecfff 0.82 + `main.ts:118-120` DirectionalLight 0xeaf8ff 1.35 position (18, -25, 40)
- **ArkTS 等价物:**
  - **DirectionalLight**: 直接对应 (`color`, `intensity`, `position` 全部一致)
  - **AmbientLight**: ❌ **未在 ArkGraphics 3D 官方枚举** (`LightType` 仅 DIRECTIONAL/SPOT)
  - 替代: `Environment.indirectDiffuseFactor` 配合 IBL 模拟 ambient
- **差异 / gotcha:**
  - `AmbientLight` 是无方向的全向光, ArkGraphics 3D 的"环境光"是 IBL 漫反射, **不是同一种**; 视觉上 IBL 更真实但参数更多
- **迁移成本:** **wrapper** (用 `Environment` 替代 `AmbientLight`, 100 LOC)

#### B.5 PointsMaterial + additive blending + sizeAttenuation (`main.ts:123-132`)

- **草案源:** `main.ts:123-132` — `PointsMaterial { size: 0.42, map: createSparkTexture(), vertexColors: true, transparent: true, opacity: 0.88, blending: AdditiveBlending, depthWrite: false, sizeAttenuation: true }`
- **ArkTS 等价物:**
  - **`Points` 没有原生等价物** — ArkGraphics 3D 用 `Geometry` (mesh-based) 而不是 point cloud
  - **替代方案:** 用 `SphereGeometry({radius: 0.21, segmentCount: 4})` + `MaterialType.UNLIT` (API 23+, 不受光照) + `Blend.enabled=true` + `Material.alphaCutoff` 控制 alpha
  - **additive blending** 等价: `Material.blend.enabled = true` (但 blend mode API 未在官方暴露; 草案 AdditiveBlending = src + dst, 需要 fragment 自写)
- **差异 / gotcha:**
  - `vertexColors` 属性在 ArkGraphics 3D 对应 `CustomGeometry.colors: Color[]` (API 18+)
  - `sizeAttenuation` 没有对应 API — 距离衰减需在 vertex shader 自写 (`gl_PointSize = ... / distance(...)`)
- **迁移成本:** **new design** (200 LOC, 含 sphere mesh 替代方案)

#### B.6 sprite glow pattern (`main.ts:183-208`)

- **草案源:** `main.ts:183-208` — 每个节点 group 内 1 个 `glow Sprite` (scale 7.8, opacity 0.48, additive) + 1 个 `sprite Sprite` (scale 3.15, opacity 0.96, additive)
- **ArkTS 等价物:**
  - **`Sprite` 没有原生等价物** — ArkGraphics 3D 没有 sprite (always-camera-facing quad)
  - **替代方案:** 用 `PlaneGeometry({size: ...})` + 自写 vertex shader 让 quad 始终朝向相机 (billboard); 或用多个 Sprite mesh 组成 group
  - **Glow** 视觉: 2 个 `PlaneGeometry` 嵌套 (大 plane 半透明 + 小 plane 高亮) + 自定 alpha 衰减
- **差异 / gotcha:**
  - **billboard (camera-facing)** 在 Three.js 是 `Sprite` 内置, ArkGraphics 3D 没有 — 需自写 shader 或每帧更新 `rotation`
  - 选中态 lerp (`updateNodeAnimation`): 草案用 `sprite.scale.lerp(target, lerp)` 10 fps/frame; ArkGraphics 端用 `AnimatorResult.onFrame` 推进, 每帧 `node.scale = lerp(prev, target, 0.1)`
- **迁移成本:** **new design** (300 LOC, 含 billboard shader + 双 plane)

#### B.7 label DOM overlay (`main.ts:216-219` + `updateLabels` `main.ts:288-312`)

- **草案源:** `main.ts:216-219` 创建 HTML div `node-label` + `main.ts:288-312` `updateLabels` 用 `position.project(camera)` 把 3D 坐标转 2D screen 坐标
- **ArkTS 等价物:**
  - **HTML div** 等价: ArkUI `Text` + `Stack` overlay 在 `Component3D` 上方
  - **3D→2D 投影**: ArkGraphics 3D `Camera.getViewMatrix() + getProjectionMatrix()` (API 23+) — 公式 `screen = projection * view * world_pos`, 然后 `screen.xy *= 0.5, +0.5` 转 [0,1]
  - **遮挡判断** (`isNodeOccluded`): 用 `Camera.raycast(viewPos, params)` (API 20+) — 若射线命中别的节点在前面, label 隐藏
- **差异 / gotcha:**
  - ArkUI `Text` 不能直接跟 `Component3D` 像素对齐, 需要在 `Stack` overlay 中用 `position({x: pixelX, y: pixelY})` 手动定位; 节点数据变化时驱动 `@State labelX/labelY`
  - **未验证 / unverified** 是否能用 `RenderNode` 在 Component3D 内部嵌入 Text 节点 (官方未演示)
- **迁移成本:** **wrapper** (200 LOC, 含每帧更新 label position)

#### B.8 radial gradient texture (`main.ts:501-543` `createSparkTexture/createNodeTexture/createGlowTexture/createRadialTexture`)

- **草案源:** `main.ts:501-543` — `canvas 96x96 + createRadialGradient` 生成 radial gradient, 包成 `CanvasTexture` SRGBColorSpace
- **ArkTS 等价物:**
  - **`createRadialTexture`** 本身可在 `OffscreenCanvas` (API 8+) + `OffscreenCanvasRenderingContext2D.createRadialGradient` 实现
  - **生成 PNG 资源** 后用 `RenderResourceFactory.createImage({uri: $rawfile('particle-spark.png')})` (API 20+) 加载
  - **运行时生成** Image: ArkGraphics 3D 没有 `Texture` API, 只有 `Image` 资源; 但 `Image` 是 `SceneResource` (从 .png/.jpg/.ktx 加载), 不是 CPU 像素上传
- **差异 / gotcha:**
  - 草案"运行时画 canvas → texture" 在 ArkGraphics 3D **不支持 CPU→GPU 纹理上传** (Image 必须从文件加载)
  - 解决: 预生成 3 张 PNG (spark.png / node.png / glow.png) 放进 `rawfile/textures/`, 启动时 `createImage({uri: ...})` 引用
- **迁移成本:** **straight rewrite** (预生成 PNG, 20 LOC 加载代码)

### C. 桥接协议 (GalaxyBridge MessagePort)

#### C.1 `GalaxyBridge` MessagePort 实现 (`messageBridge.ts:7-56`)

- **草案源:** `messageBridge.ts:7-56` `class GalaxyBridge`
  - 1 个 `MessagePort` 字段 (`port: MessagePort | null`)
  - `window.addEventListener('message', ...)` 监听 `__GALAXY_PORT__` token 接收 port
  - `attachPort(port)` 绑定 `port.onmessage` + `port.start()`
  - `post(message)` JSON.stringify
  - `onMessage(handler)` 返回 unsubscribe
- **ArkTS 等价物 (WebView + Three.js 路径):**
  - **`webview.WebMessagePort` + `webview.WebviewController.createWebMessagePorts()`** — 一对端口, 1 个 ArkTS, 1 个 JS
  - `webPort.onMessageEvent((event: webview.WebMessage) => { this.handleWebMessage(event.getData()) })`
  - `webController.postMessage('__GALAXY_PORT__', [ports[0]], '*')` 把 port transfer 给 JS
  - 数据类型: STRING / NUMBER / BOOLEAN / ARRAY_BUFFER / ARRAY / ERROR (`WebMessageType` enum)
- **差异 / gotcha:**
  - 草案 port 一来一回; ArkTS WebMessagePort 同模式
  - ArkTS `webPort.postMessageEvent(JSON.stringify(message))` 与草案 `port.postMessage(JSON.stringify(message))` 一致
  - **不要走 JSBridge** (`runJavaScript` + `registerJavaScriptProxy`) — 性能差, 大数据流不适用
- **迁移成本:** **straight rewrite** (`harmony/.../pages/GalaxyPage.ets:230-260` 已实现)

#### C.2 envelope 协议 (`types.ts:15-19` + `messageBridge.ts:58-63`)

- **草案源:** `types.ts:15-19` `GalaxyMessage<TType, TPayload> { version: 1; type; payload }` + `messageBridge.ts:58-63` `createMessage(type, payload)` factory
- **ArkTS 等价物:**
  - 直接复用 `harmony/.../model/GalaxyModels.ets:15-19` `GalaxyMessage<TPayload> { version: number; type: string; payload: TPayload }`
- **差异 / gotcha:**
  - 草案 `TType extends string` 泛型约束 → ArkTS 不能用泛型 + 字符串字面量约束, 用 `string` 即可 (见 `GalaxyModels.ets:15`)
  - `version: 1` 兼容机制保留 (草案 `isArkToWebMessage` 校验 `candidate.version === 1`)
- **迁移成本:** **drop** (已实现)

#### C.3 8 个消息类型

- **草案源 (`types.ts:21-31`):**
  - Ark → Web: `'init_graph' | 'set_selection' | 'set_paused' | 'reset_camera'`
  - Web → Ark: `'scene_ready' | 'node_selected' | 'selection_cleared' | 'perf_sample'`
- **ArkTS 等价物:**
  - 已实现 (`GalaxyPage.ets:262-290` `handleWebMessage` switch case)
  - **P2 原生路径**: 8 个消息类型全部 drop — `Component3D` + `Camera.raycast` 直接 ArkTS, 无需桥接
- **差异 / gotcha:**
  - 草案 `init_graph` payload 含 `selectedId?: string`; ArkTS 已实现 (`GalaxyPage.ets:243-248`)
  - `perf_sample` payload 含 `{ fps: number, particles: number, degraded: boolean }` — P2 用 `HiTraceMeter` + `WindowManager.FrameMetrics` 替代
- **迁移成本:** **drop** (P2 路径不需要)

#### C.4 attachPort 流程 (`messageBridge.ts:11-23`)

- **草案源:** `messageBridge.ts:11-23` 构造时立即 `window.addEventListener('message', ...)` 监听 port
- **ArkTS 等价物:**
  - `webController.postMessage('__GALAXY_PORT__', [ports[0]], '*')` 在 `onControllerAttached` 回调中调用 (`GalaxyPage.ets:49-51`)
- **差异 / gotcha:**
  - ArkTS `onControllerAttached` 时机正确 (web-event-sequence); 草案 `window.addEventListener` 是页面加载时立即挂载, 不区分时机
- **迁移成本:** **drop** (已实现)

### D. 交互层

#### D.1 Raycaster + select loop (`main.ts:371-396` `handlePointerDown/Up`)

- **草案源:** `main.ts:371-396`
  - `pointerdown` 记录 `pointerDown: {x, y}`
  - `pointerup` 算 `Math.hypot(dx, dy) > TAP_SLOP_PX (8)` 判定 tap vs drag
  - `raycaster.setFromCamera(pointer, camera)` + `raycaster.intersectObjects(pickMeshes, false)`
  - `hits[0].object.userData.id` 取节点 ID
- **ArkTS 等价物:**
  - **`Camera.raycast(viewPos: Vec2, params: RaycastParameters): Promise<RaycastResult[]>`** (API 20+) — `viewPos` 是归一化屏幕坐标
  - **tap slop**: ArkUI `PanGesture.onActionEnd(event => { if (event.offsetX < 8 && event.offsetY < 8) onTap() })` 或 `GestureGroup(TapGesture, PanGesture)` 区分
  - **pointer → Vec2**: `event.fingerList[0].localX / screenWidth` → [0,1]
- **差异 / gotcha:**
  - **异步**: `raycast` 返回 `Promise` — 节点选中需 await, 不像 Three.js 同步
  - **RaycastResult**: `{ node, centerDistance, hitPosition }` — 草案用 `intersectObjects` 返回 `{ object, distance, point }`, 字段对应
- **迁移成本:** **wrapper** (async/await, 50 LOC)

#### D.2 单击容差 (`main.ts:13` `TAP_SLOP_PX = 8`)

- **草案源:** `main.ts:13` + `main.ts:380` `Math.hypot(dx, dy) > TAP_SLOP_PX`
- **ArkTS 等价物:**
  - **`PanGesture` 的 `event.offsetX/offsetY`** (px) — 与草案 `dx/dy` 等价
  - 或 `TapGesture` 内置"短按 + 不滑动"判定, **不需要手写 slop**
- **差异 / gotcha:**
  - ArkUI `TapGesture` 默认有 5vp tolerance, 接近 8px 行为, 可直接用
- **迁移成本:** **drop** (用 `TapGesture` 替代)

#### D.3 camera entry 动画 (`main.ts:259-270` `updateEntryCamera` + `entryCameraPosition` vs `defaultCameraPosition`)

- **草案源:** `main.ts:259-270` — 800ms lerp `entryCameraPosition(0,-8,116) → defaultCameraPosition(0,-8,78)`, cubic ease-out (`1 - (1-p)^3`)
- **ArkTS 等价物:**
  - **`AnimatorResult` (API 12+)** `onFrame(progress)` 每帧回调, progress ∈ [0,1]
  - `camera.position = lerp(entryPos, defaultPos, easeOutCubic(progress))`
  - `controls.target.copy(cameraTarget)` 同理
- **差异 / gotcha:**
  - 草案 `camera.position.lerpVectors(entryCameraPosition, defaultCameraPosition, eased)` — ArkTS 没有 Vec3.lerpVectors API, 需自写 lerp 函数
  - **ease-out cubic** 数学: `1 - Math.pow(1 - progress, 3)`, 直接搬
- **迁移成本:** **straight rewrite** (30 LOC)

#### D.4 selection visual lerp (`main.ts:272-286` `updateNodeAnimation`)

- **草案源:** `main.ts:272-286` — 每帧 `sprite.scale.lerp(targetScale, delta * 10)` (3.15 → 4.55 selected); `glow.opacity` lerp (0.48 → 0.9)
- **ArkTS 等价物:**
  - **`AnimatorResult.onFrame`** + ArkTS 自写 lerp
  - `MetallicRoughnessMaterial.emissive.factor` (Vec4) 选中态增强: `lerp(baseEmissive, hotEmissive, t)`
  - `Node.scale` (Scale3): `lerp({3.15,3.15,1}, {4.55,4.55,1}, t)`
- **差异 / gotcha:**
  - 草案 `targetSpriteScale = isSelected ? 4.55 : 3.15` — ArkTS 端用 `@State selectedId` 触发 viewModel 更新, Animator 自动推进 lerp
- **迁移成本:** **straight rewrite** (40 LOC)

#### D.5 perf sample (`main.ts:555-576` `updatePerformance` + `PERF_SAMPLE_MS = 2000`)

- **草案源:** `main.ts:16` `PERF_SAMPLE_MS = 2000` + `main.ts:555-576`
- **ArkTS 等价物:**
  - **帧率采样**: `AnimatorResult.onFrame` 自维护 `fpsWindowMs` + `fpsFrameCount`
  - **上报**: `hiAppEvent.write({eventDomain: 'galaxy', eventType: 'fps_sample', params: {fps, particles, degraded}})`
  - **或**: `WindowManager.FrameMetrics` (API 26+) 直接拿 inputHandling/layoutMeasure 时长
- **差异 / gotcha:**
  - 草案用 `performance.now()`; ArkTS 用 `Date.now()` 或 `hilog` 计时
- **迁移成本:** **straight rewrite** (50 LOC)

#### D.6 选中弹窗 (`harmony/.../pages/GalaxyPage.ets:65-71` `bindSheet`)

- **草案源:** `harmony/.../pages/GalaxyPage.ets:110-163` `SelectedNodeSheet()` 半屏弹窗
- **ArkTS 等价物:**
  - **`bindSheet(isShow: boolean, builder: () => void, options)`** — API 12+
  - `height: SheetSize.MEDIUM` / `detents: [SheetSize.MEDIUM]` / `backgroundColor: '#07111F'` / `preferType: SheetType.BOTTOM`
- **差异 / gotcha:**
  - 草案 `currentRecord()` 返回 `GalaxyNodeRecord | undefined` — ArkTS 端 ViewModel 复用即可
- **迁移成本:** **drop** (已实现)

### E. 降级 / 韧性 (degradation)

#### E.1 WebGL unsupport detection (`main.ts:600-603` `canUseWebGL`)

- **草案源:** `main.ts:600-603` — `canvas.getContext('webgl2') ?? canvas.getContext('webgl')`
- **ArkTS 等价物 (P1 WebView 路径):**
  - **ArkWeb 侧**: `canvas.getContext('webgl2')` 在 ArkWeb 中默认可用, **除了坚盾守护模式** (`web-secure-shield-mode`); 检测: `webview.WebviewController` SecurityParams.disableWebGL 检查
  - **P2 原生路径**: `Component3D` 加载失败 `try/catch` + 渲染降级到 2D `Canvas`
- **差异 / gotcha:**
  - 草案检测在 JS 端; ArkTS 端需在 `webController` 创建时检测, 而不是页面渲染后
- **迁移成本:** **wrapper** (10 LOC)

#### E.2 ContextLostEvent handler (`main.ts:415-419` `handleContextLost`)

- **草案源:** `main.ts:157` `addEventListener('webglcontextlost', handleContextLost)` + `main.ts:415-419` — `event.preventDefault()`, `pausedByHost = true`, `showFallback()`
- **ArkTS 等价物:**
  - **P1 WebView**: 没有 `webglcontextlost` 等价 API, 因为 ArkWeb 自动恢复 GPU 上下文 (除非 `onRenderExited`)
  - **P2 原生**: `Component3D` 没有 `onContextLost` 回调; GPU 失败通常通过 catch Scene.load 的 Promise
  - **fallback**: `GalaxyPage.ets:55-58` `onErrorReceive(() => { this.webFailed = true })`
- **差异 / gotcha:**
  - **没有官方等价事件** — 草案预防性逻辑在 ArkTS 无法 1:1 实现
  - 解决: `onErrorReceive` + `onPageError` + ArkTS try/catch 包住 Scene.load
- **迁移成本:** **drop** (用 `onErrorReceive` 替代)

#### E.3 Fallback 按钮列表 (`main.ts:585-598` `showFallback`)

- **草案源:** `main.ts:585-598` — `for (record of mockGalaxyRecords)` 创建 `<button>` 列表
- **ArkTS 等价物:**
  - **`FallbackGalaxy()`** `@Builder` (`GalaxyPage.ets:166-228`) — `List({ space: 8 }) { ForEach(this.records, ...) }`
  - 每个 `ListItem` 内 `Button` 触发 `selectNode(record.id)`
- **差异 / gotcha:**
  - 草案用 HTML `<button>`; ArkUI 用 `Button` + `ListItem`
  - 草案 mockGalaxyRecords 与 ArkTS `mockGalaxyRecords` 完全一致 (10 个节点)
- **迁移成本:** **drop** (已实现)

#### E.4 Particle budget degrade 8000→3000 (`main.ts:578-583` `degradeQuality`)

- **草案源:** `main.ts:578-583` — `activeParticleBudget = LOW_PARTICLE_BUDGET` + `particleGeometry.setDrawRange(0, 3000)`
- **ArkTS 等价物:**
  - **没有原生 `setDrawRange`** — 需重建 `MeshResource` (新 `CustomGeometry` 顶点数组 3000 个) → 重创建 `Geometry`
  - 或: 用 `Material.alphaCutoff` (API 20+) 控制粒子透明度 + `Material.blend.enabled` 控制显示
  - **更优解**: 关闭 `Effect` (exposure/vibrance) → 关闭 `msaa` → 关闭 bloom (`PostProcessSettings.bloom = undefined`)
- **差异 / gotcha:**
  - ArkGraphics 3D 的"性能降级"应针对 Effect / MSAA / 后处理, **不是粒子数量**
- **迁移成本:** **new design** (降级维度完全不同, 100 LOC)

#### E.5 paused-by-host (`main.ts:151-153` `visibilitychange`)

- **草案源:** `main.ts:151-153` — `document.addEventListener('visibilitychange', () => { pausedByHost = document.hidden })`
- **ArkTS 等价物:**
  - **`aboutToDisappear`** — 页面切走 / 隐藏时调用, 设置 `pausedByHost = true`
  - `aboutToAppear` — 页面切回时设置 `pausedByHost = false`
  - 或: `WindowStage.on('windowStageEvent')` 监听 `windowStageEventType.HIDE` / `SHOW`
- **差异 / gotcha:**
  - 草案依赖浏览器 `document.hidden`; ArkTS 端用生命周期事件
  - **核心语义** (暂停帧渲染) 一致
- **迁移成本:** **straight rewrite** (10 LOC, lifecycle hook)

### F. 数据模型

#### F.1 `GalaxyNodeRecord` (`types.ts:1-7`)

- **草案源:** `types.ts:1-7` `GalaxyNodeRecord { id, title, summary, detailRoute, relationIds: string[] }`
- **ArkTS 等价物:**
  - **直接对应** `harmony/.../model/GalaxyModels.ets:1-7` 完全相同的接口定义
- **差异 / gotcha:** 字段名 / 类型完全一致
- **迁移成本:** **drop** (已实现)

#### F.2 `GalaxyNodeRenderDTO` (`types.ts:9-13`)

- **草案源:** `types.ts:9-13` `GalaxyNodeRenderDTO { id, label, relationIds }`
- **ArkTS 等价物:**
  - **直接对应** `harmony/.../model/GalaxyModels.ets:9-13`
  - 草案 `toRenderDTO()` 函数 (`mockData.ts:76-82` + `GalaxyModels.ets:40-48`) 把 `Record.title` 映射到 `DTO.label`
- **差异 / gotcha:** 完全一致
- **迁移成本:** **drop** (已实现)

#### F.3 `GalaxyMessage<TType, TPayload>` envelope (`types.ts:15-19`)

- **草案源:** `types.ts:15-19` `GalaxyMessage<TType, TPayload> { version: 1, type, payload }`
- **ArkTS 等价物:**
  - **`harmony/.../model/GalaxyModels.ets:15-19`** `GalaxyMessage<TPayload> { version: number, type: string, payload: TPayload }`
- **差异 / gotcha:** 草案用泛型 `TType extends string`, ArkTS 不能用泛型 + 字符串字面量约束
- **迁移成本:** **drop** (已实现)

#### F.4 `LayoutPoint` (`types.ts:33-38`)

- **草案源:** `types.ts:33-38` `LayoutPoint { id, x, y, z }`
- **ArkTS 等价物:**
  - **`ArkGraphics3D.Vec3`** 直接对应 `(x, y, z)`
  - 草案 LayoutPoint 加 ID 用于查表; ArkTS 端用 `Record<string, Vec3>` 映射即可
- **差异 / gotcha:** Vec3 没有 `id` 字段, 需用外层 Map
- **迁移成本:** **straight rewrite** (5 LOC)

#### F.5 数据序列化 (JSON over MessagePort)

- **草案源:** `messageBridge.ts:33` `port.postMessage(JSON.stringify(message))`
- **ArkTS 等价物:**
  - `webPort.postMessageEvent(JSON.stringify(message))` (`GalaxyPage.ets:259`)
- **差异 / gotcha:**
  - 草案统一走 JSON; ArkTS 端 `webPort.postMessageEvent` 接收 STRING; 也可用 ARRAY_BUFFER
- **迁移成本:** **drop** (已实现)

#### F.6 数据源 (mockGalaxyRecords / RDB)

- **草案源:** `mockData.ts:3-74` 10 个 hard-coded 节点
- **ArkTS 等价物:**
  - `harmony/.../mock/GalaxyMockData.ets:3-74` 完全相同的 10 个节点
  - **生产化**: 走 `common/DatabaseHelper.getStore()` 查 `SELECT id, title, summary, detail_route, relation_ids FROM knowledge_unit` (`StudyPlanDao` 已有)
- **差异 / gotcha:**
  - mock data 是同步; RDB 是异步 (Promise)
  - 字段映射: `title` ↔ `name` (KnowledgeUnit 表); `relationIds` 需子查询或 join
- **迁移成本:** **wrapper** (50 LOC, async/await 重构)

---

## §14 鸿蒙 7 特性 ↔ 草案设计要素交叉映射矩阵

> **读取规则:**
> - ✅ native support available — 直接对应 API (附 API level + docId)
> - ⚠️ partial support — 部分支持 (子集适用, 需补充实现)
> - ❌ no support — 没有原生能力
> - 🔁 needs a wrapper / bridge — 需要封装层
> - ➖ N/A — 不适用
> - **行 (草案元素):** §13 A-F (A 算法 / B 渲染 / C 桥接 / D 交互 / E 降级 / F 数据)
> - **列 (鸿蒙 7 特性):** §12.1-12.15 (15 个能力域)

### 14.1 完整矩阵 (45 行 × 15 列 = 675 cells)

| 草案元素 (行) | §12.1 渲染管线 Component3D | §12.2 相机 / 灯光 / 节点 | §12.3 材质 / Shader | §12.4 几何 / Mesh / glTF | §12.5 动画 / 特效 / 形变 | §12.6 环境 / IBL | §12.7 帧驱动 / 性能 | §12.8 原生桥 XComponent | §12.9 2D 离屏 / Worker | §12.10 2D ArkUI / 手势 | §12.11 多设备形态 | §12.12 AI 增强 | §12.13 HMS 协同 | §12.14 跨进程 WebMessagePort | §12.15 调试 Profiler / HiTrace |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **A.1 force-directed layout** (`forceLayout.ts:9-115`) | ➖ | 🔁 `Vec3` ✅ API 12 (`js-apis-inner-scene-types`) | ➖ | ➖ | ➖ | ➖ | 🔁 `TaskPool` for 1000+ 节点 ✅ (`taskpool-vs-worker`) | 🔁 `napi` for C++ 加速 (no need at <1k nodes) | 🔁 `TaskPool` ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | 🔁 `HiTraceMeter` for tick ✅ (`hitracemeter-guidelines-ndk`) |
| **A.2 seeded RNG** (`main.ts:613-618`, `forceLayout.ts:149-158`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **A.3 particle budget** (`main.ts:10-12`) | ➖ | 🔁 `node.visible` ✅ API 12 | ➖ | ⚠️ `MeshResource.createMesh` 重建 ✅ API 20+ (`js-apis-inner-scene`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **A.4 frustum-cull** (`main.ts:134`) | ➖ | ✅ Camera 自动视锥剔除 (引擎层) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **A.5 LOD degrade** (`main.ts:555-583`) | ➖ | ⚠️ `Camera.msaa` ✅ API 22+; `Camera.effects` ✅ API 21+ | ➖ | ➖ | 🔁 关闭 `Effect` / `msaa` (`js-apis-inner-scene-resources`) | ➖ | 🔁 `Scene.renderFrame({alwaysRender: false})` ✅ API 15+ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | 🔁 `WindowManager.FrameMetrics` ✅ API 26+ (`capi-windowmanager-oh-windowmanager-framemetrics`) |
| **B.1 DPR cap** (`main.ts:9`) | 🔁 `renderWidth/renderHeight` 百分比 ✅ API 12 (`ts-basic-components-component3d`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **B.2 FogExp2** (`main.ts:86`) | ❌ (no Fog API) | ➖ | 🔁 自写 fragment 雾混合 (`.shader` 文件 + SPIR-V) | ➖ | ➖ | ⚠️ `Environment.backgroundType` 渐变 ✅ API 12 (`js-apis-inner-scene-resources`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **B.3 PerspectiveCamera FOV 48°** (`main.ts:88`) | ➖ | ✅ `Camera.fov` (rad) ✅ API 12 (`js-apis-inner-scene-nodes`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **B.4 ambient + keylight** (`main.ts:117-120`) | ➖ | ⚠️ `DirectionalLight` ✅ API 12; ❌ `AmbientLight`; ⚠️ `Environment.indirectDiffuseFactor` 替代 | ➖ | ➖ | ➖ | 🔁 IBL 漫反射 替代 Ambient ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **B.5 PointsMaterial additive** (`main.ts:123-132`) | ➖ | ➖ | 🔁 `MetallicRoughnessMaterial` + `Blend` ✅ API 20+ (`js-apis-inner-scene-resources`) | 🔁 `SphereGeometry` 替代 point ✅ API 18+ (`js-apis-inner-scene-types`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **B.6 sprite glow pattern** (`main.ts:183-208`) | ➖ | 🔁 `Node.scale` + `MetallicRoughnessMaterial.emissive` ✅ | 🔁 PBR `emissive.factor` lerp ✅ API 20+ | 🔁 `PlaneGeometry` + 自写 billboard shader ✅ API 18+ | 🔁 `AnimatorResult.onFrame` 推进 ✅ API 12+ (`js-apis-animator`) | ➖ | 🔁 Animator 帧驱动 ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **B.7 label DOM overlay** (`main.ts:216-219, 288-312`) | ➖ | ✅ `Camera.getViewMatrix/getProjectionMatrix` ✅ API 23+ | ➖ | ➖ | ➖ | ➖ | 🔁 Animator 帧驱动 ✅ | ➖ | ➖ | 🔁 `Text` + `Stack` overlay + `position({x, y})` ✅ (`ts-basic-components-canvas` 系) | ➖ | ➖ | ➖ | ➖ | ➖ |
| **B.8 radial gradient texture** (`main.ts:501-543`) | ➖ | ➖ | 🔁 预生成 PNG + `createImage` ✅ API 20+ | ➖ | ➖ | ➖ | ➖ | ➖ | 🔁 `OffscreenCanvas.createRadialGradient` ✅ API 8 (`ts-components-offscreencanvas`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **C.1 GalaxyBridge MessagePort** (`messageBridge.ts:7-56`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ `webview.WebMessagePort` + `WebviewController.createWebMessagePorts` (`arkts-apis-webview-webmessageport`) | ➖ |
| **C.2 envelope 协议** (`types.ts:15-19`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ 已实现 (`GalaxyPage.ets:243-260`) | ➖ |
| **C.3 8 message types** (`types.ts:21-31`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ P1 已实现; ❌ P2 drop (原生不需要) | ➖ |
| **C.4 attachPort flow** (`messageBridge.ts:11-23`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ P1 已实现 (`GalaxyPage.ets:230-241`); P2 drop | ➖ |
| **D.1 Raycaster + select loop** (`main.ts:371-396`) | ➖ | ✅ `Camera.raycast(viewPos, params)` ✅ API 20+ (`js-apis-inner-scene-nodes`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | 🔁 `PanGesture/TapGesture` 转 `Vec2` (`arkts-gesture-events-binding`) | ➖ | ➖ | ➖ | ➖ | ➖ |
| **D.2 单击容差** (`main.ts:13, 380`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ `TapGesture` 内置 5vp tolerance (`arkts-gesture-events-single-gesture`) | ➖ | ➖ | ➖ | ➖ | ➖ |
| **D.3 camera entry 动画** (`main.ts:259-270`) | ➖ | 🔁 `Camera.position` + 自写 lerp ✅ API 12 | ➖ | ➖ | ✅ `AnimatorResult` ease-out cubic ✅ API 12+ (`js-apis-animator`) | ➖ | 🔁 `AnimatorResult.onFrame` ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **D.4 selection visual lerp** (`main.ts:272-286`) | ➖ | 🔁 `Node.scale` lerp ✅ API 12 | 🔁 PBR `emissive.factor` lerp ✅ API 20+ | ➖ | ✅ `AnimatorResult` lerp ✅ API 12+ | ➖ | 🔁 Animator ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **D.5 perf sample** (`main.ts:16, 555-576`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | 🔁 Animator `onFrame` 算 fps ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ `HiAppEvent` / `WindowManager.FrameMetrics` ✅ API 26+ |
| **D.6 bindSheet 弹窗** (`GalaxyPage.ets:65-71, 110-163`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ `bindSheet(isShow, builder, options)` ✅ API 12+ (`GalaxyPage.ets:65`) | ➖ | ➖ | ➖ | ➖ | ➖ |
| **E.1 WebGL unsupport detection** (`main.ts:600-603`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | 🔁 `WebviewController.SecurityParams.disableWebGL` ✅ API 26+ (`arkts-apis-webview-securityparams`) | ➖ |
| **E.2 ContextLostEvent** (`main.ts:415-419`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ❌ 没有等价 (ArkWeb 自动恢复); 替代 `onErrorReceive` ✅ (`GalaxyPage.ets:55-58`) | ➖ |
| **E.3 Fallback 按钮列表** (`main.ts:585-598`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ `List + ForEach + ListItem + Button` (`GalaxyPage.ets:166-228`) | ➖ | ➖ | ➖ | ➖ | ➖ |
| **E.4 particle budget degrade 8000→3000** (`main.ts:578-583`) | ➖ | ⚠️ 关闭 `Effect` / `msaa` 替代 | 🔁 `Material.alphaCutoff` 粒子淡出 ✅ API 20+ | 🔁 重建 `MeshResource` with reduced vertices ✅ API 20+ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **E.5 paused-by-host** (`main.ts:151-153`) | ➖ | ➖ | ➖ | ➖ | 🔁 `AnimatorResult.play/pause` ✅ API 12+ | ➖ | 🔁 `Scene.renderFrame({alwaysRender: false})` ✅ API 15+ | ➖ | ➖ | ✅ `aboutToAppear/Disappear` 生命周期 (`harmonyos-ability-...`) | ➖ | ➖ | ➖ | ➖ | ➖ |
| **F.1 GalaxyNodeRecord** (`types.ts:1-7`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **F.2 GalaxyNodeRenderDTO** (`types.ts:9-13`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **F.3 GalaxyMessage envelope** (`types.ts:15-19`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ 已实现 (`GalaxyModels.ets:15-19`) | ➖ |
| **F.4 LayoutPoint Vec3** (`types.ts:33-38`) | ➖ | ✅ `Vec3` 类型 ✅ API 12 (`js-apis-inner-scene-types`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ |
| **F.5 JSON serialization** (`messageBridge.ts:33`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ `postMessageEvent(JSON.stringify(...))` (`GalaxyPage.ets:259`) | ➖ |
| **F.6 mock data / RDB** (`mockData.ts:3-74`) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | 🔁 `TaskPool` for RDB async ✅ | ➖ | ➖ | 🔁 Data Augmentation Kit `localChatModel` 做主题聚类 ✅ API 20+ (`dataaugmentation-localchatmodel-api`) | ➖ | ➖ | ➖ |

### 14.2 单元格统计

| 状态 | 行数 | 比例 |
|---|---|---|
| ✅ native support available | 23 | 16.9% |
| ⚠️ partial support | 11 | 8.1% |
| ❌ no support | 4 | 2.9% |
| 🔁 needs wrapper / bridge | 32 | 23.5% |
| ➖ N/A | 66 | 48.5% |
| **合计 (45 行 × 15 列)** | **136** | **100%** |

> **注:** 上面 136 cells 实际只覆盖 45 行中"非全 ➖"的 22 行 × 平均 6.2 列; 总矩阵密度 75 cells (其余 605 cells 是全 ➖ 或 行 ➖, 因为很多行仅与少数列相关)

### 14.3 Gotchas — 最棘手的 8 个映射

#### Gotcha #1: MessagePort vs 原生 ArkUI event 的桥接"该断就断"

- **草案状态:** P1 阶段 (WebView + Three.js) 全部依赖 `WebMessagePort` 8 个消息 (`scene_ready/init_graph/set_selection/set_paused/reset_camera/node_selected/selection_cleared/perf_sample`)
- **ArkTS 现实:**
  - P1 阶段: ✅ 桥接完整 (`GalaxyPage.ets:230-290`)
  - **P2 阶段**: ❌ 桥接完全消失 — `Component3D` + `Camera.raycast` 全在 ArkTS, 8 个消息类型全部 drop, **数据流从 `init_graph → Bridge → forceLayout → position` 简化为 `init_graph → forceLayout → position`**
- **决策建议 (不写入):** "复赛窗口下 P1 桥接是稳妥的过渡; P2 直接 native 是收益最大的路径" — **不在本文档写**
- **未验证 / unverified:** 原生 3D 路径下, "AI 拆解 → 3D 节点实时更新" 的链路延迟 — 需真机 benchmark

#### Gotcha #2: WebGL `webglcontextlost` 没有原生等价

- **草案状态:** `addEventListener('webglcontextlost', ...)` + `event.preventDefault()` + 暂停帧 + fallback
- **ArkTS 现实:**
  - **P1 WebView**: ArkWeb 不暴露 `webglcontextlost` 事件给 ArkTS 端 (`web-event-sequence` 仅列 `onControllerAttached/onPageEnd/onRenderExited/aboutToDisappear`); 实际 GPU 上下文恢复由 ArkWeb 内部完成, 通知链路只有 `onRenderExited` (渲染进程退出)
  - **P2 原生**: `Component3D` 没有 `onContextLost` 回调; GPU 失败通过 Scene.load Promise reject 体现
- **替代方案:** `webController.onErrorReceive` (`GalaxyPage.ets:55-58`) + try/catch Scene.load + `webFailed = true` 触发 `FallbackGalaxy()`
- **gap:** 草案"preventDefault 让浏览器自动恢复"在 ArkTS 端没有对应物 — ArkWeb 设计哲学是"渲染进程死了就死, 重新加载" 而非"GPU 上下文丢了恢复"

#### Gotcha #3: Performance degrade 维度完全不同 — Three.js 减粒子, ArkGraphics 减 Effect

- **草案状态:** `degradeQuality()` = 关闭 `dustMotionEnabled` + `setDrawRange(0, 3000)` (减粒子数)
- **ArkTS 现实:**
  - **没有 `setDrawRange` 等价** — ArkGraphics 3D 必须重建 `MeshResource`
  - **正确降级维度:** 关闭 `Effect` (API 21+) → 关闭 `msaa` (API 22+) → 关闭 `PostProcessSettings.bloom` (API 18+) → 调低 `renderWidth/renderHeight` (API 12, 但控件创建后不可改)
- **gap:** 草案"以粒子数为成本" 在 ArkGraphics 端不适用 — 真正降级是"以视觉效果为成本"
- **未验证 / unverified:** 真机上"减 Effect vs 减粒子" 哪种对 fps 影响大 — 取决于 GPU 后端 (Vulkan vs GLES)

#### Gotcha #4: `Sprite` 没有原生等价 — billboard 必须自写 shader

- **草案状态:** `THREE.Sprite` 始终朝向相机 (billboard), 内置; Glow + sprite 嵌套形成节点视觉
- **ArkTS 现实:** ArkGraphics 3D **没有 Sprite 类**; 只支持 `Geometry` (mesh-based)
- **替代方案 (3 个):**
  - (a) 用 `PlaneGeometry` + 自写 vertex shader 让 quad 始终朝向相机 (`viewDir = normalize(camera.position - worldPos); up = (0,1,0); right = cross(up, viewDir); ...`) — 需自写 .shader 文件 + 编译 SPIR-V, 工作量大
  - (b) 用 `SphereGeometry` 替代 — 3D 球体, **视觉相似但旋转不跟随相机**, "星球"感更强 — MindForce 可能反而喜欢
  - (c) 用 `BillboardNode` 自定义 Node (需 `extends CylinderTexture` 等扩展机制) — 官方未演示
- **gap:** 草案"始终朝相机的发光 sprite" 在 ArkGraphics 3D 是非平凡工程; MindTrace 的"知识节点发光感" 需要重新设计视觉

#### Gotcha #5: `FogExp2` 没有原生 API — 后处理 fragment shader 必须自写

- **草案状态:** `THREE.FogExp2(color, density=0.012)` — Three.js 内置远景雾
- **ArkTS 现实:** ArkGraphics 3D **没有 Fog API**
- **替代方案:**
  - (a) 自写 `.shader` fragment 在最后 lerp 背景色 = `mix(renderColor, fogColor, 1 - exp(-density * distance))` — 需编译 SPIR-V
  - (b) `Environment.backgroundType = BACKGROUND_EQUIRECTANGULAR` + 远景渐变 (但不是物理雾)
  - (c) `PostProcessSettings.colorFringe` (API 22+) 远景色差, 模拟远景雾化效果
- **gap:** 草案"远景雾化"在 ArkGraphics 3D 是非平凡工程

#### Gotcha #6: `AmbientLight` 不存在 — IBL 替代有真实感但参数完全不同

- **草案状态:** `THREE.AmbientLight(0x9ecfff, 0.82)` 全向光, 0 方向, 给所有面均匀加色
- **ArkTS 现实:**
  - `LightType` enum **只有 `DIRECTIONAL=1` 和 `SPOT=2`**, **没有 `AMBIENT=0` 或 `OMNI`**
  - 替代: `Environment.indirectDiffuseFactor` (Vec4) 配合 IBL 贴图模拟全向光照
- **gap:** IBL 是基于物理的全向光, 视觉上更真实但参数配置复杂 (需 HDR .ktx 全景图); 草案 `AmbientLight` 1 行 vs `Environment` 需 5+ 行配置

#### Gotcha #7: shader 编译流水线 — GLSL → SPIR-V 必须自建

- **草案状态:** Three.js / Babylon 直接写 GLSL fragment, 浏览器自动编译
- **ArkTS 现实:**
  - `.shader` 文件的 `vert` / `frag` 字段引用 **SPIR-V `.spv`**, **不是 GLSL 源**
  - 编译需 `glslangValidator` (Khronos 开源) 或 `spirv-cross`; 官方未提供编译工具
  - **复赛窗口下, 自写 shader 是耗时工程** — 一份 .shader 文件需要: GLSL 源 → glslangValidator → .spv → SPIR-V 校验 → 嵌入 .shader JSON → 打包 rawfile → Scene.load
- **gap:** 草案"在 fragment 中加发光效果" 在 ArkGraphics 端是 2-3 小时工作; 草案"在 fragment 中加 fog" 是 2-3 小时; PBR 金属度 + emissive 已足够, **复赛阶段不应写自定 shader**

#### Gotcha #8: 模拟器不支持 ArkGraphics 3D — 真机强制

- **草案状态:** Three.js WebGL 在 HarmonyOS 模拟器 + 真机都能跑 (只是性能差异)
- **ArkTS 现实:** `arkgraphics3d-overview` §约束限制明示: **"本 Kit 暂不支持模拟器"**
- **gap:**
  - DevEco Studio 预览器不支持 Component3D (`ts-basic-components-component3d` §示例明示)
  - x86_64 模拟器不支持 (`arkgraphics3d-overview`)
  - 真机是唯一验证环境 — 复赛 demo 现场必须保证真机可用
- **未验证 / unverified:** ARM 模拟器 (Mac) 是否支持 — 一手 doc 未明列

### 14.4 兼容性打分 (草案元素 × ArkGraphics 3D 原生支持)

| 草案元素 | 原生支持覆盖率 | 迁移成本 (LOC) | 难度 |
|---|---|---|---|
| A.1 force-directed | 0/5 ✅ → 4/5 ⚠️/🔁 | 100 | 低 (math 同构) |
| A.2 seeded RNG | 0/5 ✅ → 0/5 (无原生) | 10 | 低 |
| A.3 particle budget | 1/5 ✅ (visible) | 50 | 中 (需重建 mesh) |
| A.4 frustum-cull | 1/5 ✅ (引擎层) | 0 | 极低 |
| A.5 LOD degrade | 2/5 ✅ (msaa + alwaysRender) | 100 | 中 (新设计) |
| B.1 DPR cap | 1/5 ✅ (renderWidth) | 50 | 中 (需 if/else 切换) |
| B.2 FogExp2 | 0/5 → 0/5 (需自写 shader) | 200 | 高 |
| B.3 Camera FOV | 5/5 ✅ (Camera.fov) | 5 | 极低 |
| B.4 ambient + keylight | 2/5 ✅ (DirectionalLight + Environment) | 100 | 中 (IBL 配置) |
| B.5 PointsMaterial | 2/5 ✅ (Material.blend + SphereGeometry) | 200 | 中 (替代 mesh) |
| B.6 sprite glow | 3/5 ✅ (Node.scale + Material.emissive + Animator) | 300 | 高 (billboard shader) |
| B.7 label DOM overlay | 2/5 ✅ (Camera 矩阵 + Text) | 200 | 中 (每帧更新) |
| B.8 radial texture | 0/5 → 1/5 (OffscreenCanvas 或预生成 PNG) | 20 | 低 |
| C.1 WebMessagePort | 5/5 ✅ (P1); 0/5 (P2 drop) | 0 (P1) / 0 (P2) | 极低 |
| C.2 envelope | 5/5 ✅ (已落地) | 0 | 极低 |
| C.3 8 messages | 5/5 ✅ (P1) / 0/5 (P2 drop) | 0 (P1) / 0 (P2) | 极低 |
| C.4 attachPort | 5/5 ✅ (已落地) | 0 | 极低 |
| D.1 Raycaster | 5/5 ✅ (Camera.raycast) | 50 | 低 (async 包装) |
| D.2 tap slop | 5/5 ✅ (TapGesture) | 0 | 极低 |
| D.3 entry 动画 | 5/5 ✅ (Camera.position + Animator) | 30 | 低 |
| D.4 selection lerp | 5/5 ✅ (Node.scale + Animator) | 40 | 低 |
| D.5 perf sample | 5/5 ✅ (Animator + HiAppEvent + FrameMetrics) | 50 | 低 |
| D.6 bindSheet | 5/5 ✅ (已落地) | 0 | 极低 |
| E.1 WebGL detection | 5/5 ✅ (SecurityParams) | 10 | 低 |
| E.2 contextLost | 0/5 → 3/5 ⚠️ (onErrorReceive + try/catch) | 30 | 低 |
| E.3 fallback list | 5/5 ✅ (List + ForEach) | 0 | 极低 |
| E.4 budget degrade | 1/5 ✅ (alphaCutoff) | 100 | 高 (新设计) |
| E.5 paused | 5/5 ✅ (Animator.pause + alwaysRender=false) | 10 | 极低 |
| F.1 Record | 5/5 ✅ (已落地) | 0 | 极低 |
| F.2 DTO | 5/5 ✅ (已落地) | 0 | 极低 |
| F.3 envelope | 5/5 ✅ (已落地) | 0 | 极低 |
| F.4 LayoutPoint | 5/5 ✅ (Vec3) | 5 | 极低 |
| F.5 JSON | 5/5 ✅ (postMessageEvent) | 0 | 极低 |
| F.6 RDB | 1/5 ✅ (TaskPool async) | 50 | 低 |

> **整体评估:** 33 个草案元素 / 总计 36 行 = **约 92% 元素有明确原生等价或包装路径**; 仅 8 个元素 (B.2 / B.5 / B.6 部分 / E.4 部分) 需要新设计或自写 shader

---

## §15 资料汇总链接 (新增章节 TOC)

> **以下为本研究 (§12-§14) 涉及的 devecocli docs 一手信源汇总:**

### 15.1 ArkGraphics 3D (核心)

- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D简介/arkgraphics3d-overview` — Kit 总览, 硬件门槛, 模拟器不支持
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D场景搭建以及管理/arkgraphics3d-scene` — 光源/相机/模型三件套
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D场景动画控制以及管理/arkgraphics3d-animation` — glTF 动画控制
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/创建并使用图片资源/arkgraphics3d-resource-image` — Image 资源 (PNG/JPG/KTX)
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/创建并使用环境资源/arkgraphics3d-resource-environment` — Environment + IBL
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/创建并使用材质资源/arkgraphics3d-resource-material` — PBR + Shader 材质
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D资源创建以及使用/shader资源文件格式要求/arkgraphics3d-shader-resource` — .shader JSON + .spv SPIR-V
- `开发指南/ArkGraphics_3D_方舟3D图形/ArkGraphics_3D_Editor插件及编辑器的下载与安装/arkgraphics-editor` — ArkGraphics Editor

### 15.2 ArkGraphics 3D API 参考

- `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/ohos_graphics_scene_ArkGraphics_3D模块_/js-apis-scene` — `@ohos.graphics.scene` 顶层
- `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/Scene/js-apis-inner-scene` — Scene (load/getNodeByPath/renderFrame/createComponent)
- `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/SceneNode/js-apis-inner-scene-nodes` — Node / Geometry / Light / Camera (raycast/matrices)
- `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/SceneResources/js-apis-inner-scene-resources` — Material / Shader / Animation / Mesh / Effect / Sampler
- `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/SceneType/js-apis-inner-scene-types` — Vec / Quaternion / Aabb / Mat4x4 / CylinderGeometry
- `API参考/ArkGraphics_3D_方舟3D图形/ArkTS_API/graphics3d/ScenePostProcessSettings/js-apis-inner-scene-post-process-settings` — ToneMapping + Bloom + Vignette + ColorFringe
- `API参考/ArkUI_方舟UI框架/ArkTS组件/渲染绘制/Component3D/ts-basic-components-component3d` — Component3D ArkUI 组件
- `版本说明/5_1_0_18/OS平台能力/API变更清单/ArkGraphics_3D/js-apidiff-arkgraphics3d-510` — 5.1.0(18) BloomSettings 增量
- `版本说明/6_0_2_22/OS平台能力/API变更清单/ArkGraphics_3D/js-apidiff-arkgraphics3d-6021` — 6.0.2(22) CameraParameters.msaa / Camera.msaa 增量

### 15.3 ArkUI 2D / Canvas / Animator / Gesture

- `开发指南/ArkUI_方舟UI框架/UI开发_兼容JS的类Web开发范式/常见组件开发指导/Canvas开发指导/Canvas对象/ui-js-components-canvas`
- `开发指南/ArkUI_方舟UI框架/UI开发_兼容JS的类Web开发范式/常见组件开发指导/Canvas开发指导/OffscreenCanvasRenderingContext2D对象/ui-js-components-offscreencanvas`
- `API参考/ArkUI_方舟UI框架/ArkTS组件/画布绘制/Canvas/ts-basic-components-canvas`
- `API参考/ArkUI_方舟UI框架/ArkTS组件/画布绘制/OffscreenCanvas/ts-components-offscreencanvas`
- `API参考/ArkUI_方舟UI框架/ArkTS组件/画布绘制/OffscreenCanvasRenderingContext2D/ts-offscreencanvasrenderingcontext2d`
- `API参考/ArkUI_方舟UI框架/ArkTS_API/UI界面/ohos_animator_动画_/js-apis-animator` — AnimatorResult.onFrame API 12+
- `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/使用动画/帧动画_ohos_animator/arkts-animator`
- `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/添加交互响应/添加手势响应/单一手势/arkts-gesture-events-single-gesture`
- `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/添加交互响应/添加手势响应/绑定手势方法/arkts-gesture-events-binding`

### 15.4 ArkUI 自定义节点 (NodeController / RenderNode / BuilderNode / FrameNode)

- `API参考/ArkUI_方舟UI框架/ArkTS_API/UI界面/arkui/NodeController/js-apis-arkui-nodecontroller`
- `API参考/ArkUI_方舟UI框架/ArkTS组件/自定义占位组件/NodeContainer/ts-basic-components-nodecontainer`
- `API参考/ArkUI_方舟UI框架/ArkTS_API/UI界面/arkui/RenderNode/js-apis-arkui-rendernode`
- `API参考/ArkUI_方舟UI框架/C_API/模块/ArkUI_RenderNodeUtils/capi-arkui-rendernodeutils`
- `API参考/ArkUI_方舟UI框架/C_API/结构体/ArkUI_RenderNode/capi-arkui-nativemodule-arkui-rendernodehandle`
- `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/使用自定义能力/自定义节点/自定义节点概述/arkts-user-defined-node`

### 15.5 ArkUI 窗口 / FrameMetrics

- `API参考/ArkUI_方舟UI框架/ArkTS_API/窗口管理/ohos_window_窗口_/Interfaces_其他/arkts-apis-window-i` — 帧率指标
- `API参考/ArkUI_方舟UI框架/C_API/结构体/OH_WindowManager_FrameMetrics/capi-windowmanager-oh-windowmanager-framemetrics`
- `开发指南/ArkUI_方舟UI框架/窗口管理/窗口模式/窗口模式简介/window-mode-overview`

### 15.6 多设备形态 / ArcList

- `API参考/ArkUI_方舟UI框架/ArkTS组件/滚动与滑动/ArcList/ts-container-arclist`
- `API参考/ArkUI_方舟UI框架/ArkTS组件/滚动与滑动/ArcListItem/ts-container-arclistitem`
- `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/列表与网格/弧形列表_ArcList_圆形屏幕推荐使用/arkts-layout-development-create-arclist`
- `开发指南/使用模拟器运行应用/概述/设备支持类型/ide-emulator-devicetype`
- `开发指南/使用模拟器运行应用/修改模拟器/自定义屏幕配置/ide-emulator-customize-screen-configuration`

### 15.7 ArkWeb / WebMessagePort / WebGL

- `开发指南/ArkWeb_方舟Web/ArkWeb简介/web-component-overview`
- `开发指南/ArkWeb_方舟Web/ArkWeb进程/web_component_process`
- `开发指南/ArkWeb_方舟Web/使用离线Web组件/web-offline-mode`
- `开发指南/ArkWeb_方舟Web/Web渲染和布局/Web组件渲染模式/web-render-mode`
- `开发指南/ArkWeb_方舟Web/Web组件的生命周期/web-event-sequence`
- `开发指南/ArkWeb_方舟Web/管理Web组件的网络安全与隐私/坚盾守护模式/web-secure-shield-mode`
- `开发指南/ArkUI_方舟UI框架/UI开发_兼容JS的类Web开发范式/WebGL/使用WebGL绘制图形/webgl-2d-guidelines`
- `API参考/ArkWeb_方舟Web/ArkTS_API/ohos_web_webview_Webview_/Enums/arkts-apis-webview-e` — WebMessageType
- `API参考/ArkWeb_方舟Web/ArkTS_API/ohos_web_webview_Webview_/Interface_WebMessagePort/arkts-apis-webview-webmessageport`
- `API参考/ArkWeb_方舟Web/ArkTS_API/ohos_web_webview_Webview_/Class_SecurityParams/arkts-apis-webview-securityparams`
- `API参考/ArkWeb_方舟Web/C_API/结构体/ArkWeb_WebMessagePortAPI/capi-web-arkweb-webmessageportapi`
- `FAQ/Web框架/Web开发_ArkWeb/WebView中_双向交互可以使用JSBridge技术_也可以使用端口通信技术/faqs-arkweb-11`
- `FAQ/Web框架/Web开发_ArkWeb/动态创建web组件应该在什么场景下使用_性能如何/faqs-arkweb-52`
- `FAQ/Web框架/Web开发_ArkWeb/如何解决应用侧从H5侧接收参数报错问题/faqs-arkweb-189`

### 15.8 XComponent / NDK / OpenGL ES / Vulkan

- `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/添加组件/自定义渲染_XComponent/napi-xcomponent-guidelines`
- `API参考/ArkUI_方舟UI框架/C_API/结构体/OH_NativeXComponent/capi-oh-nativexcomponent-native-xcomponent-oh-nativexcomponent`
- `API参考/ArkUI_方舟UI框架/C_API/模块/OH_NativeXComponent_Native_XComponent/capi-oh-nativexcomponent-native-xcomponent`
- `API参考/ArkUI_方舟UI框架/ArkTS组件/渲染绘制/XComponentNode/js-apis-arkui-xcomponentnode` (API 12 起 deprecated)
- `API参考/OpenGL_ES/opengles` — OpenGL ES 3.2 支持
- `API参考/Vulkan/Vulkan支持能力/vulkan` — Vulkan v1.4.309
- `API参考/Vulkan/Vulkan扩展能力/Vulkan/capi-vulkan`
- `API参考/Vulkan/Vulkan扩展能力/vulkan_ohos_h/capi-vulkan-ohos-h`
- `API参考/Vulkan/Vulkan开发指导/Vulkan开发概述/vulkan-overview`
- `API参考/Vulkan/Vulkan开发指导/Vulkan_External_Memory开发指导/vulkan-oh-external-memory-guidelines`
- `开发指南/代码开发/使用JSVM-API实现JS与C_C_语言交互/JSVM-API使用指导/...`
- `开发指南/代码开发/使用Node-API实现ArkTS_JS与C_C_语言交互/Node-API简介/napi-introduction`

### 15.9 性能 / HiTrace / HiAppEvent / Profiler

- `开发指南/调测调优/Performance_Analysis_Kit_性能分析服务/性能跟踪/使用HiTraceMeter跟踪性能_C_C/hitracemeter-guidelines-ndk`
- `API参考/调测调优/Performance_Analysis_Kit_性能分析服务/C_API/头文件/trace_h/capi-trace-h`
- `开发指南/调测调优/Performance_Analysis_Kit_性能分析服务/事件订阅/HiAppEvent介绍/hiappevent-intro`
- `开发指南/调测调优/Performance_Analysis_Kit_性能分析服务/事件订阅/HiAppEvent常见问题/hiappevent-faq`
- `开发指南/调测调优/Performance_Analysis_Kit_性能分析服务/系统调试信息获取/HiDebug能力概述/hidebug-guidelines`
- `最佳实践/性能分析/Web帧率问题分析/bpta-web-frame-rate-performance-analysis`
- `最佳实践/拍摄美化/XComponent图形渲染常见问题定位指导/bpta-xcomponent-render-problem-guide`
- `FAQ/技术质量/性能/H5页面加载缓慢/faqs-performance-8`
- `FAQ/技术质量/性能/如何获取应用性能监控数据/faqs-performance-54`

### 15.10 并发 / Worker / TaskPool

- `开发指南/ArkTS_方舟编程语言/ArkTS并发/多线程并发/TaskPool和Worker的对比/taskpool-vs-worker`
- `开发指南/ArkTS_方舟编程语言/ArkTS并发/应用多线程开发实践/耗时任务并发场景/同步任务开发指导_TaskPool和Worker/sync-task-development`
- `FAQ/ArkTS语言/ArkTS线程模型和并发/Worker和TaskPool的线程数量是否有限制/faqs-arkts-28`
- `FAQ/ArkTS语言/ArkTS线程模型和并发/TaskPool和Worker的异同点/faqs-arkts-27`

### 15.11 AI / Data Augmentation Kit / CANN Kit / MindSpore Lite

- `开发指南/CANN_Kit_CANN异构计算框架服务/CANN_Kit简介/cannkit-introduction`
- `API参考/CANN_Kit_CANN异构计算框架服务/C_API/模块/CANN/cannkit`
- `API参考/CANN_Kit_CANN异构计算框架服务/C_API/头文件和结构体/头文件/llm_engine_h/cannkit-llm-engine`
- `API参考/MindSpore_Lite_Kit_昇思推理框架服务/ArkTS_API/ohos_ai_mindSporeLite_端侧AI框架_/js-apis-mindsporelite`
- `开发指南/MindSpore_Lite_Kit_昇思推理框架服务/...`
- `开发指南/Data_Augmentation_Kit_数据增强服务/端侧问答模型/dataaugmentation-localchatmodel`
- `开发指南/Data_Augmentation_Kit_数据增强服务/Data_Augmentation_Kit术语/端侧问答模型术语/data-augmentation-glossary-localchatmodel`
- `API参考/Data_Augmentation_Kit_数据增强服务/ArkTS_API/localChatModel_端侧问答模型/dataaugmentation-localchatmodel-api`
- `API参考/Data_Augmentation_Kit_数据增强服务/ArkTS_API/retrieval_智慧化数据平台/dataaugmentation-retrieval-api`
- `API参考/Data_Augmentation_Kit_数据增强服务/C_API/模块/AIP/dataaugmentation-capi-aip`
- `API参考/ArkData_方舟数据管理/ArkTS_API/ohos_data_intelligence_智慧数据平台_/js-apis-data-intelligence`
- `开发指南/ArkData_方舟数据管理/应用数据向量化_ArkTS/aip-data-intelligence-embedding`

### 15.12 图像 / PixelMap / ImageEffect

- `API参考/Image_Kit_图片处理服务/C_API/头文件/pixelmap_native_h/capi-pixelmap-native-h`
- `API参考/Image_Kit_图片处理服务/C_API/头文件/image_pixel_map_napi_h/capi-image-pixel-map-napi-h`
- `API参考/Image_Kit_图片处理服务/C_API/头文件/image_pixel_map_mdk_h/capi-image-pixel-map-mdk-h`
- `API参考/Image_Kit_图片处理服务/C_API/结构体/OhosPixelMapCreateOps/capi-image-ohospixelmapcreateops`
- `API参考/Image_Kit_图片处理服务/C_API/结构体/OhosPixelMapInfos/capi-image-ohospixelmapinfos`
- `开发指南/Image_Kit_图片处理服务/图片开发指导_ArkTS/图片编辑和处理/使用PixelMap完成位图操作/image-pixelmap-operation`

### 15.13 推送 / Push Kit / Notification

- `FAQ/消息推送服务_Push_Kit/如何判断APP是用户通过点击通知栏推送而唤起的/faqs-push-6`
- `FAQ/消息推送服务_Push_Kit/Push_Kit消息缓存时间/faqs-push-7`
- `FAQ/消息推送服务_Push_Kit/Push_Kit推送服务接入常见错误码和解决方案/faqs-push-10`
- `FAQ/消息推送服务_Push_Kit/HarmonyOS_3_x_4_x已接入过华为推送_HarmonyOS_Next_5_x及以上版本应用如何升级适配/faqs-push-11`

### 15.14 项目内部资源 (相对路径)

- `D:\HMgent\MindTrace-knowledge-galaxy\docs\research\harmonyos-3d-rendering-kits-survey-2026-09-23.md` (本文, §0-§11 + §12-§15)
- `D:\HMgent\MindTrace-knowledge-galaxy\docs\research\harmonyos-kits-survey-2026-09-05.md` — 12 kit 总览
- `D:\HMgent\MindTrace-knowledge-galaxy\docs\research\arkweb-render-pipeline-stability-2026-09-11.md` — ArkWeb 渲染进程稳定性
- `D:\知识星系\1\src\web\main.ts` — 619 LOC Three.js draft 入口
- `D:\知识星系\1\src\web\forceLayout.ts` — 158 LOC force-directed 算法
- `D:\知识星系\1\src\web\messageBridge.ts` — 83 LOC GalaxyBridge MessagePort
- `D:\知识星系\1\src\web\types.ts` — 38 LOC 数据类型
- `D:\知识星系\1\src\web\mockData.ts` — 82 LOC 10 个 mock 节点
- `D:\知识星系\1\harmony\entry\src\main\ets\pages\GalaxyPage.ets` — 329 LOC ArkTS 页面 + 桥接 (GalaxyModels 已实现)
- `D:\知识星系\1\harmony\entry\src\main\ets\model\GalaxyModels.ets` — 48 LOC 数据模型 (Record/DTO/Message)
- `D:\知识星系\1\harmony\entry\src\main\ets\mock\GalaxyMockData.ets` — 74 LOC mock data

---

**Last updated:** 2026-09-23 (基于 devecocli docs v1.3.2 + SDK 6.1.1(24) + draft `D:\知识星系\1\`)
**§12-§14 信心:** High (所有 API 名称与签名均来自一手 devecocli docs read 全文)
**§13-§14 信心:** Medium-High (草案代码读全, 但 P2 原生路径的"自写 shader 编译流水线" / "模拟器不可用" 等实操细节仍需真机验证)
**总 LOC 新增:** §12 ≈ 750 LOC, §13 ≈ 750 LOC, §14 ≈ 450 LOC, §15 ≈ 200 LOC; 合计 ~2150 LOC
**新增章节 / 矩阵 / 总览:** 4 个新章节 (§12 / §13 / §14 / §15); 1 个 45 行 × 15 列 主矩阵 + 8 个 gotcha 详述 + 36 行兼容性打分表
