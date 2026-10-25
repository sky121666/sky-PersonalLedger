import { createPinia, setActivePinia, disposePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useThemeStore } from './theme'

describe('appearance preferences', () => {
  let dark = false
  let change: (() => void) | undefined
  let stored: Map<string, string>
  let classes: Set<string>
  let pinia: ReturnType<typeof createPinia>

  beforeEach(() => {
    dark = false
    stored = new Map()
    classes = new Set()
    pinia = createPinia()
    setActivePinia(pinia)
    vi.stubGlobal('localStorage', {
      getItem: (key: string) => stored.get(key) ?? null,
      setItem: (key: string, value: string) => stored.set(key, value),
    })
    vi.stubGlobal('document', {
      documentElement: {
        classList: {
          add: (key: string) => classes.add(key),
          remove: (key: string) => classes.delete(key),
          toggle: (key: string, enabled: boolean) => enabled ? classes.add(key) : classes.delete(key),
        },
        style: {},
      },
    })
    vi.stubGlobal('window', {
      matchMedia: () => ({
        get matches() { return dark },
        addEventListener: (_: string, listener: () => void) => { change = listener },
        removeEventListener: vi.fn(),
      }),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })
  })
  afterEach(() => { disposePinia(pinia); vi.unstubAllGlobals() })

  it.each(['light', 'dark'] as const)('keeps legacy %s selection instead of adopting the system', preference => {
    stored.set('theme', preference)
    dark = preference === 'light'
    const theme = useThemeStore()
    theme.init()
    expect(theme.preference).toBe(preference)
    expect(theme.isDark).toBe(preference === 'dark')
    expect(classes.has('dark')).toBe(preference === 'dark')
  })

  it('persists system selection and reacts to subsequent system changes', () => {
    const theme = useThemeStore()
    theme.init()
    expect(theme.setPreference('system')).toBe(true)
    expect(stored.get('theme')).toBe('system')
    dark = true
    change?.()
    expect(theme.isDark).toBe(true)
    expect(classes.has('dark')).toBe(true)
    theme.init()
    expect(theme.preference).toBe('system')
    expect(theme.isDark).toBe(true)
  })

  it('a manual toggle exits system following', () => {
    const theme = useThemeStore()
    theme.init()
    theme.toggle()
    expect(theme.preference).toBe('dark')
    dark = true
    change?.()
    dark = false
    change?.()
    expect(theme.isDark).toBe(true)
    expect(stored.get('theme')).toBe('dark')
  })

  it('keeps the previous preference when persistence is unavailable', () => {
    const theme = useThemeStore()
    theme.init()
    vi.stubGlobal('localStorage', { setItem: () => { throw Error('blocked') } })
    expect(theme.setPreference('dark')).toBe(false)
    expect(theme.preference).toBe('system')
    expect(theme.isDark).toBe(false)
  })
})
