import { get, post, put } from '@/utils/request'

export interface AuthStatus {
  initialized: boolean
}

export interface AuthResponse {
  access_token: string
  refresh_token: string
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
    return post<AuthResponse>('/auth/init', { password })
  },

  login(password: string): Promise<AuthResponse> {
    return post<AuthResponse>('/auth/login', { password })
  },

  refresh(refreshToken: string): Promise<AuthResponse> {
    return post<AuthResponse>('/auth/refresh', { refresh_token: refreshToken })
  },

  logout(): Promise<void> {
    return post<void>('/auth/logout')
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
