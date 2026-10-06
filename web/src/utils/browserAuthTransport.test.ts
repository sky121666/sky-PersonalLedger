import { createPinia, setActivePinia } from 'pinia'
import { AxiosError, AxiosHeaders, type InternalAxiosRequestConfig } from 'axios'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useAuthStore } from '@/stores/auth'
import instance from './request'
import { deferred, flushWork } from '@/test/componentScript'

vi.mock('@/router', () => ({ default: { replace: vi.fn() } }))

function ok(config: InternalAxiosRequestConfig, access_token = 'new-access') {
  return { data: { code: 0, data: { access_token } }, config, status: 200, statusText: 'OK', headers: new AxiosHeaders() }
}

describe('browser authentication response ordering', () => {
  beforeEach(() => { setActivePinia(createPinia()); vi.clearAllMocks() })

  it('drains a refresh response before logout revokes its rotated cookie and before a new login', async () => {
    const oldResponse = deferred()
    const calls: string[] = []
    let cookie = 'old-cookie'
    let revoked = ''
    instance.defaults.adapter = async config => {
      calls.push(config.url!)
      if (config.url === '/auth/refresh') {
        await oldResponse.promise
        cookie = 'rotated-cookie' // Browser applies Set-Cookie before JS receives the body.
      } else if (config.url === '/auth/logout') {
        revoked = cookie
        cookie = ''
      } else if (config.url === '/auth/login') cookie = 'new-login-cookie'
      return ok(config)
    }
    const store = useAuthStore()
    store.accessToken = 'old-access'
    const refreshing = store.refresh()
    await flushWork()
    const loggingOut = store.logout()
    expect(store.accessToken).toBeNull()
    const login = store.login('password')
    await flushWork()
    const sentBeforeDrain = [...calls]
    oldResponse.resolve(undefined)
    await Promise.all([refreshing, loggingOut, login])
    expect(sentBeforeDrain).toEqual(['/auth/refresh'])
    expect(calls).toEqual(['/auth/refresh', '/auth/logout', '/auth/login'])
    expect(revoked).toBe('rotated-cookie')
    expect(cookie).toBe('new-login-cookie')
    expect(store.accessToken).toBe('new-access')
  })

  it('cannot apply a slow logout response after a newer login has established cookies', async () => {
    const oldResponse = deferred()
    let cookie = 'old-cookie'
    instance.defaults.adapter = async config => {
      if (config.url === '/auth/logout') { await oldResponse.promise; cookie = '' }
      else cookie = 'new-login-cookie'
      return ok(config)
    }
    const store = useAuthStore()
    store.accessToken = 'old-access'
    const logout = store.logout()
    const login = store.login('password')
    await flushWork()
    oldResponse.resolve(undefined)
    await Promise.all([logout, login])
    expect(cookie).toBe('new-login-cookie')
    expect(store.accessToken).toBe('new-access')
  })

  it('drains an old failed response before allowing the next login response to set its cookie', async () => {
    const oldResponse = deferred()
    let cookie = 'old-cookie'
    instance.defaults.adapter = async config => {
      if (config.url === '/auth/refresh') {
        await oldResponse.promise
        cookie = '' // Also protects clients while an older server still clears failed refresh cookies.
        throw new AxiosError('revoked', '401', config, undefined, { data: { code: 40100 }, config, status: 401, statusText: 'Unauthorized', headers: new AxiosHeaders() })
      }
      cookie = 'new-login-cookie'
      return ok(config)
    }
    const store = useAuthStore()
    store.accessToken = 'old-access'
    const refresh = store.refresh()
    await flushWork()
    const login = store.login('password')
    await flushWork()
    oldResponse.resolve(undefined)
    await Promise.all([refresh, login])
    expect(cookie).toBe('new-login-cookie')
    expect(store.accessToken).toBe('new-access')
  })

  it('does not attribute an undispatched old refresh failure to a replacement login', async () => {
    instance.defaults.adapter = async config => {
      if (config.url === '/auth/refresh') {
        throw new AxiosError('revoked', '401', config, undefined, { data: { code: 40100 }, config, status: 401, statusText: 'Unauthorized', headers: new AxiosHeaders() })
      }
      return ok(config)
    }
    const store = useAuthStore()
    store.accessToken = 'old-access'
    const refresh = store.refresh()
    // No yield: the old API operation has queued but not dispatched yet.
    const login = store.login('password')
    await expect(Promise.all([refresh, login])).resolves.toBeDefined()
    expect(store.accessToken).toBe('new-access')
  })
})
