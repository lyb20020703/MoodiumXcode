# Moodium Pocket · 快速原型

用 Xcode 16.3 打开 Moodium.xcodeproj，选择 Moodium 和 iPhone 模拟器运行。真机需在 Signing & Capabilities 选择自己的 Team（iOS 17+）。

## 计划与当前范围
1. 复用 Unity NewOpenningAni.mp4 开场视频及 moodi_tense.png。
2. 原生选关卡片：糖果星球、呼吸森林，带转场动画。
3. Core Motion 旋转速率识别底座按压引起的摆动，冷却 350ms；累积能量解救 Moodi。
4. SpriteKit 粒子受重力影响，并在屏幕边缘回弹；触摸按钮支持模拟器演示。
5. 进入后台暂停传感器；重返前台恢复。

## 原型边界与后续计划
这是可继续迭代的原生原型。Unity Prefab、Shader、3D 模型和原选关动画尚未迁移，当前为原生替代效果。灵敏度目前调整能量增益；需结合真实感官底座采集信号后再实现静置校准、轴向判定与噪声滤波。陀螺仪测量运动而非压力，拿起手机也可能触发。

下一轮：检查原选关 Timeline/Animator，导出视频或拆分图层；导出 Moodi 透明动画，替换静态表情；复用更多世界卡片/UI；加入音效、触觉节奏及持久化。

资源来源：Moodium/Assets/Video/NewOpenningAni.mp4、Assets/UI/Moodium/MoodCheck/png/moodi_tense.png、Assets/UI/Moodium/SqueezeModes/Resources/MoodiumSqueezeModes/squeeze_sparkle.png。原始项目未修改。
