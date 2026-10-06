import { createPinia, setActivePinia } from 'pinia'
import { AxiosError, AxiosHeaders, type InternalAxiosRequestConfig } from 'axios'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { authApi } from '@/api/auth'
import { useAuthStore } from '@/stores/auth'
import router from '@/router'
import instance, { get } from './request'
import { deferred, flushWork } from '@/test/componentScript'

vi.mock('@/api/auth', () => ({ authApi: { login: vi.fn(), refresh: vi.fn(), logout: vi.fn() } }))
vi.mock('@/router', () => ({ default: { replace: vi.fn() } }))

describe('request session binding', () => {
  beforeEach(() => { setActivePinia(createPinia()); vi.clearAllMocks() })

  it('rejects an old successful response after a new login', async () => {
    const response = deferred()
    let request!: InternalAxiosRequestConfig
    instance.defaults.adapter = config => { request = config; return response.promise }
    const store = useAuthStore()
    store.accessToken = 'old-token'
    const reading = get('/accounts')
    const result = reading.then(value => ({ value }), error => ({ error }))
    await flushWork()
    vi.mocked(authApi.login).mockResolvedValue({ access_token: 'new-token', expires_in: 900 })
    await store.login('password')
    response.resolve({ data: { code: 0, data: { old: true } }, config: request, status: 200, statusText: 'OK', headers: new AxiosHeaders() })
    expect(await result).toHaveProperty('error')
    expect(store.accessToken).toBe('new-token')
  })

  it('never replays an old 401 with a new session token', async () => {
    const response = deferred()
    let request!: InternalAxiosRequestConfig
    const adapter = vi.fn(config => { request = config; return response.promise })
    instance.defaults.adapter = adapter
    const store = useAuthStore()
    store.accessToken = 'old-token'
    const reading = get('/accounts').catch(error => error)
    await flushWork()
    vi.mocked(authApi.login).mockResolvedValue({ access_token: 'new-token', expires_in: 900 })
    await store.login('password')
    response.reject(new AxiosError('expired', '401', request, undefined, { data: { code: 40102 }, config: request, status: 401, statusText: 'Unauthorized', headers: new AxiosHeaders() }))
    await reading
    expect(adapter).toHaveBeenCalledTimes(1)
    expect(authApi.refresh).not.toHaveBeenCalled()
    expect(store.accessToken).toBe('new-token')
  })
})


describe('request refresh coordination', () => {
  beforeEach(() => { setActivePinia(createPinia()); vi.clearAllMocks() })
  function expired(config: InternalAxiosRequestConfig) {
    return new AxiosError('expired', '401', config, undefined, { data: { code: 40102 }, config, status: 401, statusText: 'Unauthorized', headers: new AxiosHeaders() })
  }

  it('does not replay or redirect when a new login overtakes a pending refresh', async () => {
    const refresh = deferred()
    vi.mocked(authApi.refresh).mockReturnValue(refresh.promise)
    const adapter = vi.fn(config => Promise.reject(expired(config)))
    instance.defaults.adapter = adapter
    const store = useAuthStore()
    store.accessToken = 'old-token'
    const reading = get('/accounts').catch(error => error)
    await flushWork()
    vi.mocked(authApi.login).mockResolvedValue({ access_token: 'new-token', expires_in: 900 })
    await store.login('password')
    refresh.resolve({ access_token: 'late-old-refresh' })
    await reading
    expect(adapter).toHaveBeenCalledTimes(1)
    expect(store.accessToken).toBe('new-token')
    expect(router.replace).not.toHaveBeenCalled()
  })

  it('shares one current-session refresh and replays both requests with the renewed token', async () => {
    const refresh = deferred()
    vi.mocked(authApi.refresh).mockReturnValue(refresh.promise)
    instance.defaults.adapter = config => config.headers.get('Authorization') === 'Bearer renewed-token'
      ? Promise.resolve({ data: { code: 0, data: config.url }, config, status: 200, statusText: 'OK', headers: new AxiosHeaders() })
      : Promise.reject(expired(config))
    const store = useAuthStore()
    store.accessToken = 'old-token'
    const reading = Promise.all([get('/accounts'), get('/statistics/overview')])
    await flushWork()
    expect(authApi.refresh).toHaveBeenCalledTimes(1)
    refresh.resolve({ access_token: 'renewed-token' })
    expect(await reading).toEqual(['/accounts', '/statistics/overview'])
    expect(store.accessToken).toBe('renewed-token')
  })

  it('expires the current session and redirects when its own refresh fails', async () => {
    vi.mocked(authApi.refresh).mockRejectedValue(new Error('refresh revoked'))
    instance.defaults.adapter = config => Promise.reject(expired(config))
    const store = useAuthStore()
    store.accessToken = 'expired-token'
    await expect(get('/accounts')).rejects.toThrow()
    expect(store.accessToken).toBeNull()
    expect(router.replace).toHaveBeenCalledWith('/login?reason=expired')
  })
})
