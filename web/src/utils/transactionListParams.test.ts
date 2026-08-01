import { describe, expect, it } from 'vitest'

import { buildTransactionListParams } from './transactionListParams'

describe('buildTransactionListParams', () => {
  it('uses the backend snake_case date contract', () => {
    const params = buildTransactionListParams(2, 20, {
      type: 'expense',
      start_date: '2026-07-01',
      end_date: '2026-07-31',
      keyword: '午餐',
    })

    expect(params).toEqual({
      page: 2,
      page_size: 20,
      type: 'expense',
      start_date: '2026-07-01',
      end_date: '2026-07-31',
      keyword: '午餐',
    })
    expect(params).not.toHaveProperty('startDate')
    expect(params).not.toHaveProperty('endDate')
  })

  it('omits empty filters while preserving pagination', () => {
    expect(buildTransactionListParams(1, 20, {
      type: '',
      start_date: '',
      end_date: '',
      keyword: '',
    })).toEqual({
      page: 1,
      page_size: 20,
    })
  })
})
