import { get, post, put, del } from '@/utils/request'

export interface Tag {
  id: string
  user_id: number
  name: string
  color: string
  icon: string
  is_system: boolean
  used_count: number
  created_at: string
  updated_at: string
}

export interface CreateTagRequest {
  name: string
  color?: string
  icon?: string
}

export const tagApi = {
  list: () => get<Tag[]>('/tags'),
  
  getById: (id: string) => get<Tag>(`/tags/${id}`),
  
  create: (data: CreateTagRequest) => post<Tag>('/tags', data),
  
  update: (id: string, data: CreateTagRequest) => put<Tag>(`/tags/${id}`, data),
  
  delete: (id: string) => del(`/tags/${id}`),
}
