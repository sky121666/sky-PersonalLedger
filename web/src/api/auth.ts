import type { AxiosRequestConfig } from 'axios'

import { get, post, put } from '@/utils/request'
import { setupAccessConfig } from '@/utils/setupAccess'

export interface AuthStatus {
  initialized: boolean
}

export interface AuthResponse {
  access_token: string
  refresh_token?: string
  expires_in: number
}

export interface UserProfile {
  id: number
  username: string
  nickname: string
  email: string
  avatar: string
  bio: string
  created_at: string
  last_login_at?: string
}

export interface UpdateProfileRequest {
  nickname: string
  email: string
  avatar: string
  bio: string
}

export const authApi = {
  getStatus(): Promise<AuthStatus> {
    return get<AuthStatus>('/auth/status')
  },

  init(password: string): Promise<AuthResponse> {
    return post<AuthResponse>(
      '/auth/init',
      { password },
      withBrowserSession(setupAccessConfig())
    )
  },

  login(password: string): Promise<AuthResponse> {
    return post<AuthResponse>('/auth/login', { password }, withBrowserSession())
  },

  refresh(silent = false): Promise<AuthResponse> {
    return post<AuthResponse>(
      '/auth/refresh',
      {},
      withBrowserSession(
        silent ? { headers: { 'X-Session-Bootstrap': '1' } } : undefined
      )
    )
  },

  logout(): Promise<void> {
    return post<void>('/auth/logout', undefined, withBrowserSession())
  },

  changePassword(oldPassword: string, newPassword: string): Promise<void> {
    return post<void>('/auth/change-password', {
      old_password: oldPassword,
      new_password: newPassword
    })
  },

  getProfile(): Promise<UserProfile> {
    return get<UserProfile>('/auth/profile')
  },

  updateProfile(data: UpdateProfileRequest): Promise<UserProfile> {
    return put<UserProfile>('/auth/profile', data)
  }
}

function withBrowserSession(config: AxiosRequestConfig = {}): AxiosRequestConfig {
  return {
    ...config,
    headers: {
      ...config.headers,
      'X-Refresh-Token-Mode': 'cookie'
    }
  }
}
