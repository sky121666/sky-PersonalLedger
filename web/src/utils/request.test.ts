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

describe('request rate limiting', () => {
  beforeEach(() => { setActivePinia(createPinia()) })
  it.each([
    [{}, { retry_after: 1800 }, 1800],
    [{ 'retry-after': '90' }, { retry_after: 1800 }, 90],
    [{ 'retry-after': 'invalid' }, { retry_after: 1800 }, 1800],
    [{}, {}, 60],
  ])('uses a valid header or legacy body delay', async (headers, data, seconds) => {
    instance.defaults.adapter = config => Promise.reject(new AxiosError('limited', '429', config, undefined, {
      status: 429, statusText: 'Too Many Requests', config, data, headers: new AxiosHeaders(headers),
    }))
    await expect(get('/test')).rejects.toThrow(`请求过于频繁，请 ${seconds} 秒后再试`)
  })
})

describe('safe HTTP error status', () => {
  beforeEach(() => { setActivePinia(createPinia()) })

  it('retains a numeric business conflict code without exposing transport data', async () => {
    instance.defaults.adapter = config => Promise.reject(new AxiosError('conflict', '409', config, undefined, {
      status: 409, statusText: 'Conflict', config,
      data: { code: 40903, message: 'idempotency conflict' }, headers: new AxiosHeaders(),
    }))
    await expect(get('/test')).rejects.toMatchObject({ status: 409, code: 40903 })
  })

  it.each([400, 409, 429, 500])('preserves status %s without exposing request headers or response objects', async status => {
    instance.defaults.adapter = config => Promise.reject(new AxiosError('failure', String(status), config, undefined, {
      status, statusText: 'Failure', config, data: { message: 'request rejected' }, headers: new AxiosHeaders(),
    }))
    const error = await get('/test').catch(error => error)
    expect(error).toMatchObject({ status })
    expect(error).not.toHaveProperty('config')
    expect(error).not.toHaveProperty('response')
    expect(error).not.toHaveProperty('headers')
  })

  it('does not invent an HTTP status for network failures', async () => {
    instance.defaults.adapter = config => Promise.reject(new AxiosError('network failure', 'ERR_NETWORK', config))
    const error = await get('/test').catch(error => error)
    expect(error).toBeInstanceOf(Error)
    expect(error).not.toHaveProperty('status')
  })
})

describe('blob HTTP errors', () => {
  beforeEach(() => { setActivePinia(createPinia()); vi.clearAllMocks() })

  function failBackup(data: Blob) {
    instance.defaults.adapter = config => Promise.reject(new AxiosError('backup failure', 'ERR_BAD_REQUEST', config, undefined, {
      status: 409, statusText: 'Conflict', config, data, headers: new AxiosHeaders(),
    }))
  }

  it('preserves a JSON blob message and status without exposing transport details', async () => {
    failBackup(new Blob([JSON.stringify({
      message: 'Backup attachments are missing',
      config: { private: true }, headers: { private: true }, response: { private: true },
    })], { type: 'application/json' }))

    const error = await get('/backup', { responseType: 'blob' }).catch(error => error)
    expect(error).toBeInstanceOf(Error)
    expect(error).toMatchObject({ message: 'Backup attachments are missing', status: 409 })
    expect(error).not.toHaveProperty('config')
    expect(error).not.toHaveProperty('headers')
    expect(error).not.toHaveProperty('response')
  })

  it.each(['not JSON', 'null', '{"message":{"private":true}}', '{"message":""}', '{"message":"   "}'])(
    'falls back safely for an invalid blob body: %s', async body => {
      failBackup(new Blob([body], { type: 'application/json' }))
      await expect(get('/backup', { responseType: 'blob' })).rejects.toMatchObject({ message: '请求失败', status: 409 })
    },
  )

  it('falls back safely when the blob cannot be read', async () => {
    const data = new Blob()
    vi.spyOn(data, 'text').mockRejectedValue(new Error('private read failure'))
    failBackup(data)
    await expect(get('/backup', { responseType: 'blob' })).rejects.toMatchObject({ message: '请求失败', status: 409 })
  })

  it.each(['resolved', 'rejected'] as const)('discards old-session details when blob reading is %s', async outcome => {
    const text = deferred<string>()
    void text.promise.catch(() => {})
    const data = new Blob()
    vi.spyOn(data, 'text').mockReturnValue(text.promise)
    failBackup(data)
    const store = useAuthStore()
    const reading = get('/backup', { responseType: 'blob' }).catch(error => error)
    await flushWork()

    store.clearSession()
    if (outcome === 'resolved') text.resolve('{"message":"Old session backup details"}')
    else text.reject(new Error('Old session read details'))

    const error = await reading
    expect(error).toBeInstanceOf(Error)
    expect(error).toMatchObject({ message: '会话已变更，请重新操作' })
    expect(error).not.toHaveProperty('status')
    expect(error).not.toHaveProperty('config')
    expect(error).not.toHaveProperty('headers')
    expect(error).not.toHaveProperty('response')
    expect(authApi.refresh).not.toHaveBeenCalled()
    expect(router.replace).not.toHaveBeenCalled()
  })
})

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
