import { describe, expect, it } from 'vitest'
import {
  decideTokenRefreshAction,
  decideUnauthorizedFallback,
  shouldAttemptTokenRefresh,
  shouldRetryWithCurrentAccessToken
} from './tokenRefreshPolicy'

describe('shouldAttemptTokenRefresh', () => {
  it.each([
    '/auth/status',
    '/auth/init',
    '/auth/login',
    '/auth/refresh',
    '/api/v1/auth/refresh',
    'https://example.test/api/v1/auth/refresh'
  ])('does not recursively refresh a session endpoint: %s', (requestUrl) => {
    expect(shouldAttemptTokenRefresh({
      status: 401,
      code: 40102,
      requestUrl
    })).toBe(false)
  })

  it('allows an expired protected request to start one refresh attempt', () => {
    expect(shouldAttemptTokenRefresh({
      status: 401,
      code: 40102,
      requestUrl: '/transactions'
    })).toBe(true)
  })

  it('allows logout to refresh and retry so the server session can be revoked', () => {
    expect(shouldAttemptTokenRefresh({
      status: 401,
      code: 40102,
      requestUrl: '/auth/logout'
    })).toBe(true)
  })

  it('does not refresh a request that has already been retried', () => {
    expect(shouldAttemptTokenRefresh({
      status: 401,
      code: 40102,
      requestUrl: '/transactions',
      alreadyRetried: true
    })).toBe(false)
  })

  it('does not refresh a protected request for a non-expiry 40101 response', () => {
    expect(shouldAttemptTokenRefresh({
      status: 401,
      code: 40101,
      requestUrl: '/transactions'
    })).toBe(false)
  })
})

describe('late 401 handling', () => {
  it('retries a late old-token request with the current token instead of refreshing again', () => {
    const lateRequest = {
      status: 401,
      code: 40102,
      requestUrl: '/transactions',
      requestAuthorization: 'Bearer old-access-token',
      currentAccessToken: 'new-access-token'
    }

    expect(shouldRetryWithCurrentAccessToken(lateRequest)).toBe(true)
    expect(decideTokenRefreshAction(lateRequest)).toBe('retry-with-current-token')
  })

  it('starts refresh when the failed request used the current access token', () => {
    expect(decideTokenRefreshAction({
      status: 401,
      code: 40102,
      requestUrl: '/transactions',
      requestAuthorization: 'Bearer current-access-token',
      currentAccessToken: 'current-access-token'
    })).toBe('refresh')
  })

  it('never retries a refresh request recursively even if the access token changed', () => {
    expect(decideTokenRefreshAction({
      status: 401,
      code: 40102,
      requestUrl: '/auth/refresh',
      requestAuthorization: 'Bearer old-access-token',
      currentAccessToken: 'new-access-token'
    })).toBe('reject')
  })
})

describe('401 fallback semantics', () => {
  it.each([
    ['/auth/login', 40101, '密码错误，请重试'],
    ['/api/v1/auth/login', 40102, '密码错误，请重试'],
    ['https://example.test/api/v1/auth/init', 40101, '初始化认证失败，请重试'],
    ['/auth/init?source=setup', 40102, '初始化认证失败，请重试'],
    ['/api/v1/auth/status', 40101, '认证状态检查失败，请稍后重试'],
    ['https://example.test/api/v1/auth/status', 40102, '认证状态检查失败，请稍后重试']
  ])('returns a safe error without expiring the session for %s code %i', (
    requestUrl,
    code,
    message
  ) => {
    expect(decideUnauthorizedFallback({
      status: 401,
      code,
      requestUrl
    })).toEqual({ type: 'return-safe-error', message })
  })

  it.each([
    ['/auth/refresh', 40101],
    ['/api/v1/auth/refresh', 40102],
    ['https://example.test/api/v1/auth/refresh', 40101],
    ['/transactions', 40101],
    ['/api/v1/transactions', 40102],
    ['https://example.test/api/v1/transactions', 40102]
  ])('expires the session for %s code %i', (requestUrl, code) => {
    expect(decideUnauthorizedFallback({
      status: 401,
      code,
      requestUrl
    })).toEqual({ type: 'expire-session' })
  })
})
