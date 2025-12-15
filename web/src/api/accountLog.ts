import { get } from '@/utils/request'

export interface AccountLog {
  id: string
  user_id: number
  account_id: string
  type: 'income' | 'expense' | 'transfer_in' | 'transfer_out' | 'rollback' | 'adjustment'
  amount: number
  balance_before: number
  balance_after: number
  transaction_id?: string
  reminder_id?: string
  lending_id?: string
  remark: string
  created_at: string
  account?: {
    id: string
    name: string
    icon: string
    color: string
  }
}

export interface AccountLogListResponse {
  list: AccountLog[]
  total: number
  page: number
  page_size: number
}

export interface AccountLogParams {
  page?: number
  page_size?: number
}

export const accountLogApi = {
  getAll(params?: AccountLogParams): Promise<AccountLogListResponse> {
    return get<AccountLogListResponse>('/account-logs', { params })
  },

  getByAccountId(accountId: string, params?: AccountLogParams): Promise<AccountLogListResponse> {
    return get<AccountLogListResponse>(`/account-logs/account/${accountId}`, { params })
  },
}
