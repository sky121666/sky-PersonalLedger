import axios, {
  type AxiosRequestConfig,
  type AxiosResponse,
  type InternalAxiosRequestConfig,
} from 'axios'
import { useAuthStore } from '@/stores/auth'
import router from '@/router'
import { createRefreshCoordinator } from '@/utils/refreshCoordinator'
import {
  decideTokenRefreshAction,
  decideUnauthorizedFallback
} from '@/utils/tokenRefreshPolicy'

const instance = axios.create({
  baseURL: '/api/v1',
  timeout: 10000,
  withCredentials: true,
  xsrfCookieName: 'ledger_csrf_token',
  xsrfHeaderName: 'X-CSRF-Token',
  headers: {
    'Content-Type': 'application/json'
  }
})

interface RetryableRequestConfig extends InternalAxiosRequestConfig {
  _retry?: boolean
  _sessionGeneration?: number
}

const refreshCoordinators = new Map<number, ReturnType<typeof createRefreshCoordinator>>()

function sessionChangedError() {
  return new Error('会话已变更，请重新操作')
}

instance.interceptors.request.use(
  (config) => {
    const authStore = useAuthStore()
    const request = config as RetryableRequestConfig
    if (request._sessionGeneration !== undefined && request._sessionGeneration !== authStore.sessionGeneration) {
      throw sessionChangedError()
    }
    request._sessionGeneration = authStore.sessionGeneration
    if (authStore.accessToken) {
      config.headers.Authorization = `Bearer ${authStore.accessToken}`
    }
    return config
  },
  (error) => { throw error },
  { synchronous: true }
)

instance.interceptors.response.use(
  (response: AxiosResponse) => {
    const config = response.config as RetryableRequestConfig
    // Logout deliberately invalidates its own local session immediately.
    if (config._sessionGeneration !== useAuthStore().sessionGeneration && !config.url?.endsWith('/auth/logout')) {
      return Promise.reject(sessionChangedError())
    }
    if (response.config.responseType === 'blob') {
      return response
    }
    const data = response.data
    if (data.code !== 0) {
      return Promise.reject(new Error(data.message || 'Request failed'))
    }
    return data.data
  },
  async (error) => {
    const originalRequest = error.config as RetryableRequestConfig | undefined
    const authStore = useAuthStore()
    const generation = originalRequest?._sessionGeneration
    if (generation !== undefined && generation !== authStore.sessionGeneration) {
      return Promise.reject(sessionChangedError())
    }

    // Handle 401 Unauthorized
    if (error.response?.status === 401) {
      const isSilentBootstrap = originalRequest?.headers.get('X-Session-Bootstrap') === '1'
      if (isSilentBootstrap) {
        return Promise.reject(new Error('未找到可恢复的浏览器会话'))
      }

      const refreshAction = originalRequest
        ? decideTokenRefreshAction({
            status: error.response.status,
            code: error.response?.data?.code,
            requestUrl: originalRequest.url,
            alreadyRetried: originalRequest._retry,
            requestAuthorization: originalRequest.headers.get('Authorization'),
            currentAccessToken: authStore.accessToken
          })
        : 'reject'

      // Token expired, try refresh
      if (originalRequest && refreshAction !== 'reject') {
        originalRequest._retry = true

        if (refreshAction === 'retry-with-current-token' && authStore.accessToken) {
          originalRequest.headers.Authorization = `Bearer ${authStore.accessToken}`
          return instance(originalRequest)
        }

        let success = false
        try {
          const session = authStore.sessionGeneration
          let coordinator = refreshCoordinators.get(session)
          if (!coordinator) {
            coordinator = createRefreshCoordinator()
            refreshCoordinators.set(session, coordinator)
          }
          try {
            success = await coordinator.run(() => authStore.sessionGeneration === session
              ? authStore.refresh(false, () => { void router.replace('/login?reason=expired') })
              : Promise.resolve(false))
          } finally {
            if (refreshCoordinators.get(session) === coordinator) refreshCoordinators.delete(session)
          }
        } catch {
          success = false
        }

        if (generation !== authStore.sessionGeneration) return Promise.reject(sessionChangedError())
        if (success && authStore.accessToken) {
          originalRequest.headers.Authorization = `Bearer ${authStore.accessToken}`
          return instance(originalRequest)
        }
      }

      const fallback = decideUnauthorizedFallback({
        status: error.response.status,
        code: error.response?.data?.code,
        requestUrl: originalRequest?.url
      })
      if (fallback.type === 'return-safe-error') {
        return Promise.reject(new Error(fallback.message))
      }

      authStore.clearSession()
      void router.replace('/login?reason=expired')
      return Promise.reject(new Error('登录已过期，请重新登录'))
    }

    // Handle rate limiting (429)
    if (error.response?.status === 429) {
      const retryAfter = error.response.headers['retry-after'] || 60
      return Promise.reject(new Error(`请求过于频繁，请 ${retryAfter} 秒后再试`))
    }

    // Handle API token error (403)
    if (error.response?.status === 403 && error.response?.data?.code === 40300) {
      return Promise.reject(new Error('API Token 无效或缺失'))
    }

    const message = error.response?.data?.message || (error.response ? '请求失败' : '网络连接失败')
    return Promise.reject(new Error(message))
  }
)

export function get<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
  return instance.get(url, config) as Promise<T>
}

export function post<T>(url: string, data?: unknown, config?: AxiosRequestConfig): Promise<T> {
  return instance.post(url, data, config) as Promise<T>
}

export function put<T>(url: string, data?: unknown, config?: AxiosRequestConfig): Promise<T> {
  return instance.put(url, data, config) as Promise<T>
}

export function del<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
  return instance.delete(url, config) as Promise<T>
}

export function patch<T>(url: string, data?: unknown, config?: AxiosRequestConfig): Promise<T> {
  return instance.patch(url, data, config) as Promise<T>
}

export function postForm<T>(url: string, data: FormData, config?: AxiosRequestConfig): Promise<T> {
  return instance.post(url, data, {
    ...config,
    headers: {
      ...(config?.headers || {}),
      'Content-Type': 'multipart/form-data'
    }
  }) as Promise<T>
}

export function getRaw(url: string, config?: AxiosRequestConfig): Promise<AxiosResponse<Blob>> {
  return instance.get(url, {
    ...config,
    responseType: 'blob'
  }) as Promise<AxiosResponse<Blob>>
}

export default instance
