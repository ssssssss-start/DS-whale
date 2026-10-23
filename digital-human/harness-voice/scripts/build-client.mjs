import {createRequire} from 'node:module'
import {readFile,writeFile} from 'node:fs/promises'
import {fileURLToPath} from 'node:url'
import {resolve} from 'node:path'

const require = createRequire(import.meta.url)
const root = fileURLToPath(new URL('..',import.meta.url))
const {build} = require('esbuild')
const result = await build({absWorkingDir:root,entryPoints:['src/client/index.js'],bundle:true,format:'cjs',platform:'browser',target:'es2022',
  external:['react'],charset:'utf8',write:false,logLevel:'silent'})
if (result.warnings.length) throw new Error('Whale client build produced warnings')
const output = `// Generated from src/client by npm run build. Do not edit by hand.\nwindow.__ModuleLoader__.load({id:'dsh-whale-voice',factory:(require)=>{\nconst module={exports:{}}\n${result.outputFiles[0].text}\nreturn Object.defineProperty({...module.exports},Symbol.toStringTag,{value:'Module'})\n}})\n`
const path = resolve(root,'client.js')
if (process.argv.includes('--check')) {
  if (await readFile(path,'utf8') !== output) throw new Error('client.js is stale; run npm run build')
} else await writeFile(path,output)
