import { ref } from 'vue'
import { describe, expect, it, vi } from 'vitest'
import { componentScript, deferred, flushWork } from '@/test/componentScript'

function setupHome(fail: 'ai' | 'account' | null = null, transactionLoader?: (params: any) => Promise<any>, accountLoader?: () => Promise<any>) {
  const toast = { error: vi.fn(), success: vi.fn(), warning: vi.fn() }
  const data = { list: [], net_assets: 1234, total_assets: 1234, total_liabilities: 0 }
  const view = componentScript('views/HomeView.vue', ['refresh', 'loadData', 'accountData', 'overview', 'formatMoney', 'handleDateSelect', 'dateTransactions', 'selectedDate', 'viewMode', 'loadDateTransactions', 'dateTransactionsFailed'], {
    '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0) },
    '@/composables/useToast': { toast },
    '@/api/account': { accountApi: { getList: accountLoader || (async () => { if (fail === 'account') throw Error('account unavailable'); return data }) } },
    '@/api/statistics': { statisticsApi: { getOverview: async () => ({ expense: 20 }) } },
    '@/api/transaction': { transactionApi: { getList: transactionLoader || (async (params: any) => { if (params.start_date === '2025-02-02') throw Error('date unavailable'); return { list: params.start_date ? [{ id: params.start_date, transaction_date: params.start_date }] : [] } }) } },
    '@/api/reminder': { reminderApi: { getDebtSummary: async () => ({}) } },
    '@/api/budget': { budgetApi: { getSummary: async () => ({}) } },
    '@/api/lending': { lendingApi: { getSummary: async () => ({}) } },
    '@/api/family': { familyApi: { getSummary: async () => ({}) } },
    '@/api/ai': { aiApi: { listReports: async () => { if (fail === 'ai') throw Error('AI unavailable'); return [] } } },
  })
  return { ...view, toast, data }
}

describe('page data source and refresh result', () => {
  it('retains successful core balances when optional AI fails and reports partial refresh', async () => {
    const view = setupHome('ai')
    await view.entry.refresh()
    expect(view.entry.accountData.value).toEqual(view.data)
    expect(view.toast.success).not.toHaveBeenCalledWith('刷新成功')
    expect(view.toast.warning).toHaveBeenCalled()
    view.unmount()
  })

  it('never formats unknown assets as a real zero or reports failed core refresh as success', async () => {
    const view = setupHome('account')
    await view.entry.refresh()
    expect(view.entry.formatMoney(view.entry.accountData.value?.net_assets)).not.toBe('0.00')
    expect(view.toast.success).not.toHaveBeenCalled()
    view.unmount()
  })

  it('hides old-month amounts when a different month fails to load', async () => {
    let fail = false
    const view = componentScript('views/StatisticsView.vue', ['loadData', 'selectedMonth', 'overview', 'categoryStats', 'trendData'], {
      '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0) },
      '@/composables/useToast': { toast: { error: vi.fn() } },
      '@/api/statistics': { statisticsApi: { getOverview: async () => ({ expense: 120 }), getCategoryStats: async () => ({ items: [{ amount: 120 }] }), getTrend: async () => { if (fail) throw Error('trend unavailable'); return { items: [{ expense: 120 }] } } } },
    })
    await view.entry.loadData()
    fail = true
    view.entry.selectedMonth.value = '2025-01'
    await view.entry.loadData()
    expect(view.entry.overview.value).toBeNull()
    expect(view.entry.categoryStats.value).toEqual([])
    expect(view.entry.trendData.value).toEqual([])
    view.unmount()
  })
})


describe('home calendar query identity', () => {
  it('does not show the prior date transactions after selecting a failed date', async () => {
    const view = setupHome()
    view.entry.handleDateSelect('2025-02-01')
    await flushWork()
    expect(view.entry.dateTransactions.value).toHaveLength(1)
    view.entry.handleDateSelect('2025-02-02')
    await flushWork()
    expect(view.entry.dateTransactions.value).toEqual([])
    view.unmount()
  })
})


describe('calendar refresh completion identity', () => {
  const dayA = '2025-03-01'
  const dayB = '2025-03-02'
  const transactions = (date: string) => ({ list: [{ id: date, transaction_date: date }] })

  it.each(['success', 'failure'] as const)('does not toast an obsolete A refresh after B succeeds when A ends with %s', async outcome => {
    const a = deferred()
    const view = setupHome(null, async params => !params.start_date
      ? { list: [] }
      : params.start_date === dayA ? a.promise : transactions(dayB))
    view.entry.viewMode.value = 'calendar'
    view.entry.selectedDate.value = dayA
    const refreshingA = view.entry.refresh()
    await flushWork()
    view.entry.handleDateSelect(dayB)
    await flushWork()
    expect(view.entry.dateTransactions.value[0].id).toBe(dayB)
    if (outcome === 'success') a.resolve(transactions(dayA))
    else a.reject(Error('obsolete A failure'))
    await refreshingA
    expect(view.toast.error).not.toHaveBeenCalled()
    expect(view.toast.success).not.toHaveBeenCalled()
    expect(view.entry.dateTransactionsFailed.value).toBe(false)
    expect(view.entry.dateTransactions.value[0].id).toBe(dayB)
    view.unmount()
  })

  it('reports a superseded date request as stale rather than failed', async () => {
    const a = deferred()
    const view = setupHome(null, async params => params.start_date === dayA ? a.promise : transactions(dayB))
    view.entry.selectedDate.value = dayA
    const loadingA = view.entry.loadDateTransactions(dayA)
    view.entry.selectedDate.value = dayB
    expect(await view.entry.loadDateTransactions(dayB)).toBe('success')
    a.resolve(transactions(dayA))
    expect(await loadingA).toBe('stale')
    view.unmount()
  })

  it('does not retarget an A refresh to B if the date changes while core reads wait', async () => {
    const account = deferred()
    const transactionsApi = vi.fn(async params => params.start_date ? transactions(params.start_date) : { list: [] })
    const view = setupHome(null, transactionsApi, () => account.promise)
    view.entry.viewMode.value = 'calendar'
    view.entry.selectedDate.value = dayA
    const refreshing = view.entry.refresh()
    view.entry.handleDateSelect(dayB)
    await flushWork()
    account.resolve(view.data)
    await refreshing
    expect(transactionsApi.mock.calls.filter(([params]) => params.start_date === dayB)).toHaveLength(1)
    expect(view.toast.success).not.toHaveBeenCalled()
    view.unmount()
  })

  it('still reports the current date failure when optional core-side data also fails', async () => {
    const view = setupHome('ai')
    view.entry.viewMode.value = 'calendar'
    view.entry.selectedDate.value = '2025-02-02'
    await view.entry.refresh()
    expect(view.toast.error).toHaveBeenCalledWith('所选日期交易刷新失败，请重试')
    expect(view.toast.success).not.toHaveBeenCalled()
    view.unmount()
  })
})
