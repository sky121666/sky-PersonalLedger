import { describe, expect, it } from 'vitest'
import { debtCents, debtAmount, buildDebtParts, buildDebtPayment, buildDebtAllocation } from './debtAmounts'

const rows = [
  { plan_id: 'A', principal: '60', booked_interest: '', cash_interest: '10' },
  { plan_id: 'B', principal: '40', booked_interest: '', cash_interest: '' },
]

describe('debt monetary input', () => {
  it('uses exact integer cents for decimal input and allocation sums', () => {
    expect(debtCents('0.29')).toBe(29)
    expect(debtCents('0.1') + debtCents('0.2')).toBe(30)
    expect(debtAmount(29)).toBe(0.29)
    expect(buildDebtParts(rows).totalCents).toBe(11000)
  })

  it.each(['-1', '1.001', '1e3', 'Infinity', 'NaN', '90071992547409.92'])('rejects invalid or inexact amount %s', value => {
    expect(() => debtCents(value)).toThrow()
  })

  it('retains explicit residual payment credit without inventing allocation priority', () => {
    const result = buildDebtPayment({
      amount: '120', source_kind: 'account', source_account_id: 'cash',
      unplanned_amount: '', unapplied_amount: '10', occurred_at: '2026-10-18T10:00',
    }, rows, { account_id: 'card' }, false)
    expect(result).toMatchObject({ amount: 120, unapplied_amount: 10, source_account_id: 'cash' })
    expect(result.allocations).toEqual([
      { plan_id: 'A', principal: 60, booked_interest: 0, cash_interest: 10 },
      { plan_id: 'B', principal: 40, booked_interest: 0, cash_interest: 0 },
    ])
    expect(() => buildDebtPayment({
      amount: '120', source_kind: 'account', source_account_id: 'cash',
      unplanned_amount: '', unapplied_amount: '', occurred_at: '',
    }, rows, { account_id: 'card' }, false)).toThrow(/合计/)
  })

  it('does not allow external cash interest or the debt account as its own payer', () => {
    const form = { amount: '110', source_kind: 'external' as const, source_account_id: '', unplanned_amount: '', unapplied_amount: '', occurred_at: '' }
    expect(() => buildDebtPayment(form, rows, { account_id: 'card' }, false)).toThrow(/外部/)
    expect(() => buildDebtPayment({ ...form, source_kind: 'account', source_account_id: 'card' }, rows, { account_id: 'card' }, false)).toThrow(/同一/)
  })

  it('requires explicit, bounded deferred allocations and rejects cash interest there', () => {
    expect(buildDebtAllocation([{ plan_id: 'A', principal: '0.10', booked_interest: '0.20', cash_interest: '' }], '', 30))
      .toMatchObject({ allocations: [{ plan_id: 'A', principal: 0.1, booked_interest: 0.2, cash_interest: 0 }] })
    expect(() => buildDebtAllocation(rows, '', 20000)).toThrow(/利息/)
    expect(() => buildDebtAllocation([{ ...rows[1]!, principal: '41' }], '', 4000)).toThrow(/额度/)
  })
})
