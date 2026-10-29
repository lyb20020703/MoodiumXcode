# Moodium Pocket · 快速原型

用 Xcode 16.3 打开 Moodium.xcodeproj，选择 Moodium 和 iPhone 模拟器运行。真机需在 Signing & Capabilities 选择自己的 Team（iOS 17+）。

## 计划与当前范围
1. 复用 Unity NewOpenningAni.mp4 开场视频及 moodi_tense.png。
2. 原生选关卡片：糖果星球、呼吸森林，带转场动画。
3. Core Motion 旋转速率识别底座按压引起的摆动，冷却 350ms；累积能量解救 Moodi。
4. SpriteKit 粒子受重力影响，并在屏幕边缘回弹；仅使用陀螺仪触发按压。
5. 进入后台暂停传感器；重返前台恢复。

## 原型边界与后续计划
这是可继续迭代的原生原型。Unity Prefab、Shader、3D 模型和原选关动画尚未迁移，当前为原生替代效果。灵敏度目前调整能量增益；需结合真实感官底座采集信号后再实现静置校准、轴向判定与噪声滤波。陀螺仪测量运动而非压力，拿起手机也可能触发。

下一轮：检查原选关 Timeline/Animator，导出视频或拆分图层；导出 Moodi 透明动画，替换静态表情；复用更多世界卡片/UI；加入音效、触觉节奏及持久化。

资源来源：Moodium/Assets/Video/NewOpenningAni.mp4、Assets/UI/Moodium/MoodCheck/png/moodi_tense.png、Assets/UI/Moodium/SqueezeModes/Resources/MoodiumSqueezeModes/squeeze_sparkle.png。原始项目未修改。

## 横屏平板原型更新
支持 iPhone / iPad，锁定双向横屏（iPad 全屏运行）。横屏左右侧倾使用设备 X 轴旋转速率，避免原先混合两个轴触发。需在真实底座上验证阈值。
选关改为 SceneKit 展示 Unity 的 CandyWorldUI.fbx / NatureWorldUI.fbx，经 Blender 转为 USDZ；横向滑动切换模型，按钮进入当前居中的关卡。Unity Shader 与 Prefab 材质覆盖不会自动迁移，外观仍需与原场景逐项比对。当前并未移植 Unity 原选关动画。

## 大幅 3D 按压场景
按压页改用 SceneKit，全屏展示 CandySoft / NatureSoft，顶部导航和底部能量以浮层呈现。每次触发播放整体缩放回弹（原型效果，并非 Unity 软体变形）。爆发物采用 Unity 原 FBX 转出的 USDZ：糖果为 chocolate、cookie、heart、star、Macaron；自然为 leaf_lofi、flower、mushroom。采用原生刚体重力、旋转和横屏边界回弹，同时存在上限为 96 个，5 秒自动回收。Unity 材质覆盖、软体与粒子脚本未直接迁移，需真机确认外观与性能。

## 选关与输入更新
选关使用横向吸附分页，单页宽度占 88%，相邻关卡保留边缘预览；进入按钮跟随当前分页。固定相机，模型增加 X 轴 90° 朝向修正。移除触摸按压入口，仅 Core Motion 触发捏捏与粒子；模拟器无运动传感器时无法演示按压。
