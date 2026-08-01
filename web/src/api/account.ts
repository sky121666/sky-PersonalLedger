import { get, post, put, del, patch } from '@/utils/request'
import type { AccountType } from '@/utils/accountTypeRules'

export type { AccountType } from '@/utils/accountTypeRules'
export { DEBT_ACCOUNT_TYPES, isDebtAccount } from '@/utils/accountTypeRules'

export interface Account {
  id: string
  name: string
  type: AccountType
  icon: string
  color: string
  initial_balance: number
  current_balance: number
  payment_day?: number
  billing_day?: number
  credit_limit?: number
  interest_rate?: number
  total_paid: number
  start_date?: string
  target_date?: string
  paid_off_at?: string
  remark?: string
  is_archived: boolean
  sort_order: number
}

export interface AccountListResponse {
  list: Account[]
  total_assets: number
  total_liabilities: number
  net_assets: number
}

export interface CreateAccountParams {
  name: string
  type: AccountType
  icon?: string
  color?: string
  initial_balance: number
  payment_day?: number
  billing_day?: number
  credit_limit?: number
  interest_rate?: number
  start_date?: string
  target_date?: string
  remark?: string
}

export interface UpdateAccountParams {
  name?: string
  icon?: string
  color?: string
	payment_day?: number | null
	billing_day?: number | null
	credit_limit?: number | null
	interest_rate?: number | null
	start_date?: string | null
	target_date?: string | null
	remark?: string | null
}

export const accountApi = {
  getList(includeArchived = false): Promise<AccountListResponse> {
    return get<AccountListResponse>('/accounts', {
      params: { include_archived: includeArchived }
    })
  },

  getById(id: string): Promise<Account> {
    return get<Account>(`/accounts/${id}`)
  },

  create(params: CreateAccountParams): Promise<Account> {
    return post<Account>('/accounts', params)
  },

	update(id: string, params: UpdateAccountParams): Promise<Account> {
		return patch<Account>(`/accounts/${id}`, params)
  },

  delete(id: string): Promise<void> {
    return del<void>(`/accounts/${id}`)
  },

  archive(id: string, isArchived: boolean): Promise<void> {
    return patch<void>(`/accounts/${id}/archive`, { is_archived: isArchived })
  },

  updateSort(ids: string[]): Promise<void> {
    return put<void>('/accounts/sort', { ids })
  },
}
