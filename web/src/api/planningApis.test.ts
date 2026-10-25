import { describe, expect, it, vi } from 'vitest'
import { get, post } from '@/utils/request'
import { reminderApi } from './reminder'
import { budgetApi } from './budget'

vi.mock('@/utils/request', () => ({ get: vi.fn(), post: vi.fn(), patch: vi.fn(), del: vi.fn() }))

describe('planning request contracts', () => {
  it('sends the repayment retry identity in the reminder payment JSON', async () => {
    await reminderApi.recordPayment('debt-1', 110, 'cash-1', 100, 10, 'payment-key')
    expect(post).toHaveBeenCalledWith('/reminders/debt-1/payment', {
      amount: 110, account_id: 'cash-1', principal_amount: 100, interest_amount: 10, idempotency_key: 'payment-key',
    })
  })

  it('sends the requested budget month as a query parameter', async () => {
    await budgetApi.getList('2026-04')
    expect(get).toHaveBeenCalledWith('/budgets', { params: { month: '2026-04' } })
  })
})
