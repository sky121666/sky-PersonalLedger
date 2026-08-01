import { del, get, post } from '@/utils/request'
import type { Transaction } from '@/api/transaction'

export interface QuickTemplate {
  id: string
  user_id: number
  name: string
  type: 'income' | 'expense'
  amount: number
  account_id: string
  category_id: string | null
  remark: string
  used_count: number
  last_used_at: string | null
  created_at: string
  updated_at: string
}

export interface CreateTemplateRequest {
  name: string
  type: 'income' | 'expense'
  amount: number
  account_id: string
  category_id?: string
  remark?: string
}

export interface ApplyTemplateRequest {
  transaction_date?: string
  amount?: number
}

interface TemplateListResponse {
  list: QuickTemplate[]
}

export const templateApi = {
  async list(): Promise<QuickTemplate[]> {
    const response = await get<TemplateListResponse>('/templates')
    return response.list || []
  },

  create(data: CreateTemplateRequest): Promise<QuickTemplate> {
    return post<QuickTemplate>('/templates', data)
  },

  delete(id: string): Promise<void> {
    return del<void>(`/templates/${id}`)
  },

  apply(id: string, data: ApplyTemplateRequest): Promise<Transaction> {
    return post<Transaction>(`/templates/${id}/apply`, data)
  },
}
