import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'

// Tailwind v4 scans sources natively. Reject a reintroduced vulnerable parser
// anywhere in the frozen dependency graph, including non-Tailwind consumers.
const lock = readFileSync(new URL('../pnpm-lock.yaml', import.meta.url), 'utf8')
assert.doesNotMatch(lock, /^\s+(?:['"]?braces@|braces:)/m,
  'braces returned to the dependency graph; restore a bounded-depth regression and reviewed patch before accepting it')

const webRequire = createRequire(new URL('../package.json', import.meta.url))
const tailwind = webRequire('tailwindcss/package.json')
assert.match(tailwind.version, /^4\./, 'This guard requires the native Tailwind v4 scanner')
const pluginRequire = createRequire(webRequire.resolve('@tailwindcss/vite'))
assert.ok(pluginRequire.resolve('@tailwindcss/oxide'), 'The native scanner must be installed')
console.log('Brace parser guard passed: no braces dependency in the frozen graph; Tailwind v4 native scanner is installed.')
