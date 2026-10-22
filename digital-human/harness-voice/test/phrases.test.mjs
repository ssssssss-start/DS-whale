import {test} from 'node:test'
import assert from 'node:assert/strict'
import {Phrases} from '../phrases.js'

function fixture() {
 const out=[];let callback,delay
 const splitter=new Phrases(s=>out.push(s),{schedule:(fn,ms)=>{callback=fn;delay=ms;return 1},unschedule:()=>{callback=null}})
 return {out,splitter,get delay(){return delay},fire(){const fn=callback;callback=null;fn?.()}}
}
test('adjacent tiny replies form one phrase without an unbounded wait',()=>{
 const f=fixture();f.splitter.push('嗯，在呢。');f.splitter.push('今天也陪着你。')
 assert.equal(f.out.length,0);assert.equal(f.delay,180)
 f.fire();assert.deepEqual(f.out,['嗯，在呢。 今天也陪着你。'])
})
test('long phrase emits immediately; final short reply does not wait for more text',()=>{
 const f=fixture();f.splitter.push('这是一句已经足够完整的回复，现在就可以说出来。')
 assert.equal(f.out.length,1)
 f.splitter.push('好呀。',true);assert.equal(f.out[1],'好呀。');f.fire();assert.equal(f.out.length,2)
})
test('cancel clears the timer and code blocks never enter a merged phrase',()=>{
 const f=fixture();f.splitter.push('旧回复。');f.splitter.cancel();f.fire();assert.equal(f.out.length,0)
 f.splitter.push('你好。\n```js\n秘密代码();\n```\n继续。',true)
 assert.deepEqual(f.out,['你好。 继续。'])
})
