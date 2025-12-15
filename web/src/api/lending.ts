import { get, post, put, del } from '@/utils/request'

export interface Lending {
  id: string
  user_id: number
  type: 'lend_out' | 'borrow_in'
  contact_name: string
  contact_phone?: string
  contact_remark?: string
  principal: number
  interest_rate?: number
  current_balance: number
  total_repaid: number
  lend_date: string
  due_date?: string
  settled_at?: string
  account_id?: string
  remark?: string
  evidence?: string
  is_settled: boolean
  created_at: string
  updated_at: string
  account?: any
}

export interface LendingRecord {
  id: string
  lending_id: string
  user_id: number
  type: 'repay' | 'additional'
  amount: number
  record_date: string
  account_id?: string
  transaction_id?: string
  remark?: string
  evidence?: string
  created_at: string
  updated_at: string
  account?: any
  transaction?: any
}

export interface LendingSummary {
  total_lend_out: number
  total_borrow_in: number
  active_lend_out: number
  active_borrow_in: number
  settled_lend_out: number
  settled_borrow_in: number
  total_receivable: number
  total_payable: number
  net_lending: number
}

export interface CreateLendingParams {
  type: 'lend_out' | 'borrow_in'
  contact_name: string
  contact_phone?: string
  contact_remark?: string
  principal: number
  interest_rate?: number
  lend_date: string
  due_date?: string
  account_id?: string
  remark?: string
  evidence?: string
  create_transaction?: boolean
}

export interface UpdateLendingParams {
  contact_name: string
  contact_phone?: string
  contact_remark?: string
  interest_rate?: number
  due_date?: string
  remark?: string
  evidence?: string
}

export interface RecordRepaymentParams {
  amount: number
  record_date: string
  account_id?: string
  remark?: string
  evidence?: string
  create_transaction?: boolean
}

export const lendingApi = {
  list(includeSettled = false): Promise<Lending[]> {
    return get<Lending[]>('/lendings', {
      params: { include_settled: includeSettled }
    })
  },

  getById(id: string): Promise<Lending> {
    return get<Lending>(`/lendings/${id}`)
  },

  create(params: CreateLendingParams): Promise<Lending> {
    return post<Lending>('/lendings', params)
  },

  update(id: string, params: UpdateLendingParams): Promise<Lending> {
    return put<Lending>(`/lendings/${id}`, params)
  },

  delete(id: string): Promise<void> {
    return del<void>(`/lendings/${id}`)
  },

  recordRepayment(id: string, params: RecordRepaymentParams): Promise<Lending> {
    return post<Lending>(`/lendings/${id}/repay`, params)
  },

  getRecords(id: string): Promise<LendingRecord[]> {
    return get<LendingRecord[]>(`/lendings/${id}/records`)
  },

  getSummary(): Promise<LendingSummary> {
    return get<LendingSummary>('/lendings/summary')
  }
}
