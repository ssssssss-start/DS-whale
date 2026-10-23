# 鲸鱼娘原版精度绑定 v0.3

按用户要求以外观优先：原版 **1,383,928 个顶点全部保留**，不减面，不降低贴图分辨率。v0.2 轻量副本已停止使用。来源是用户当前 Blender 中已导入的鲸鱼娘；本轮没有下载外部模型或调用付费生成服务，模型最初的生成来源未作额外推断。

- `whale-full-v0.3.blend`：原版网格、贴图、16 根骨骼及 7 组动画；打开 `Whale_Full_v03` 场景。原始 `Scene` 仍保留。
- `whale-full-v0.3.glb`：给桌宠使用的完整精度导出，14 个网格、1 套蒙皮、7 组动作。
- `rig-validation.json`：顶点数、拓扑保留与权重覆盖检查。
- `export-validation.json`：导出网格、骨骼蒙皮和动画数量检查。

## 下载模型

完整 GLB 和 Blender 工程放在 [v0.7.2 版本附件](https://github.com/ssssssss-start/DS-whale/releases/tag/v0.7.2)，不包含在 Git 源码包内。在仓库根目录运行 `bash digital-human/3d/download-model.sh`，下载并校验 GLB；随后构建桌宠。Blender 工程可从同一页面下载，大小和 SHA-256 见 `assets.json`。

## 动作

在骨骼 `WhaleFullRig` 的 NLA 编辑器中只启用一条轨道播放。`Turn_360` 为 8 秒；`Wave`、`Idle`、`Listening`、`Thinking`、`Tail_Swish` 为 4 秒；`Walk_In_Place` 为 2 秒循环。24 fps。默认保存为中立姿势。

桌宠右键可选择 `3D Character (Original Detail)`，并可随时切回 2D。需要重新构建并重开应用。新增 Agent 动作还需要插件 0.5.5；不修改 Harness。听和思考使用不同头部动作，原有电话状态条仍显示通话阶段。

## 尚需精修

这是首次可运行的绑定和桌宠集成，未宣称最终美术完成。手指未独立绑定；步行是原地动作，没有脚部 IK；长发跟随头部，没有头发/衣裙碰撞或物理模拟。眨眼和口型为局部形变初稿，不能替代完整面部重拓扑与表情绑定。旧四种情绪暂不在 3D 模式向 Agent 宣告。没有进行真实麦克风或付费语音质量测试。

## 重建

下载的 Blender 工程已包含绑定和原始 `Scene`；直接使用或修改 `Whale_Full_v03` 场景后运行 `export.py`，并设置正确的 `__file__`。`prepare.py` 保留为建模记录，只能对尚未创建派生场景的原始工程副本运行，不能在已绑定工程上重复运行。任何后续性能优化须先维持原版外观，不能默认减面。
