// Generated from src/client by npm run build. Do not edit by hand.
window.__ModuleLoader__.load({id:'dsh-whale-voice',factory:(require)=>{
const module={exports:{}}
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/client/index.js
var index_exports = {};
__export(index_exports, {
  LauncherButton: () => LauncherButton,
  apply: () => apply,
  inject: () => inject
});
module.exports = __toCommonJS(index_exports);
var import_react = require("react");

// src/client/controller.js
var LauncherController = class {
  constructor(request = async (action) => {
    const controller = new AbortController(), timeout = setTimeout(() => controller.abort(), 1e4);
    try {
      const response = await fetch("api/whale-voice", { method: "POST", credentials: "same-origin", headers: { "content-type": "application/json" }, body: JSON.stringify({ action }), signal: controller.signal });
      const result = await response.json();
      if (!response.ok || !result?.ok) throw new Error("unavailable");
      return result.value;
    } finally {
      clearTimeout(timeout);
    }
  }) {
    this.request = request;
    this.listeners = /* @__PURE__ */ new Set();
    this.value = { loading: true, supported: true, running: false, starting: false, problem: null };
    this.closed = false;
    this.busy = false;
    this.polling = false;
    this.timer = null;
    this.generation = 0;
    this.subscribe = (listener) => {
      this.listeners.add(listener);
      return () => this.listeners.delete(listener);
    };
    this.getSnapshot = () => this.value;
  }
  update(state) {
    if (this.closed) return;
    this.value = { ...this.value, ...state };
    for (const listener of this.listeners) listener();
  }
  async start() {
    try {
      this.update({ ...await this.request("desktop_autostart"), loading: false });
    } catch {
      this.update({ loading: false, problem: "unavailable" });
    }
    if (!this.closed) this.timer = setInterval(() => {
      void this.refresh();
    }, 2e3);
  }
  async refresh() {
    if (this.closed || this.polling || this.busy) return;
    this.polling = true;
    const generation = this.generation;
    try {
      const value = await this.request("desktop_state");
      if (generation === this.generation) this.update({ ...value, loading: false });
    } catch {
      if (generation === this.generation) this.update({ running: false, starting: false, problem: "unavailable" });
    } finally {
      this.polling = false;
    }
  }
  async launch() {
    if (this.closed || this.busy) return;
    this.busy = true;
    this.generation += 1;
    this.update({ loading: true, problem: null });
    try {
      this.update({ ...await this.request("desktop_toggle"), loading: false });
    } catch {
      this.update({ loading: false, problem: "unavailable" });
    } finally {
      this.busy = false;
    }
  }
  close() {
    this.closed = true;
    clearInterval(this.timer);
    this.listeners.clear();
  }
};

// src/client/index.js
var inject = ["slots", "locale"];
var namespace = "whale-launcher";
var en = {
  start: "Start Whale Companion",
  show: "Show Whale Companion",
  hide: "Hide Whale Companion",
  starting: "Starting Whale Companion…",
  app_missing: "Whale Companion was not found. Place it in Applications or set companionPath in the plugin configuration.",
  open_failed: "Whale Companion could not be opened. Check the application and try again.",
  unavailable: "The Whale launcher is unavailable. Check that the plugin is enabled.",
  visibility_failed: "The companion did not confirm the visibility change. Try again.",
  hint: "Show or hide the character on the Harness host. Hiding stops speech and ends the call; showing does not start a call."
};
var zh = {
  start: "启动鲸鱼娘",
  show: "显示鲸鱼娘",
  hide: "隐藏鲸鱼娘",
  starting: "正在启动鲸鱼娘…",
  app_missing: "未找到鲸鱼娘。请将应用放到 Applications，或在插件配置中设置 companionPath。",
  open_failed: "无法打开鲸鱼娘，请检查应用后重试。",
  unavailable: "鲸鱼娘启动入口暂不可用，请确认插件已启用。",
  visibility_failed: "鲸鱼娘未确认显示状态变化，请重试。",
  hint: "显示或隐藏 Harness 所在电脑上的桌宠。隐藏会停止播报并结束通话；显示不会自动开始通话。"
};
function CompanionIcon() {
  return (0, import_react.createElement)(
    "svg",
    { width: 21, height: 21, viewBox: "0 0 24 24", fill: "none", "aria-hidden": true },
    (0, import_react.createElement)("path", { d: "M4 13c0-4 3-7 7-7 4 0 7 3 7 7 0 4-3 7-7 7-4 0-7-3-7-7Z", fill: "currentColor", opacity: 0.18 }),
    (0, import_react.createElement)("path", { d: "M5 13c0-3.6 2.5-6 6-6s6 2.4 6 6-2.5 6-6 6-6-2.4-6-6Zm12 1c3 0 4-2 4-4 1 4 0 7-4 7M9 4l1-2m3 2 1-2", stroke: "currentColor", strokeWidth: 1.6, strokeLinecap: "round", strokeLinejoin: "round" }),
    (0, import_react.createElement)("circle", { cx: 9.5, cy: 12, r: 1, fill: "currentColor" })
  );
}
function LauncherButton({ wide, controller, t }) {
  const state = (0, import_react.useSyncExternalStore)(controller.subscribe, controller.getSnapshot);
  if (!state.supported) return null;
  const busy = state.loading || state.starting || state.changing;
  const starting = state.starting || state.loading && !state.running;
  const label = t(starting ? "starting" : state.running ? state.visible && state.canHide ? "hide" : "show" : "start");
  const problem = state.problem && Object.hasOwn(en, state.problem) ? t(state.problem) : "";
  return (0, import_react.createElement)(
    "div",
    { className: "whale-launcher", "data-wide": String(!!wide) },
    (0, import_react.createElement)(
      "button",
      {
        type: "button",
        className: "whale-launcher-button",
        disabled: busy,
        "aria-label": label,
        "aria-busy": busy || void 0,
        "aria-pressed": state.running ? !!state.visible : void 0,
        title: problem || label + " · " + t("hint"),
        onClick: () => {
          void controller.launch();
        }
      },
      (0, import_react.createElement)(CompanionIcon),
      wide ? (0, import_react.createElement)("span", { className: "whale-launcher-label" }, label) : null,
      (0, import_react.createElement)("span", { className: "whale-launcher-dot", "data-running": state.running || void 0, "data-busy": busy || void 0 })
    ),
    wide && problem ? (0, import_react.createElement)("div", { className: "whale-launcher-error", role: "alert" }, problem) : null
  );
}
var css = `
[data-slot="sidebar.footer.action"]:has(.whale-launcher){display:flex!important;flex-direction:column;align-items:flex-start;width:100%;min-width:0;gap:2px}
.whale-launcher{min-width:0;color:inherit;font:inherit}
.whale-launcher-button{display:flex;align-items:center;gap:9px;min-height:36px;max-width:100%;padding:0 14px;border:0;border-radius:999px;background:none;color:inherit;font:inherit;font-size:14px;cursor:pointer}
.whale-launcher-button:hover{background:rgba(127,127,127,.14)}
.whale-launcher-button:focus-visible{outline:2px solid #60a5fa;outline-offset:2px}
.whale-launcher-button:disabled{cursor:wait;opacity:.7}
.whale-launcher-button>svg{flex:none;color:#57b7df}
.whale-launcher-label{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.whale-launcher-dot{flex:none;width:6px;height:6px;border-radius:50%;background:currentColor;opacity:.3}
.whale-launcher-dot[data-running]{background:#42b879;opacity:1}
.whale-launcher-dot[data-busy]{background:#e7ab4b;opacity:1}
.whale-launcher[data-wide="false"] .whale-launcher-button{padding:0;justify-content:center;gap:4px;width:36px}
.whale-launcher-error{max-width:260px;padding:3px 14px 7px;font-size:12px;line-height:1.5;color:#e79680}
`;
function apply(ctx) {
  const controller = new LauncherController();
  ctx.effect(() => ctx.locale.register(namespace, { en, zh }), "whale launcher dictionaries");
  ctx.effect(() => {
    const style = document.createElement("style");
    style.textContent = css;
    document.head.append(style);
    return () => style.remove();
  }, "whale launcher styles");
  ctx.slots.inject("sidebar.footer.action", () => ctx.slots.register({
    name: "sidebar.footer.action",
    id: "whale-launcher",
    order: -400,
    locale: namespace,
    inject: () => ({ controller })
  }, LauncherButton));
  ctx.effect(() => {
    void controller.start();
    return () => controller.close();
  }, "whale launcher startup");
}

return Object.defineProperty({...module.exports},Symbol.toStringTag,{value:'Module'})
}})
