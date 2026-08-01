import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  clearSetupToken,
  getSetupToken,
  setSetupToken,
  setupAccessConfig
} from './setupAccess'

describe('setup access token', () => {
  beforeEach(() => {
    vi.unstubAllGlobals()
    clearSetupToken()
  })

  it('normalizes the token and emits only the setup header', () => {
    expect(setSetupToken('  local-install-token  ')).toBe('local-install-token')
    expect(getSetupToken()).toBe('local-install-token')
    expect(setupAccessConfig()).toEqual({
      headers: { 'X-Setup-Token': 'local-install-token' }
    })
  })

  it('clears the token after initialization', () => {
    setSetupToken('local-install-token')
    clearSetupToken()

    expect(getSetupToken()).toBe('')
    expect(setupAccessConfig()).toEqual({})
  })

  it('continues in memory when session storage is unavailable', () => {
    vi.stubGlobal('window', {
      sessionStorage: {
        setItem: () => { throw new Error('blocked') },
        getItem: () => { throw new Error('blocked') },
        removeItem: () => { throw new Error('blocked') }
      }
    })

    setSetupToken('memory-only-token')
    expect(getSetupToken()).toBe('memory-only-token')
  })
})
