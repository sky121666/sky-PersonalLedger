const AUTH_ENDPOINTS_WITHOUT_AUTO_REFRESH = new Set([
  '/auth/status',
  '/auth/init',
  '/auth/login',
  '/auth/refresh'
])

const NON_SESSION_401_MESSAGES = new Map([
  ['/auth/login', '密码错误，请重试'],
  ['/auth/init', '初始化认证失败，请重试'],
  ['/auth/status', '认证状态检查失败，请稍后重试']
])

export interface TokenRefreshDecision {
  status?: number
  code?: number
  requestUrl?: string
  alreadyRetried?: boolean
  requestAuthorization?: unknown
  currentAccessToken?: string | null
}

export type TokenRefreshAction = 'reject' | 'refresh' | 'retry-with-current-token'
export type UnauthorizedFallbackAction =
  | { type: 'return-safe-error'; message: string }
  | { type: 'expire-session' }

function normalizeApiPath(url: string): string {
  const pathname = new URL(url, 'http://local.request').pathname
  return pathname.startsWith('/api/v1/')
    ? pathname.slice('/api/v1'.length)
    : pathname
}

export function shouldAttemptTokenRefresh({
  status,
  code,
  requestUrl,
  alreadyRetried
}: TokenRefreshDecision): boolean {
  if (status !== 401 || code !== 40102 || alreadyRetried || !requestUrl) {
    return false
  }

  return !AUTH_ENDPOINTS_WITHOUT_AUTO_REFRESH.has(normalizeApiPath(requestUrl))
}

export function shouldRetryWithCurrentAccessToken({
  requestAuthorization,
  currentAccessToken
}: Pick<TokenRefreshDecision, 'requestAuthorization' | 'currentAccessToken'>): boolean {
  if (typeof requestAuthorization !== 'string' || !currentAccessToken) {
    return false
  }

  const requestToken = requestAuthorization.match(/^Bearer\s+(.+)$/i)?.[1]
  return Boolean(requestToken && requestToken !== currentAccessToken)
}

export function decideTokenRefreshAction(
  decision: TokenRefreshDecision
): TokenRefreshAction {
  if (!shouldAttemptTokenRefresh(decision)) {
    return 'reject'
  }

  return shouldRetryWithCurrentAccessToken(decision)
    ? 'retry-with-current-token'
    : 'refresh'
}

export function decideUnauthorizedFallback({
  status,
  requestUrl
}: TokenRefreshDecision): UnauthorizedFallbackAction {
  if (status === 401 && requestUrl) {
    const message = NON_SESSION_401_MESSAGES.get(normalizeApiPath(requestUrl))
    if (message) {
      return { type: 'return-safe-error', message }
    }
  }

  return { type: 'expire-session' }
}
