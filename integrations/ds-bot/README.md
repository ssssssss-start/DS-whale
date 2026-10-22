# Optional DS Bot integration

This patch changes DS Bot, not Harness. It adds right-click binding, success feedback, the Whale call adapter, voice-state/caption handling, translations and regression tests. `client.js` is generated from `src/client` and included alongside source changes.

Target repository: https://github.com/FeiZhuLulu/DeepSeek-Bot

Exact baseline: `6c25d5449582b7ae3aa323050e94400c76229443`.

Apply in a clean, separate checkout of that baseline. Do not apply over an already modified installation:

```sh
git apply --check /absolute/path/to/DS-whale/integrations/ds-bot/whale-integration.patch
git apply /absolute/path/to/DS-whale/integrations/ds-bot/whale-integration.patch
cd ds-bot
npm ci
npm run build
npm test
node scripts/build-client.mjs --check
```

Use DS Bot's documented packaging/plugin installation flow afterward. Never edit generated `client.js` directly. On another baseline, review conflicts rather than force-applying. This repository does not claim compatibility with arbitrary future DS Bot/Harness versions. The local reference Harness commit is recorded in `versions.json`; no Harness patch is provided or required.
