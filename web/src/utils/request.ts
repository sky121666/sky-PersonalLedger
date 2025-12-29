import axios, { type AxiosRequestConfig, type AxiosResponse } from 'axios'
import { useAuthStore } from '@/stores/auth'
import router from '@/router'

const instance = axios.create({
  baseURL: '/api/v1',
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json'
  }
})

let isRefreshing = false
let refreshSubscribers: ((token: string) => void)[] = []

function onRefreshed(token: string) {
  refreshSubscribers.forEach(callback => callback(token))
  refreshSubscribers = []
}

function addRefreshSubscriber(callback: (token: string) => void) {
  refreshSubscribers.push(callback)
}

instance.interceptors.request.use(
  (config) => {
    const authStore = useAuthStore()
    if (authStore.accessToken) {
      config.headers.Authorization = `Bearer ${authStore.accessToken}`
    }
    return config
  },
  (error) => Promise.reject(error)
)

instance.interceptors.response.use(
  (response: AxiosResponse) => {
    const data = response.data
    if (data.code !== 0) {
      return Promise.reject(new Error(data.message || 'Request failed'))
    }
    return data.data
  },
  async (error) => {
    const originalRequest = error.config
    const authStore = useAuthStore()

    // Handle 401 Unauthorized
    if (error.response?.status === 401) {
      // Token expired, try refresh
      if (error.response?.data?.code === 40102) {
        if (!isRefreshing) {
          isRefreshing = true
          const success = await authStore.refresh()
          isRefreshing = false

          if (success) {
            onRefreshed(authStore.accessToken!)
            originalRequest.headers.Authorization = `Bearer ${authStore.accessToken}`
            return instance(originalRequest)
          } else {
            authStore.logout()
            router.replace('/login?reason=expired')
            return Promise.reject(new Error('登录已过期，请重新登录'))
          }
        } else {
          return new Promise((resolve) => {
            addRefreshSubscriber((token: string) => {
              originalRequest.headers.Authorization = `Bearer ${token}`
              resolve(instance(originalRequest))
            })
          })
        }
      } else {
        // Other 401 errors (invalid token, etc.) - redirect to login
        authStore.logout()
        router.replace('/login?reason=expired')
        return Promise.reject(new Error('登录已过期，请重新登录'))
      }
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

    const message = error.response?.data?.message || error.message || 'Request failed'
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

export default instance
