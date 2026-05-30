import type { AxiosResponse } from 'axios'
import { get } from '@/utils/request'

export interface MonthlyData {
  month: string
  income: number
  expense: number
  balance: number
}

export interface CategoryStat {
  category_id: string
  category_name: string
  category_icon: string
  amount: number
  percentage: number
  count: number
}

export interface YearlyReport {
  year: number
  total_income: number
  total_expense: number
  net_savings: number
  savings_rate: number
  monthly_data: MonthlyData[]
  top_expenses: CategoryStat[]
  top_incomes: CategoryStat[]
  transaction_count: number
  average_expense: number
  average_income: number
  max_expense_month: string
  min_expense_month: string
  best_savings_month: string
  max_single_expense: number
  max_expense_remark: string
  active_days: number
  daily_avg_expense: number
}

export interface ExportFilter {
  start_date?: string
  end_date?: string
  type?: string
  account_id?: string
}

export const exportApi = {
  // Download transactions as CSV
  async downloadCSV(filter?: ExportFilter): Promise<void> {
    const params = new URLSearchParams()
    if (filter?.start_date) params.append('start_date', filter.start_date)
    if (filter?.end_date) params.append('end_date', filter.end_date)
    if (filter?.type) params.append('type', filter.type)
    if (filter?.account_id) params.append('account_id', filter.account_id)

    const response = await get<AxiosResponse<Blob>>('/export/transactions/csv', {
      params,
      responseType: 'blob'
    })
    const blob = response.data
    const downloadUrl = window.URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = downloadUrl
    a.download = `transactions_${new Date().toISOString().slice(0, 10)}.csv`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    window.URL.revokeObjectURL(downloadUrl)
  },

  // Get yearly report
  getYearlyReport(year?: number): Promise<YearlyReport> {
    const params = year ? { year: year.toString() } : {}
    return get<YearlyReport>('/export/report/yearly', { params })
  },

  // Get available years
  async getAvailableYears(): Promise<number[]> {
    const res = await get<{ years: number[] }>('/export/years')
    return res.years || []
  }
}
