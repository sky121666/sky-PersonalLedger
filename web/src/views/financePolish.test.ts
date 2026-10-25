import { ref } from 'vue'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { componentScript, flushWork } from '@/test/componentScript'

const views: ReturnType<typeof componentScript>[] = []
function transactions() {
  const getList = vi.fn(async (_params?: unknown) => ({ list: [], total: 0 }))
  const view = componentScript('views/TransactionsView.vue', ['filters', 'filterDraft', 'filterError', 'openFilter', 'applyFilter', 'showFilter'], {
    '@/api/transaction': { transactionApi: { getList } },
    '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0) },
    '@/composables/useToast': { toast: { error: vi.fn(), success: vi.fn() } },
  })
  views.push(view)
  return { ...view.entry, getList }
}
afterEach(() => views.splice(0).forEach(view => view.unmount()))

describe('transaction filter drafts', () => {
  it('does not apply a changed type or dates before confirmation', async () => {
    const e = transactions()
    e.openFilter()
    e.filterDraft.value.type = 'transfer'
    e.filterDraft.value.start_date = '2026-10-01'
    e.showFilter.value = false
    await flushWork()
    expect(e.filters.value.type).toBe('')
    expect(e.getList).not.toHaveBeenCalled()
    e.openFilter()
    expect(e.filterDraft.value.start_date).toBe('')
  })
  it('rejects reversed dates without changing the active query', async () => {
    const e = transactions()
    e.openFilter()
    e.filterDraft.value = { type: 'expense', start_date: '2026-10-22', end_date: '2026-10-01' }
    e.applyFilter()
    await flushWork()
    expect(e.filterError.value).toContain('开始日期')
    expect(e.filters.value.start_date).toBe('')
    expect(e.showFilter.value).toBe(true)
    expect(e.getList).not.toHaveBeenCalled()
  })
  it('applies the confirmed filter once and preserves keyword search', async () => {
    const e = transactions()
    e.filters.value.keyword = '药品'
    e.openFilter()
    e.filterDraft.value = { type: 'transfer', start_date: '2026-10-01', end_date: '2026-10-21' }
    e.applyFilter()
    await flushWork()
    expect(e.filters.value.type).toBe('transfer')
    expect(e.showFilter.value).toBe(false)
    expect(e.getList).toHaveBeenCalledTimes(1)
    expect(e.getList.mock.calls[0]?.[0]).toEqual(expect.objectContaining({ keyword: '药品' }))
  })
})

describe('family attribution presentation', () => {
  it('keeps disabled member history and the real unassigned amount', () => {
    const view = componentScript('views/FamilyView.vue', ['members', 'summary', 'statistics', 'attribution', 'displayMembers'], {
      '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0) },
      '@/api/family': { familyApi: {} },
      '@/api/budget': { budgetApi: {} },
      '@/composables/useToast': { toast: {} },
    })
    views.push(view)
    const e = view.entry
    e.members.value = [{ id: 'history', name: '历史成员', is_enabled: false }]
    e.summary.value = { total_expense: 100, members: [{ member_id: 'history', expense_total: 60 }] }
    e.statistics.value = { total_expense: 100, members: [{ member_id: 'history', expense_total: 60, categories: [] }] }
    expect(e.attribution.value).toEqual({ assigned: 60, unassigned: 40 })
    expect(e.displayMembers.value.map((member: { member_id: string }) => member.member_id)).toContain('history')
  })
})

it('spaces sparse recorded days on the real calendar without changing their amounts', () => {
  const view = componentScript('views/StatisticsView.vue', ['selectedMonth', 'dataQueryKey', 'trendData', 'dailyTrend'], {
    '@/api/statistics': { statisticsApi: {
      getOverview: vi.fn(async () => ({ income: 0, expense: 0, balance: 0 })),
      getCategoryStats: vi.fn(async () => ({ items: [] })),
      getTrend: vi.fn(async () => ({ items: [] })),
    } },
    '@/composables/useToast': { toast: { error: vi.fn() } },
    '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0) },
  })
  views.push(view)
  const e = view.entry
  e.selectedMonth.value = '2025-02'
  e.dataQueryKey.value = '2025-02:expense'
  e.trendData.value = [{ date: '2025-02-10', income: 100, expense: 0, balance: 100 }]
  expect(e.dailyTrend.value).toHaveLength(28)
  expect(e.dailyTrend.value[0]).toEqual({ date: '2025-02-01', income: 0, expense: 0, balance: 0 })
  expect(e.dailyTrend.value[9].income).toBe(100)
  expect(e.dailyTrend.value.reduce((sum: number, row: { income: number }) => sum + row.income, 0)).toBe(100)
  e.dataQueryKey.value = ''
  expect(e.dailyTrend.value).toEqual([])
})
