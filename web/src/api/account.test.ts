import { describe, expect, it } from 'vitest'

import { isDebtAccount } from '@/utils/accountTypeRules'
import { accountSummaryTotals } from '@/utils/accountSummary'
import { ACCOUNT_ICONS, ACCOUNT_TYPES } from '@/utils/constants'
import { toLedgerInstant } from '@/utils/ledgerDate'
import { formatLocalDate, formatLocalMonth } from '@/utils/localDate'

describe('account type rules', () => {
  it('classifies payable as debt and receivable as an asset', () => {
    expect(isDebtAccount('payable')).toBe(true)
    expect(isDebtAccount('receivable')).toBe(false)
  })

  it('uses the server-classified totals instead of recomputing signed balances', () => {
    expect(accountSummaryTotals({ total_assets: 140, total_liabilities: 125 })).toEqual({
      totalAssets: 140,
      totalLiabilities: 125,
    })
  })

  it('sends datetime-local input as an explicit UTC instant', () => {
    const encoded = toLedgerInstant('2026-05-31T23:30')
    expect(encoded.endsWith('Z')).toBe(true)
    expect(new Date(encoded).getTime()).toBe(new Date(2026, 4, 31, 23, 30).getTime())
  })

  it('has labels and icons for receivable and payable accounts', () => {
    expect(ACCOUNT_TYPES.receivable).toBe('应收款')
    expect(ACCOUNT_TYPES.payable).toBe('应付款')
    expect(ACCOUNT_ICONS.receivable).toBeTruthy()
    expect(ACCOUNT_ICONS.payable).toBeTruthy()
  })

  it('formats date-only filters from local calendar fields', () => {
    const local = new Date(2026, 4, 31, 23, 30)
    expect(formatLocalDate(local)).toBe('2026-05-31')
    expect(formatLocalMonth(local)).toBe('2026-05')
  })
})
