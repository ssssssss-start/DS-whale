# DS Whale · 鲸鱼娘 🐳

面向 DeepSeek Harness / DS Bot 的 macOS 桌面数字人伴侣：透明桌宠、动作表情、会话绑定、豆包流式语音、语音通话，以及主动提醒和免打扰。

[English](README.md)

## 功能

- 透明背景，可拖动、缩放；支持挥手、戳一戳和摸头。
- 手动选择害羞、惊讶、委屈、困倦表情，带进入、停留及恢复过程。
- 绑定会话后播报新的直接回复，也可以用 `[whale]` 单次启用。
- 接入豆包官方双向流式 TTS；支持本地配置 Key、播放状态同步和说话动作。
- 安装 DS Bot 配套补丁后，可右键绑定、用鲸鱼娘的音色进行语音通话。
- 任务通知、明确约定的提醒、陪伴问候、免打扰与安静时段。

## 改动边界

| 部分 | 目录 | 说明 |
| --- | --- | --- |
| 鲸鱼娘独立插件 | `digital-human/harness-voice/` | 通过公开插件接口接入 Harness |
| macOS 桌宠 | `digital-human/desktop-preview/` | Swift 原生桌面应用 |
| DS Bot 配套补丁 | `integrations/ds-bot/` | **修改 DS Bot 客户端**，实现右键绑定和通话接管 |
| DeepSeek Harness 核心 | 外部依赖 | 本次核对的本地检出中，已跟踪核心源码没有改动 |

独立鲸鱼娘插件不等于 DS Bot 的全部集成功能。右键菜单和通话接管需要 DS Bot 配套补丁；不打补丁时仍可使用桌宠的 Follow Next Conversation 或 `[whale]` 接入基础播报。

## 构建与使用

1. macOS 安装 Apple Command Line Tools，然后运行：
   ```sh
   bash digital-human/desktop-preview/build.sh
   open 'digital-human/desktop-preview/Whale Companion.app'
   ```
2. 在 Harness 插件管理器中安装 `digital-human/harness-voice` 并启用 `dsh-whale-voice`。
3. 将桌宠目录的 `voice-config.example.json` 复制为同目录 `voice-config.local.json`，将权限设为 `600`，在本机填写自己的豆包语音 API Key。该文件禁止提交。菜单 Reload Voice Config… 可重载，Connect Doubao Voice… 可临时连接。调用按服务商规则计费。
4. 使用 Follow Next Conversation 后，在目标会话发送一条直接消息。右键绑定和通话详见 [DS Bot 集成说明](integrations/ds-bot/README.zh.md)。

桌宠在 Harness 所在电脑播放声音。语音识别仍依赖 Harness Voice Input 或浏览器识别器，回复来自 Bot 已配置的聊天模型；TTS Key 不包含识别和聊天模型能力。

## 版本与更新

查看 [versions.json](versions.json) 和 [更新记录](CHANGELOG.md)。当前桌宠 0.5.1/build 15、鲸鱼娘插件 0.4.3。此仓库先建立源码及版本记录，**尚未实现自动检查、下载和安装更新**。后续可通过 GitHub Releases 提供带版本的插件包、桌面构建；插件使用 Harness 插件管理器更新，桌宠在无通话时重建并重开。

## 验证与限制

```sh
node --test digital-human/harness-voice/test/*.test.mjs
bash digital-human/desktop-preview/build.sh
```

自动检查使用模拟传输与音频，不能代替真实麦克风、回声及付费接口延迟测试。新表情目前手动选择；尚无音素级嘴型同步。尾巴现为身体后方的独立图层，尾根固定，尾尖延迟跟随小幅摆动。历史 Mira 网页桥接与固定欢迎、戳一戳、摸头录音不发布；缺少这些录音时动作仍可使用，豆包动态语音不受影响。

只包含当前运行所需形象素材，不包含真实密钥、会话数据、日志、应用构建、旧实验和第三方参考项目。暂未指定分发许可证，素材说明见 [assets/README.md](digital-human/desktop-preview/assets/README.md)。
