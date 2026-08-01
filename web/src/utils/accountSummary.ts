import type { AccountListResponse } from '@/api/account'

export function accountSummaryTotals(data: Pick<AccountListResponse, 'total_assets' | 'total_liabilities'>) {
  return {
    totalAssets: Number.isFinite(data.total_assets) ? data.total_assets : 0,
    totalLiabilities: Number.isFinite(data.total_liabilities) ? data.total_liabilities : 0,
  }
}
