import { get, post, put, del, patch } from '@/utils/request'

export type LoanType = 'credit_card' | 'mortgage' | 'car_loan' | 'consumer_loan' | 'other'

export interface Reminder {
  id: string
  name: string
  account_id?: string
  loan_type: LoanType
  payment_day: number
  billing_day?: number
  advance_days: number
  amount?: number
  principal?: number
  current_balance?: number
  interest_rate?: number
  total_interest?: number
  total_paid: number
  interest_paid: number
  start_date?: string
  target_date?: string
  paid_off_at?: string
  color: string
  remark: string
  evidence: string
  is_enabled: boolean
  created_at: string
  account?: { id: string; name: string }
}

export interface CreateReminderParams {
  name: string
  account_id?: string
  loan_type: LoanType
  payment_day: number
  billing_day?: number
  advance_days?: number
  amount?: number
  principal?: number
  current_balance?: number
  interest_rate?: number
  total_interest?: number
  start_date?: string
  target_date?: string
  color?: string
  remark?: string
  evidence?: string
}

export interface DebtSummary {
  total_debt: number
  total_paid: number
  total_principal: number
  progress: number
  active_loans: number
  paid_off_loans: number
  next_payment_day: number
  next_payment_name: string
  days_until_next: number
}

export const reminderApi = {
  async getList(accountId?: string): Promise<Reminder[]> {
    const url = accountId ? `/reminders?account_id=${accountId}` : '/reminders'
    const res = await get<Reminder[]>(url)
    return Array.isArray(res) ? res : []
  },

  getById(id: string): Promise<Reminder> {
    return get<Reminder>(`/reminders/${id}`)
  },

  create(params: CreateReminderParams): Promise<Reminder> {
    return post<Reminder>('/reminders', params)
  },

  update(id: string, params: CreateReminderParams): Promise<Reminder> {
    return put<Reminder>(`/reminders/${id}`, params)
  },

  delete(id: string): Promise<void> {
    return del<void>(`/reminders/${id}`)
  },

  toggle(id: string): Promise<Reminder> {
    return patch<Reminder>(`/reminders/${id}/toggle`, {})
  },

  recordPayment(
    id: string,
    amount: number,
    accountId?: string,
    principalAmount?: number,
    interestAmount?: number
  ): Promise<Reminder> {
    return post<Reminder>(`/reminders/${id}/payment`, {
      amount,
      account_id: accountId,
      principal_amount: principalAmount,
      interest_amount: interestAmount
    })
  },

  getDebtSummary(): Promise<DebtSummary> {
    return get<DebtSummary>('/debt/summary')
  }
}
