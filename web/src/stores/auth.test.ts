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
