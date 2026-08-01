import { get, post, put, del } from '@/utils/request'

export interface Transaction {
  id: string
  type: 'income' | 'expense' | 'transfer'
  amount: number
  account_id: string
  category_id: string | null
  transaction_date: string
  remark: string
  images: string
  tags: string
  to_account_id: string | null
  member_id?: string | null
  paid_by_member_id?: string | null
  source: string
  reminder_id?: string | null
  lending_id?: string | null
  recurring_id: string | null
  // Nested objects from backend
  account?: {
    id: string
    name: string
    type: string
    icon: string
    color: string
  }
  category?: {
    id: string
    name: string
    type: string
    icon: string
    color: string
  }
  to_account?: {
    id: string
    name: string
  }
  // Computed getters for backwards compatibility
  account_name?: string
  category_name?: string
  category_icon?: string
  category_color?: string
}

export interface TransactionListResponse {
  list: Transaction[]
  total: number
  page: number
  page_size: number
}

export interface TransactionListParams {
  page?: number
  page_size?: number
  start_date?: string
  end_date?: string
  type?: string
  account_id?: string
  category_id?: string
  keyword?: string
}

export interface CreateTransactionParams {
  type: 'income' | 'expense' | 'transfer'
  amount: number
  account_id: string
  to_account_id?: string
  category_id?: string
  transaction_date: string
  remark?: string
  images?: string
  tags?: string
  member_id?: string
  paid_by_member_id?: string
}

export const transactionApi = {
  getList(params?: TransactionListParams): Promise<TransactionListResponse> {
    return get<TransactionListResponse>('/transactions', { params })
  },

  getById(id: string): Promise<Transaction> {
    return get<Transaction>(`/transactions/${id}`)
  },

  create(params: CreateTransactionParams): Promise<Transaction> {
    return post<Transaction>('/transactions', params)
  },

  update(id: string, params: CreateTransactionParams): Promise<Transaction> {
    return put<Transaction>(`/transactions/${id}`, params)
  },

  delete(id: string): Promise<void> {
    return del<void>(`/transactions/${id}`)
  },

  batchDelete(ids: string[]): Promise<void> {
    return post<void>('/transactions/batch-delete', { ids })
  }
}
