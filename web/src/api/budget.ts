import { get, post, del } from '@/utils/request'

export interface Budget {
  id: string
  category_id: string | null
  category_name?: string
  amount: number
  period: string
  alert_threshold: number
  is_active: boolean
  spent?: number
  percentage?: number
}

export interface BudgetListResponse {
  total_budget: Budget | null
  category_budgets: Budget[]
}

export interface OverLimit {
  name: string
  percentage: number
}

export interface BudgetSummary {
  total_amount: number
  total_spent: number
  percentage: number
  daily_available: number
  days_remaining: number
  over_budget_categories: OverLimit[]
}

export const budgetApi = {
  getList(): Promise<BudgetListResponse> {
    return get<BudgetListResponse>('/budgets')
  },

  getSummary(): Promise<BudgetSummary> {
    return get<BudgetSummary>('/budgets/summary')
  },

  setTotal(amount: number, alertThreshold?: number): Promise<Budget> {
    return post<Budget>('/budgets/total', {
      amount,
      alert_threshold: alertThreshold || 80
    })
  },

  setCategory(categoryId: string, amount: number, alertThreshold?: number): Promise<Budget> {
    return post<Budget>('/budgets/category', {
      category_id: categoryId,
      amount,
      alert_threshold: alertThreshold || 80
    })
  },

  delete(id: string): Promise<void> {
    return del<void>(`/budgets/${id}`)
  }
}
