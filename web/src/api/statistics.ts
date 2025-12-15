import { get } from '@/utils/request'

export interface OverviewResponse {
  income: number
  expense: number
  balance: number
  income_change: number
  expense_change: number
  daily_average: number
  transaction_count: number
}

export interface CategoryStatItem {
  category_id: string
  category_name: string
  icon: string
  color: string
  amount: number
  percentage: number
  count: number
}

export interface CategoryStatResponse {
  total: number
  items: CategoryStatItem[]
}

export interface TrendItem {
  date: string
  income: number
  expense: number
  balance: number
}

export interface TrendResponse {
  items: TrendItem[]
  total_income: number
  total_expense: number
}

export interface AssetTrendItem {
  month: string
  total_assets: number
  total_debts: number
  net_worth: number
  month_income: number
  month_expense: number
}

export interface AssetTrendResponse {
  items: AssetTrendItem[]
  current_assets: number
  current_debts: number
  current_net_worth: number
}

export const statisticsApi = {
  getOverview(month?: string): Promise<OverviewResponse> {
    return get<OverviewResponse>('/statistics/overview', { params: { month } })
  },

  getCategoryStats(month?: string, type?: string): Promise<CategoryStatResponse> {
    return get<CategoryStatResponse>('/statistics/categories', { params: { month, type } })
  },

  getTrend(month?: string): Promise<TrendResponse> {
    return get<TrendResponse>('/statistics/trend', { params: { month } })
  },

  getAssetTrend(months?: number): Promise<AssetTrendResponse> {
    return get<AssetTrendResponse>('/statistics/asset-trend', { params: { months } })
  }
}
