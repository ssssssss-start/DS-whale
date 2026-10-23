import {createElement as h, useSyncExternalStore} from 'react'
import {LauncherController} from './controller.js'

export const inject = ['slots','locale']
const namespace = 'whale-launcher'
const en = {
  start:'Start Whale Companion', show:'Show Whale Companion', hide:'Hide Whale Companion', starting:'Starting Whale Companion…',
  app_missing:'Whale Companion was not found. Place it in Applications or set companionPath in the plugin configuration.',
  open_failed:'Whale Companion could not be opened. Check the application and try again.',
  unavailable:'The Whale launcher is unavailable. Check that the plugin is enabled.',
  visibility_failed:'The companion did not confirm the visibility change. Try again.',
  hint:'Show or hide the character on the Harness host. Hiding stops speech and ends the call; showing does not start a call.',
}
const zh = {
  start:'启动鲸鱼娘', show:'显示鲸鱼娘', hide:'隐藏鲸鱼娘', starting:'正在启动鲸鱼娘…',
  app_missing:'未找到鲸鱼娘。请将应用放到 Applications，或在插件配置中设置 companionPath。',
  open_failed:'无法打开鲸鱼娘，请检查应用后重试。',
  unavailable:'鲸鱼娘启动入口暂不可用，请确认插件已启用。',
  visibility_failed:'鲸鱼娘未确认显示状态变化，请重试。',
  hint:'显示或隐藏 Harness 所在电脑上的桌宠。隐藏会停止播报并结束通话；显示不会自动开始通话。',
}

function CompanionIcon() {
  return h('svg',{width:21,height:21,viewBox:'0 0 24 24',fill:'none','aria-hidden':true},
    h('path',{d:'M4 13c0-4 3-7 7-7 4 0 7 3 7 7 0 4-3 7-7 7-4 0-7-3-7-7Z',fill:'currentColor',opacity:.18}),
    h('path',{d:'M5 13c0-3.6 2.5-6 6-6s6 2.4 6 6-2.5 6-6 6-6-2.4-6-6Zm12 1c3 0 4-2 4-4 1 4 0 7-4 7M9 4l1-2m3 2 1-2',stroke:'currentColor',strokeWidth:1.6,strokeLinecap:'round',strokeLinejoin:'round'}),
    h('circle',{cx:9.5,cy:12,r:1,fill:'currentColor'}))
}

export function LauncherButton({wide, controller, t}) {
  const state = useSyncExternalStore(controller.subscribe,controller.getSnapshot)
  if (!state.supported) return null
  const busy = state.loading || state.starting || state.changing
  const starting = state.starting || (state.loading && !state.running)
  const label = t(starting ? 'starting' : state.running ? state.visible && state.canHide ? 'hide' : 'show' : 'start')
  const problem = state.problem && Object.hasOwn(en,state.problem) ? t(state.problem) : ''
  return h('div',{className:'whale-launcher','data-wide':String(!!wide)},
    h('button',{type:'button',className:'whale-launcher-button',disabled:busy,'aria-label':label,'aria-busy':busy || undefined,'aria-pressed':state.running ? !!state.visible : undefined,
      title:problem || label + ' · ' + t('hint'),onClick:() => { void controller.launch() }},
    h(CompanionIcon),wide ? h('span',{className:'whale-launcher-label'},label) : null,
    h('span',{className:'whale-launcher-dot','data-running':state.running || undefined,'data-busy':busy || undefined})),
    wide && problem ? h('div',{className:'whale-launcher-error',role:'alert'},problem) : null)
}

const css = `
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
`

export function apply(ctx) {
  const controller = new LauncherController()
  ctx.effect(() => ctx.locale.register(namespace,{en,zh}),'whale launcher dictionaries')
  ctx.effect(() => {
    const style = document.createElement('style'); style.textContent = css; document.head.append(style)
    return () => style.remove()
  },'whale launcher styles')
  ctx.slots.inject('sidebar.footer.action',() => ctx.slots.register({name:'sidebar.footer.action',id:'whale-launcher',order:-400,
    locale:namespace,inject:() => ({controller})},LauncherButton))
  ctx.effect(() => { void controller.start(); return () => controller.close() },'whale launcher startup')
}
