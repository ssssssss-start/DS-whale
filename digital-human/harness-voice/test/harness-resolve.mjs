// Test-only resolution: the plugin consumes package exports exactly as a Harness profile supplies them.
import { registerHooks, createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'
import { resolve } from 'node:path'
const harness = process.env.DSH_HARNESS ?? resolve(import.meta.dirname, '../../../deepseek-harness')
const requireFromHarness = createRequire(pathToFileURL(resolve(harness, 'packages/bundle/base/package.json')))
const root = pathToFileURL(resolve(import.meta.dirname, '..')).href + '/'
registerHooks({ resolve(specifier, context, next) {
  if (context.parentURL?.startsWith(root) && (specifier.startsWith('@deepseek-ai/') || specifier === 'zod')) {
    return {url:pathToFileURL(specifier === 'zod' ? createRequire(requireFromHarness.resolve('@deepseek-ai/dsh-storage-domain')).resolve('zod') : requireFromHarness.resolve(specifier)).href,shortCircuit:true}
  }
  return next(specifier,context)
} })
