import { get, post, del } from '@/utils/request'

export interface APIToken {
  id: number
  name: string
  token_prefix: string
  last_used_at: string | null
  expires_at: string | null
  created_at: string
}

export interface APITokenResponse {
  id: number
  name: string
  token: string
  token_prefix: string
  expires_at: string | null
  created_at: string
}

export interface CreateTokenRequest {
  name: string
  expires_in_days?: number
}

interface APITokenListResponse {
  list: APIToken[]
}

export const apiTokenApi = {
  list(): Promise<APITokenListResponse> {
    return get<APITokenListResponse>('/api-tokens')
  },

  create(data: CreateTokenRequest): Promise<APITokenResponse> {
    return post<APITokenResponse>('/api-tokens', data)
  },

  delete(id: number): Promise<void> {
    return del<void>(`/api-tokens/${id}`)
  }
}
