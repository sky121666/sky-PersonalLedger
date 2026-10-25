import { describe, expect, it, vi } from 'vitest'

const api = vi.hoisted(() => ({
  accountApi: { getList: vi.fn() },
  statisticsApi: { getOverview: vi.fn() },
  transactionApi: { getList: vi.fn() },
  reminderApi: { getDebtSummary: vi.fn() },
  budgetApi: { getSummary: vi.fn(), getList: vi.fn() },
  lendingApi: { getSummary: vi.fn() },
  familyApi: { getSummary: vi.fn() },
  aiApi: { listReports: vi.fn() },
}))

vi.mock('@/api/account', () => ({ accountApi: api.accountApi }))
vi.mock('@/api/statistics', () => ({ statisticsApi: api.statisticsApi }))
vi.mock('@/api/transaction', () => ({ transactionApi: api.transactionApi }))
vi.mock('@/api/reminder', () => ({ reminderApi: api.reminderApi }))
vi.mock('@/api/budget', () => ({ budgetApi: api.budgetApi }))
vi.mock('@/api/lending', () => ({ lendingApi: api.lendingApi }))
vi.mock('@/api/family', () => ({ familyApi: api.familyApi }))
vi.mock('@/api/ai', () => ({ aiApi: api.aiApi }))

import { useHomeOverview } from './useHomeOverview'

function success() {
  api.accountApi.getList.mockResolvedValue({ list: [], total_assets: 1, total_liabilities: 0, net_assets: 1 })
  api.statisticsApi.getOverview.mockResolvedValue({ income: 1, expense: 0, balance: 1, income_change: 0, expense_change: 0, daily_average: 0, transaction_count: 0 })
  api.transactionApi.getList.mockResolvedValue({ list: [], total: 0, page: 1, page_size: 20 })
  api.reminderApi.getDebtSummary.mockResolvedValue({ total_debt: 0, total_paid: 0, total_principal: 0, progress: 0, active_loans: 0, paid_off_loans: 0, next_payment_day: 0, next_payment_name: '', days_until_next: 0 })
  api.budgetApi.getSummary.mockResolvedValue({ total_amount: 0, total_spent: 0, percentage: 0, daily_available: 0, days_remaining: 0, over_budget_categories: [] })
  api.lendingApi.getSummary.mockResolvedValue({ total_lend_out: 0, total_borrow_in: 0, active_lend_out: 0, active_borrow_in: 0, settled_lend_out: 0, settled_borrow_in: 0, total_receivable: 0, total_payable: 0, net_lending: 0 })
  api.familyApi.getSummary.mockResolvedValue({ month: '2026-10', total_expense: 0, members: [] })
  api.aiApi.listReports.mockResolvedValue([])
  api.budgetApi.getList.mockResolvedValue({ total_budget: null, category_budgets: [], member_budgets: [] })
}

describe('useHomeOverview', () => {
  it('loads the existing home sources once and exposes separate resource states', async () => {
    vi.clearAllMocks(); success()
    const overview = useHomeOverview({ receivedAt: () => 123 })
    expect(await overview.load()).toBe('success')
    expect(api.accountApi.getList).toHaveBeenCalledTimes(1)
    expect(api.statisticsApi.getOverview).toHaveBeenCalledTimes(1)
    expect(api.transactionApi.getList).toHaveBeenCalledWith({ page_size: 20 })
    expect(overview.accounts.value).toMatchObject({ phase: 'ready', receivedAt: 123, queryKey: 'accounts' })
    expect(overview.overview.value).toMatchObject({ phase: 'ready', receivedAt: 123, queryKey: 'overview:current' })
    expect(overview.failures.value).toEqual([])
  })

  it('keeps successful values and marks only failed sources', async () => {
    vi.clearAllMocks(); success()
    api.aiApi.listReports.mockRejectedValue(new Error('ai down'))
    const overview = useHomeOverview({ receivedAt: () => 123 })
    expect(await overview.load()).toBe('partial')
    expect(overview.accounts.value.phase).toBe('ready')
    expect(overview.overview.value.phase).toBe('ready')
    expect(overview.ai.value.phase).toBe('error')
    expect(overview.failures.value).toContain('AI 分析')
  })
})

describe('home optional source ownership', () => {
  it('keeps an in-flight family refresh when another optional widget is enabled', async () => {
    vi.clearAllMocks(); success()
    const optional = { lending: false, family: true, ai: false, budgetDetails: false, accountIds: [] as string[] }
    const model = useHomeOverview({ optional: () => optional })
    await model.load()
    let resolve!: (value: any) => void
    api.familyApi.getSummary.mockReturnValueOnce(new Promise(yes => { resolve = yes }))
    const refreshing = model.load()
    await vi.waitFor(() => expect(api.familyApi.getSummary).toHaveBeenCalledTimes(2))
    optional.ai = true
    const adding = model.loadOptional()
    resolve({ month: '2026-10', total_expense: 45, members: [] })
    await adding
    expect(await refreshing).toBe('success')
    expect(model.family.value.data?.total_expense).toBe(45)
    expect(api.familyApi.getSummary).toHaveBeenCalledTimes(2)
  })

  it('loads only enabled optional sources and deduplicates account queries', async () => {
    vi.clearAllMocks(); success()
    let optional = { lending: false, family: false, ai: false, budgetDetails: false, accountIds: [] as string[] }
    const model = useHomeOverview({ optional: () => optional })
    await model.load()
    expect(api.lendingApi.getSummary).not.toHaveBeenCalled()
    expect(api.familyApi.getSummary).not.toHaveBeenCalled()
    expect(api.aiApi.listReports).not.toHaveBeenCalled()
    expect(api.budgetApi.getList).not.toHaveBeenCalled()
    optional = { ...optional, budgetDetails: true, accountIds: ['card', 'card', 'cash'] }
    await model.loadOptional()
    expect(api.budgetApi.getList).toHaveBeenCalledTimes(1)
    expect(api.transactionApi.getList.mock.calls.filter(([params]) => params.account_id)).toEqual([
      [{ account_id: 'card', page_size: 3 }], [{ account_id: 'cash', page_size: 3 }],
    ])
    await model.loadOptional()
    expect(api.budgetApi.getList).toHaveBeenCalledTimes(1)
    expect(api.accountApi.getList).toHaveBeenCalledTimes(1)
  })

  it('rejects late core and optional responses after the session changes', async () => {
    vi.clearAllMocks(); success()
    let generation = 1
    let resolve!: (value: any) => void
    const late = new Promise<any>(yes => { resolve = yes })
    api.accountApi.getList.mockReturnValue(late)
    api.aiApi.listReports.mockReturnValue(late)
    const model = useHomeOverview({ sessionGeneration: () => generation })
    const loading = model.load()
    generation++
    resolve({ list: [], net_assets: 999 })
    expect(await loading).toBe('stale')
    expect(model.accounts.value.data).toBeNull()
    expect(model.ai.value.data).toBeNull()
  })
})
