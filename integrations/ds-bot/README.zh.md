# DS Bot 可选集成

补丁修改的是 DS Bot 插件，不是 Harness。内容包括：会话右键绑定、成功提示、鲸鱼娘通话适配、语音状态与字幕处理、翻译和回归测试。生成文件 `client.js` 与对应源码一起保存。

语音识别结果现在显式标注为 ASR，供 Agent 的听觉上下文使用。原生桌面双击通话直接使用 Harness 会话，不要求此补丁；本补丁用于 DS Bot 浏览器入口。

目标仓库：https://github.com/FeiZhuLulu/DeepSeek-Bot

精确基线：`6c25d5449582b7ae3aa323050e94400c76229443`。

在该版本的独立干净检出中应用，不要覆盖已经修改过的安装：

```sh
git apply --check /absolute/path/to/DS-whale/integrations/ds-bot/whale-integration.patch
git apply /absolute/path/to/DS-whale/integrations/ds-bot/whale-integration.patch
cd ds-bot
npm ci
npm run build
npm test
node scripts/build-client.mjs --check
```

随后按 DS Bot 自身文档打包并通过插件管理器安装。禁止手改生成的 `client.js`。其他版本需先核对冲突，不强行应用。本仓库不承诺任意未来版本兼容；当前参考 Harness 提交记录在 `versions.json`，不提供也不需要 Harness 核心补丁。
