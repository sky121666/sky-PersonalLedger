import { get, post, put, del, patch } from '@/utils/request'

export type AccountType = 
  | 'cash' | 'bank_card' | 'alipay' | 'wechat' | 'savings' | 'investment' 
  | 'fund' | 'stock' | 'crypto' | 'prepaid' | 'qq_pay' | 'jd_pay' | 'apple_pay'
  | 'credit' | 'loan' | 'mortgage' | 'car_loan' | 'consumer_loan' 
  | 'huabei' | 'baitiao' | 'other'

export const DEBT_ACCOUNT_TYPES: AccountType[] = [
  'credit', 'loan', 'mortgage', 'car_loan', 'consumer_loan', 'huabei', 'baitiao'
]

export function isDebtAccount(type: string): boolean {
  return DEBT_ACCOUNT_TYPES.includes(type as AccountType)
}

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
  payment_day?: number
  billing_day?: number
  credit_limit?: number
  interest_rate?: number
  start_date?: string
  target_date?: string
  remark?: string
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
    return put<Account>(`/accounts/${id}`, params)
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
