import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { createRequire } from 'node:module'
import { runInNewContext } from 'node:vm'
import ts from 'typescript'
import * as vue from 'vue'

const localRequire = createRequire(import.meta.url)

// Execute the actual <script setup> with Vue reactivity. Only browser lifecycle,
// DOM focus and API boundaries are supplied by the test; no business logic is copied.
export function componentScript(file: string, exposed: string[], mocks: Record<string, unknown>, props = {}) {
  const scope = vue.effectScope()
  const unmount: (() => void)[] = []
  const mounted: (() => void)[] = []
  const emitted: unknown[][] = []
  const reactiveProps = vue.reactive(props)
  const sourceRoot = resolve(process.cwd(), 'src')
  function evaluate(source: string): any {
    const module = { exports: {} }
    const require = (name: string): any => {
      if (name in mocks) return mocks[name]
      if (name === 'vue') return { ...vue, onMounted: (fn: () => void) => mounted.push(fn), onBeforeUnmount: (fn: () => void) => unmount.push(fn) }
      if (name === 'vue-router') return { useRouter: () => ({ push() {} }) }
      if (name === 'lucide-vue-next' || name.endsWith('.vue')) return {}
      if (name.startsWith('@/')) return evaluate(readFileSync(resolve(sourceRoot, name.slice(2) + '.ts'), 'utf8'))
      return localRequire(name)
    }
    const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true } }).outputText
    runInNewContext(compiled, { require, module, exports: module.exports, console, setTimeout, clearTimeout, document: { activeElement: null }, HTMLElement: class {}, defineProps: () => reactiveProps, defineEmits: () => (...args: unknown[]) => emitted.push(args) })
    return module.exports
  }
  const raw = readFileSync(resolve(sourceRoot, file), 'utf8').split('<script setup lang="ts">')[1]!.split('</script>')[0]!
  const entry = scope.run(() => evaluate(raw + `\nexports.entry = {${exposed.join(',')}};`).entry)
  return { entry, props: reactiveProps as any, emitted, mount: () => mounted.forEach(fn => fn()), unmount: () => { unmount.forEach(fn => fn()); scope.stop() } }
}

export function deferred<T = any>() {
  let resolve!: (value: T) => void
  let reject!: (reason: unknown) => void
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}

export async function flushWork() {
  for (let i = 0; i < 16; i++) await vue.nextTick()
}
