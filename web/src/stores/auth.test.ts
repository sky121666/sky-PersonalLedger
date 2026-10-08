import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { authApi } from '@/api/auth'
import { useAuthStore } from './auth'

vi.mock('@/api/auth', () => ({
  authApi: {
    getStatus: vi.fn(),
    login: vi.fn(),
    init: vi.fn(),
    refresh: vi.fn(),
    logout: vi.fn(),
  },
}))

describe('auth store session cleanup', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
  })

  function seedSession() {
    const store = useAuthStore()
    store.accessToken = 'access-token'
    return store
  }

  it('revokes the server session before clearing a local session', async () => {
    vi.mocked(authApi.logout).mockResolvedValue(undefined)
    const store = seedSession()

    await store.logout()

    expect(authApi.logout).toHaveBeenCalledTimes(1)
    expect(store.accessToken).toBeNull()
  })

  it('clears the local session when server revocation fails', async () => {
    vi.mocked(authApi.logout).mockRejectedValue(new Error('offline'))
    const store = seedSession()

    await expect(store.logout()).rejects.toThrow('offline')
    expect(authApi.logout).toHaveBeenCalledTimes(1)
    expect(store.accessToken).toBeNull()
  })

  it('clears a passive session without calling the logout API', () => {
    const store = seedSession()

    store.clearSession()

    expect(authApi.logout).not.toHaveBeenCalled()
    expect(store.accessToken).toBeNull()
  })

  it('restores an access token from the HttpOnly-cookie session on reload', async () => {
    vi.mocked(authApi.getStatus).mockResolvedValue({ initialized: true })
    vi.mocked(authApi.refresh).mockResolvedValue({
      access_token: 'restored-access-token',
      expires_in: 900,
    })
    const store = useAuthStore()

    await store.checkAuth()

    expect(authApi.refresh).toHaveBeenCalledWith(true)
    expect(store.accessToken).toBe('restored-access-token')
    expect(store.isLoggedIn).toBe(true)
  })

  it('keeps the browser logged out when no refresh cookie can restore a session', async () => {
    vi.mocked(authApi.getStatus).mockResolvedValue({ initialized: true })
    vi.mocked(authApi.refresh).mockRejectedValue(new Error('no cookie'))
    const store = useAuthStore()

    await store.checkAuth()

    expect(store.accessToken).toBeNull()
    expect(store.isLoggedIn).toBe(false)
  })
})

describe('auth response session identity', () => {
  beforeEach(() => { setActivePinia(createPinia()); vi.clearAllMocks() })
  function pending() {
    let resolve!: (value: any) => void, reject!: (error: Error) => void
    const promise = new Promise<any>((yes, no) => { resolve = yes; reject = no })
    return { promise, resolve, reject }
  }

  it('does not restore a late refresh after logout', async () => {
    const response = pending()
    vi.mocked(authApi.refresh).mockReturnValue(response.promise)
    vi.mocked(authApi.logout).mockResolvedValue(undefined)
    const store = useAuthStore()
    store.accessToken = 'old-session'
    const refreshing = store.refresh()
    await store.logout()
    response.resolve({ access_token: 'late-access' })
    expect(await refreshing).toBe(false)
    expect(store.isLoggedIn).toBe(false)
  })

  it('does not clear a new login when an old refresh fails', async () => {
    const response = pending()
    vi.mocked(authApi.refresh).mockReturnValue(response.promise)
    vi.mocked(authApi.login).mockResolvedValue({ access_token: 'new-access', expires_in: 900 })
    const store = useAuthStore()
    store.accessToken = 'old-session'
    const refreshing = store.refresh()
    await store.login('password')
    response.reject(new Error('old refresh failed'))
    await refreshing
    expect(store.accessToken).toBe('new-access')
  })

  it('does not let a slow logout clear a newer login', async () => {
    const response = pending()
    vi.mocked(authApi.logout).mockReturnValue(response.promise)
    vi.mocked(authApi.login).mockResolvedValue({ access_token: 'new-access', expires_in: 900 })
    const store = useAuthStore()
    store.accessToken = 'old-session'
    const loggingOut = store.logout()
    expect(store.accessToken).toBeNull()
    await store.login('password')
    response.resolve(undefined)
    await loggingOut
    expect(store.accessToken).toBe('new-access')
  })
})

describe('pending login boundary', () => {
  it('stops using the previous token while a replacement login is pending', async () => {
    setActivePinia(createPinia())
    let resolve!: (result: any) => void
    vi.mocked(authApi.login).mockReturnValue(new Promise(yes => { resolve = yes }))
    const store = useAuthStore()
    store.accessToken = 'previous-token'
    const login = store.login('password')
    expect(store.accessToken).toBeNull()
    resolve({ access_token: 'new-token' })
    await login
    expect(store.accessToken).toBe('new-token')
  })
})

describe('logout boundary failure', () => {
  it('still clears the session when the logout request cannot start', async () => {
    setActivePinia(createPinia())
    vi.mocked(authApi.logout).mockImplementation(() => { throw Error('could not dispatch') })
    const store = useAuthStore()
    store.accessToken = 'old-token'
    await expect(store.logout()).rejects.toThrow('could not dispatch')
    expect(store.accessToken).toBeNull()
  })
})
