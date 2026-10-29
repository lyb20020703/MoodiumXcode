# Moodium Pocket · 手机版

没有 Vision Pro 时的补充体验：手机吸在枕头形状的感官底座中间，按压底座让手机轻微摆动，陀螺仪把每一次摆动变成一次“捏捏”，触发和 visionOS 版一致的世界、粒子和 Moodi 救援故事。

用 Xcode 16.3+ 打开 `Moodium.xcodeproj`，选择 iPhone / iPad 运行（iOS 17+，横屏）。真机需在 Signing & Capabilities 里选自己的 Team。仓库里的 `.usdz` 用 Git LFS 存储，克隆后先 `git lfs pull`。

## 体验流程

1. **开场**：沿用 Unity 的开场动画（带透明通道），边缘羽化后叠在烟紫色房间背景上；播完后 Logo 上移，出现和 visionOS 一样的玻璃按钮：语言（中文 / English）→ 有没有感官底座（有 / 没有）。
2. **选关**：移植 `WorldCarouselSelectionController` 的轮播参数：两座世界岛屿（CandyWorldUI / NatureWorldUI），侧边缩到 70 %、透明 55 %、偏转 20°，切换 0.35 s 缓出；背景是所选世界全景图的模糊版，岛屿用全景图做环境光。Moodi 在旁边说一句话，底部是移植的玻璃滑块 `GlassSlideToEnter`（糖果粉 / 自然绿主题）。
3. **捏捏救援**（移植 `MoodiRescueDirector` 和 K1–K10 中英文配音）：
   - 世界 360° 全景做背景，手机摆动时有轻微视差；
   - Moodi 飞进来、脚下一滑掉进捏捏枕头（CandySoft / NatureSoft），闷声求救；
   - 每次按压：枕头像果冻一样压扁、回弹、晃两下，并向被按的一侧倾斜；从枕头里喷出 Unity 的道具模型（巧克力、饼干、爱心、星星、马卡龙 / 叶子、花、蘑菇）；
   - **手机特有的玩法**：道具和小糖珠受手机真实重力影响，晃动底座它们就跟着滚；撞到屏幕边缘会弹回，撞击点沿屏幕边缘亮起一道光、溅出水花，同时有轻微震动和音效；落在枕头上的道具会在下一次按压时被弹起来；拿起手机用力晃会把所有东西撒开；
   - 能量环完全照 visionOS 设计稿：40 颗点、呼吸的头部点、20/50/80/100 % 四颗礼物菱形（点亮时放大并扩散波纹）、满能量 3 秒后淡到 40 %、8 秒没按压淡到 60 %；
   - 环境粒子随能量变化（按 `CandyFrostParticleController` 的曲线）：糖果世界糖霜越来越密，接近 100 % 变成糖雪；自然世界落叶、蒲公英和萤火虫；
   - Moodi 的声音经过低通滤波，能量越高越清楚；20/50/80 % 各说一句，连续按压随机鼓励，12 秒没按会催一下；
   - 100 %：枕头鼓起后“啵”地消失，Moodi 跳出来转圈，糖果雨 + 彩珠落下，然后可以“再救一次”或“换个世界”。

## 按压识别（`Squeeze/PressSensor.swift`）

- 读取 Core Motion 的旋转速率，按当前横屏方向换算到屏幕平面：绕屏幕竖轴 = 左右两侧的按压，绕屏幕横轴 = 前后按压，两者合成幅度；
- 自适应噪声底：阈值 = max(0.32 rad/s, 噪声 × 4.5) × 灵敏度系数；越过阈值后取 120 ms 内的峰值作为力度，先下沉的一侧作为按压方向；之后等枕头回弹平息再接收下一次；
- 用力晃动（线性加速度 > 1.1 g）不算按压，而是把道具撒开；
- App 自己的震动会让传感器短暂忽略，避免震动被误判为按压；
- 设置里可以选灵敏度（灵敏 / 适中 / 稳重）。**阈值需要在真实底座上调试**，入口集中在 `PressSensor` 的 `threshold`、`thresholdScale`。
- 选择“没有底座”或设备没有运动传感器时，自动改为触摸：按住屏幕枕头被压下，松开即一次捏捏，力度取决于按住时长，方向取决于按在屏幕左边还是右边。

## 目录

| 路径 | 内容 |
|---|---|
| `App/` | 入口、全局状态（语言 / 底座 / 灵敏度 / 静音，存在 UserDefaults）、世界定义 |
| `Design/` | 液态玻璃样式、背景、设置面板、模型加载 |
| `Opening/` | 开场视频与选择 |
| `Select/` | 3D 选关轮播、玻璃滑块 |
| `Squeeze/` | 按压识别、3D 舞台（SceneKit）、2D 特效与 Moodi（SpriteKit）、能量环、救援流程 |
| `Audio/` | 背景音乐、音效、Moodi 配音（AVAudioEngine 低通） |
| `Assets.xcassets` | App 图标、Moodi 表情、能量环与开场按钮贴图、粒子贴图、世界图标 |
| `Resources/` | 模型、全景图、开场视频、音乐音效、配音 |

## 资源来源（Unity 工程 lyb20020703/Moodium）

- 模型：`CandySoft`、`NatureSoft`、`CandyWorldUI`、`NatureWorldUI`、`Macaron` 用 Blender 减面（岛屿 195 万 → 17.5 万面，116 MB → 13 MB，外观逐个渲染比对过），其余道具原样。糖果道具在 Unity 里靠材质覆盖上色，导出后是白色，这里重新上了糖果色。
- 全景：`Assets/Moodium/image/CandyWorld.png`、`NatureWorld.png`（缩到 4096×2048）。
- UI：`ui-refresh` 交接包的能量环与开场玻璃按钮贴图、`MoodCheck` 的 Moodi 表情、`UI/icon` 的 App 图标、`UI/Image` 的世界图标。
- 粒子：Epic Toon FX 的 `sparkle3 / star / ring / glow1`（visionOS VFX 用的同一批）、`SqueezeModes` 的糖珠 / 种子 / 闪光、`Moodium/image` 的叶子。
- 声音：`Music/` 的两首世界 BGM 和音效、`MoodiumWalkTrail` 的提示音、`MoodiumVoice` 的 K1–K10 中英文配音及 squeeze-rescue 包里的闷声版。

## 已知限制

- 字体：Unity 里的阿里巴巴普惠体只有 TextMeshPro SDF 图集，没有 TTF，这里用系统圆体代替；有 TTF 后放进工程并改 `Font.moodium` 即可。
- Unity 的软体变形、Shader（如果冻材质）无法直接迁移，枕头的形变是缩放弹簧近似。
- Moodi 用的是 2D 表情图做动画，没有导入骨骼动画模型。
