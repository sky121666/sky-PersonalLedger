import { describe, expect, it } from 'vitest'
import type { AccountListResponse } from '@/api/account'
import type { AIReport } from '@/api/ai'
import type { BudgetSummary } from '@/api/budget'
import type { DebtSummary } from '@/api/reminder'
import type { OverviewResponse } from '@/api/statistics'
import type { Transaction } from '@/api/transaction'
import { createHomeReadModels, getReminderReadModel, getTransactionPresentation } from './readModels'

const accounts: AccountListResponse = {
  list: [
    { id: 'cash', name: '现金', type: 'cash', icon: 'wallet', color: '#007AFF', initial_balance: 0, current_balance: 300, total_paid: 0, is_archived: false, sort_order: 0 },
    { id: 'card', name: '信用卡', type: 'credit', icon: 'credit-card', color: '#FF3B30', initial_balance: 0, current_balance: -200, total_paid: 0, is_archived: false, sort_order: 1 },
  ],
  total_assets: 300, total_liabilities: 200, net_assets: 100,
}
const overview: OverviewResponse = { income: 500, expense: 300, balance: 200, income_change: 0, expense_change: 0, daily_average: 10, transaction_count: 3 }
const budget: BudgetSummary = { total_amount: 100, total_spent: 130, percentage: 130, daily_available: -2, days_remaining: 10, over_budget_categories: [{ name: '餐饮', percentage: 130 }] }
const debt: DebtSummary = { total_debt: 75, total_paid: 25, total_principal: 100, progress: 25, active_loans: 1, paid_off_loans: 0, next_payment_day: 22, next_payment_name: '房贷', days_until_next: 4 }
const transaction: Transaction = { id: 't1', type: 'transfer', amount: 100, account_id: 'cash', to_account_id: 'card', category_id: null, transaction_date: '2026-10-20T08:00:00Z', remark: '转出', images: '', tags: '', source: 'manual', recurring_id: null }

describe('home read models', () => {
  it('keeps server asset totals and does not recompute them from account rows', () => {
    const model = createHomeReadModels({ accounts, overview, budget, debt, recentTransactions: [], showAmounts: true })
    expect(model.netAssets.data).toMatchObject({ netAssets: 100, totalAssets: 300, totalLiabilities: 200 })
  })

  it('keeps transfer transactions neutral and preserves budget overrun values', () => {
    expect(getTransactionPresentation(transaction).tone).toBe('neutral')
    const model = createHomeReadModels({ accounts, overview, budget, debt, recentTransactions: [transaction], showAmounts: true })
    expect(model.budget.data).toMatchObject({ remaining: -30, percentage: 130, visualPercentage: 100 })
    expect(model.transactions.data?.[0].presentation.tone).toBe('neutral')
  })

  it('does not invent a reminder amount or interpret an empty reminder as today', () => {
    expect(getReminderReadModel(null)).toBeNull()
    expect(getReminderReadModel({ ...debt, next_payment_name: '' })).toBeNull()
    const model = getReminderReadModel(debt)
    expect(model).toMatchObject({ nextName: '房贷', daysUntil: 4, scheduledDay: 22 })
    expect(model).not.toHaveProperty('nextAmount')
  })

  it('returns error states for failed resources while preserving successful siblings', () => {
    const model = createHomeReadModels({ accounts, overview: null, budget: null, debt, recentTransactions: [], showAmounts: true, failures: ['本月收支', '预算'] })
    expect(model.overview.phase).toBe('error')
    expect(model.budget.phase).toBe('error')
    expect(model.netAssets.phase).toBe('ready')
    expect(model.reminders.phase).toBe('ready')
  })

  it.each([undefined, debt])('a reminder outage is an error even with previous data %s', previous => {
    const model = createHomeReadModels({ debt: previous, failures: ['债务提醒'] })
    expect(model.reminders.phase).toBe('error')
    expect(model.reminders.error).toBe('还款提醒加载失败')
  })

  it('uses category overrun rather than the total budget balance to label category warnings', () => {
    const data = { ...budget, total_amount: 10000, total_spent: 8100, percentage: 81,
      over_budget_categories: [{ name: '居住', percentage: 0 }, { name: '购物', percentage: 32 }] }
    expect(createHomeReadModels({ budget: data }).budget.data).toMatchObject({
      remaining: 1900, alertName: '购物', alertOver: true,
    })
    expect(createHomeReadModels({ budget: { ...data, over_budget_categories: [{ name: '居住', percentage: 0 }] } }).budget.data)
      .toMatchObject({ alertName: '居住', alertOver: false })
  })

  it('keeps not-yet-loaded accounts and reminders unknown until their successful response', () => {
    const initial = createHomeReadModels({})
    expect(initial.accounts.phase).toBe('idle')
    expect(initial.reminders.phase).toBe('idle')
    expect(createHomeReadModels({ accounts: { ...accounts, list: [] } }).accounts.phase).toBe('ready')
    expect(createHomeReadModels({ debt: { ...debt, next_payment_name: '' } }).reminders.phase).toBe('ready')
  })

  it.each([
    ['failed', '', '报告生成失败'],
    ['running', '', '报告正在生成'],
    ['completed', '{"summary":"合成摘要","title":"合成标题"}', '合成摘要'],
    ['completed', '旧格式报告正文', '旧格式报告正文'],
  ])('presents a truthful AI summary for %s', (status, content_json, summary) => {
    const aiReport = { status, content_json, period_start: '2026-10-01', period_end: '2026-10-31', provider_name: '合成提供商' } as AIReport
    expect(createHomeReadModels({ aiReport }).ai.data?.summary).toBe(summary)
  })

  it('masks every amount-bearing model when privacy is enabled', () => {
    const model = createHomeReadModels({ accounts, overview, budget, debt, recentTransactions: [transaction], showAmounts: false })
    expect(model.netAssets.data?.displayNetAssets).toBe('****')
    expect(model.overview.data?.displayIncome).toBe('****')
    expect(model.budget.data?.displaySpent).toBe('****')
    expect(model.reminders.data?.displayPaid).toBe('****')
    expect(model.transactions.data?.[0].displayAmount).toBe('****')
  })
})
