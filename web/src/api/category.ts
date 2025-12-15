import { get, post, put, del } from '@/utils/request'

export interface Category {
  id: string
  name: string
  type: 'income' | 'expense'
  icon: string
  color: string
  is_system: boolean
  sort_order: number
}

export interface CreateCategoryParams {
  name: string
  type: 'income' | 'expense'
  icon?: string
  color?: string
}

export interface UpdateCategoryParams {
  name?: string
  icon?: string
  color?: string
}

interface CategoryListResponse {
  list: Category[]
}

export const categoryApi = {
  async getList(type?: 'income' | 'expense'): Promise<Category[]> {
    const res = await get<CategoryListResponse>('/categories', { params: { type } })
    return res.list || []
  },

  getById(id: string): Promise<Category> {
    return get<Category>(`/categories/${id}`)
  },

  create(params: CreateCategoryParams): Promise<Category> {
    return post<Category>('/categories', params)
  },

  update(id: string, params: UpdateCategoryParams): Promise<Category> {
    return put<Category>(`/categories/${id}`, params)
  },

  delete(id: string): Promise<void> {
    return del<void>(`/categories/${id}`)
  }
}
