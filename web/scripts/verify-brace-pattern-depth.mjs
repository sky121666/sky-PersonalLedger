import assert from 'node:assert/strict'
import { createRequire } from 'node:module'

// Resolve through the real consumers so an unapplied or partial pnpm patch fails.
const webRequire = createRequire(new URL('../package.json', import.meta.url))
const tailwindRequire = createRequire(webRequire.resolve('tailwindcss/package.json'))
const micromatchRequire = createRequire(tailwindRequire.resolve('micromatch/package.json'))
const fastGlobRequire = createRequire(tailwindRequire.resolve('fast-glob/package.json'))
const fastGlobMicromatchRequire = createRequire(fastGlobRequire.resolve('micromatch/package.json'))
const chokidarRequire = createRequire(tailwindRequire.resolve('chokidar/package.json'))
const bracesPath = micromatchRequire.resolve('braces')
assert.equal(fastGlobMicromatchRequire.resolve('braces'), bracesPath)
assert.equal(chokidarRequire.resolve('braces'), bracesPath)
const braces = micromatchRequire('braces')
const micromatch = tailwindRequire('micromatch')
const fastGlob = tailwindRequire('fast-glob')

const deepBrace = '{'.repeat(4500) + 'a,b' + '}'.repeat(4500)
function rejectsDepth(label, operation) {
  assert.throws(operation, (error) =>
    (error instanceof SyntaxError || error instanceof RangeError) &&
    /nesting depth exceeds maximum 100/.test(error.message) &&
    !/Maximum call stack size exceeded/.test(error.message), label)
}

// RED on the vulnerable dependency: this must be a bounded input rejection,
// rather than the engine exhausting its call stack below the 10,000-char cap.
rejectsDepth('compile rejects deep input before stack exhaustion', () => braces.compile(deepBrace))

const cases = [
  ['./src/**/*.{vue,js,ts,jsx,tsx}', './src/**/*.(vue|js|ts|jsx|tsx)',
    ['./src/**/*.vue', './src/**/*.js', './src/**/*.ts', './src/**/*.jsx', './src/**/*.tsx'], './src/**/*.{vue,js,ts,jsx,tsx}'],
  ['a/{b,c}/d', 'a/(b|c)/d', ['a/b/d', 'a/c/d'], 'a/{b,c}/d'],
  ['{1..10}', '([1-9]|10)', ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'], '{1..10}'],
  ['{a..z..3}', '(a|d|g|j|m|p|s|v|y)', ['a', 'd', 'g', 'j', 'm', 'p', 's', 'v', 'y'], '{a..z..3}'],
  ['\\{literal\\}', '{literal}', ['{literal}'], '{literal}'],
  ['a/(b)/{c,d}', 'a/(b)/(c|d)', ['a/(b)/c', 'a/(b)/d'], 'a/(b)/{c,d}'],
  ['${a,b}', '$\\{a,b\\}', ['${a,b}'], '${a,b}'],
  ['{a,b', '\\{a,b', ['{a,b'], '{a,b'],
  ['"{a,b}"', '{a,b}', ['{a,b}'], '{a,b}'],
  ['{1..3,x}', '(1..3|x)', ['1..3', 'x'], '{1..3,x}'],
]
for (const [pattern, compiled, expanded, stringified] of cases) {
  const options = { escapeInvalid: true }
  assert.equal(braces.compile(pattern, options), compiled)
  assert.deepEqual(braces.expand(pattern, options), expanded)
  assert.equal(braces.stringify(pattern, options), stringified)
}
for (const [open, close] of [['{', '}'], ['(', ')']]) {
  const boundary = open.repeat(100) + 'x' + close.repeat(100)
  assert.equal(braces.compile(boundary), boundary)
  assert.deepEqual(braces.expand(boundary), [boundary])
  assert.equal(braces.stringify(boundary), boundary)
  const overBoundary = open.repeat(101) + 'x' + close.repeat(101)
  for (const api of ['compile', 'expand', 'stringify', 'parse']) {
    rejectsDepth(`${api} rejects the 101st ${open} container`, () => braces[api](overBoundary))
  }
}

const attacks = [
  deepBrace,
  '('.repeat(4500) + 'x' + ')'.repeat(4500),
  '{('.repeat(2250) + 'x' + ')}'.repeat(2250),
  '$' + deepBrace,
  '{'.repeat(4500) + 'x',
]
for (const pattern of attacks) {
  for (const api of ['compile', 'expand', 'stringify', 'parse']) {
    rejectsDepth(`${api} rejects hostile nesting`, () => braces[api](pattern))
  }
}

// Caller-supplied ASTs bypass parse(); exercise all public AST walkers.
function nestedAST(depth, fallbackDepth, fallbackFlag) {
  let node = { type: 'text', value: 'x' }
  for (let level = depth; level >= 1; level--) {
    const parent = { type: 'paren', nodes: [node] }
    node.parent = parent
    if (level === fallbackDepth) parent[fallbackFlag] = true
    node = parent
  }
  const root = { type: 'root', nodes: [node] }
  node.parent = root
  return root
}
for (const api of ['compile', 'expand', 'stringify']) {
  rejectsDepth(`${api} bounds direct AST traversal`, () => braces[api](nestedAST(6000)))
}
// Total depth 101, but only 21 below the fallback: resetting the depth here
// would silently accept this tree and is a separate bypass regression.
rejectsDepth('invalid stringify fallback preserves consumed depth', () => braces.expand(nestedAST(101, 80, 'invalid')))
rejectsDepth('dollar stringify fallback preserves consumed depth', () => braces.expand(nestedAST(101, 80, 'dollar')))
assert.deepEqual(braces.expand(nestedAST(100, 80, 'invalid')), ['x'])
assert.deepEqual(braces.expand(nestedAST(100, 80, 'dollar')), ['x'])

const expectedPatterns = ['./index.html', './src/**/*.js', './src/**/*.ts', './src/**/*.vue', './src/**/*.jsx', './src/**/*.tsx']
assert.deepEqual(fastGlob.generateTasks(['./index.html', './src/**/*.{vue,js,ts,jsx,tsx}']).flatMap((task) => task.patterns), expectedPatterns)
rejectsDepth('actual micromatch expansion uses the patched dependency', () => micromatch.braces(deepBrace, { expand: true, nodupes: true, keepEscaping: true }))
rejectsDepth('actual fast-glob task generation uses the patched dependency', () => fastGlob.generateTasks([deepBrace]))

console.log('Brace depth regression passed: 36 normal/boundary checks, 24 attack variants, exact limits, fallback inheritance and actual consumer chains.')
