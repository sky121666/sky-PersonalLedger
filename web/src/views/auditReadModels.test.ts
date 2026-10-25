import { createPinia, setActivePinia } from 'pinia'
import { useWorkspacePreferencesStore } from '@/stores/workspacePreferences'
import { ref } from 'vue'
import { afterEach, describe, expect, it, vi } from 'vitest'
vi.mock('@/api/auth', () => ({ authApi: { getProfile: async () => ({ id: 1 }) } }))
import { componentScript, deferred, flushWork } from '@/test/componentScript'

const views: ReturnType<typeof componentScript>[] = []
afterEach(() => views.splice(0).forEach(v => v.unmount()))
const toast = { error: vi.fn(), success: vi.fn(), warning: vi.fn() }
const mutations = (revision = ref(0)) => ({ useLedgerMutationRevision: () => revision })
function view(file: string, exposed: string[], mocks: Record<string, unknown>, props = {}) {
  const v = componentScript(file, exposed, { '@/stores/workspacePreferences': { useWorkspacePreferencesStore: () => { setActivePinia(createPinia()); return useWorkspacePreferencesStore() } }, '@/composables/useToast': { toast }, '@/composables/useLedgerMutation': mutations(), ...mocks }, props)
  views.push(v)
  return v.entry
}

describe('audited report and category query isolation', () => {
  it('clears a successful year when the selected different year fails', async () => {
    const e = view('views/ReportView.vue', ['selectedYear', 'report', 'loadReport'], {
      '@/api/export': { exportApi: { getYearlyReport: async (year: number) => { if (year === 2025) throw Error('offline'); return { year, total_expense: 123 } } } },
      '@/api/statistics': { statisticsApi: { getAssetTrend: async () => ({ items: [], current_net_worth: 20 }) } },
    })
    e.selectedYear.value = 2026
    await e.loadReport()
    e.selectedYear.value = 2025
    await e.loadReport()
    expect(e.report.value).toBeNull()
  })

  it('refreshes available years when a newly backdated transaction is recorded', async () => {
    const revision = ref(0)
    const e = view('views/ReportView.vue', ['availableYears', 'loadYears'], {
      '@/composables/useLedgerMutation': mutations(revision),
      '@/api/export': { exportApi: { getAvailableYears: async () => revision.value ? [2026, 2020] : [2026], getYearlyReport: async () => ({ year: 2026 }) } },
      '@/api/statistics': { statisticsApi: { getAssetTrend: async () => ({ items: [], current_net_worth: 0 }) } },
    })
    await e.loadYears()
    revision.value++
    await flushWork()
    expect(e.availableYears.value).toEqual([2026, 2020])
  })

  it('ignores the late expense response after the income tab loaded', async () => {
    const expense = deferred()
    const e = view('views/CategoryView.vue', ['activeTab', 'categories', 'loadCategories'], {
      '@/api/category': { categoryApi: { getList: (type: string) => type === 'expense' ? expense.promise : Promise.resolve([{ id: 'income', type }]) } },
    })
    const old = e.loadCategories()
    e.activeTab.value = 'income'
    await flushWork()
    expense.resolve([{ id: 'expense', type: 'expense' }])
    await old
    expect(e.categories.value.map((c: any) => c.id)).toEqual(['income'])
  })
})

describe('calendar query and mutation freshness', () => {
  it('does not overwrite the new month with an old month response', async () => {
    const january = deferred()
    const e = view('components/CalendarView.vue', ['nextMonth', 'trendData'], {
      '@/api/statistics': { statisticsApi: { getTrend: (month: string) => month === '2025-01' ? january.promise : Promise.resolve({ items: [{ date: '2025-02-01', expense: 20 }] }) } },
    }, { initialDate: '2025-01' })
    e.nextMonth()
    await flushWork()
    january.resolve({ items: [{ date: '2025-01-01', expense: 10 }] })
    await flushWork()
    expect(e.trendData.value[0].date).toBe('2025-02-01')
  })

  it('refreshes calendar amounts after a ledger mutation without switching month', async () => {
    const revision = ref(0)
    const e = view('components/CalendarView.vue', ['trendData'], {
      '@/composables/useLedgerMutation': mutations(revision),
      '@/api/statistics': { statisticsApi: { getTrend: async () => ({ items: [{ date: '2025-01-01', expense: revision.value ? 25 : 10 }] }) } },
    }, { initialDate: '2025-01' })
    await flushWork()
    revision.value++
    await flushWork()
    expect(e.trendData.value[0].expense).toBe(25)
  })

  it('appends the 101st daily transaction when requesting page two', async () => {
    const e = view('views/HomeView.vue', ['loadDateTransactions', 'dateTransactions', 'selectedDate'], {
      '@/stores/auth': { useAuthStore: () => ({ sessionGeneration: 0 }) },
      '@/api/account': {}, '@/api/statistics': {}, '@/api/reminder': {}, '@/api/budget': {}, '@/api/lending': {}, '@/api/family': {}, '@/api/ai': {},
      '@/api/transaction': { transactionApi: { getList: async ({ page = 1 }: any) => ({ total: 101, list: Array.from({ length: page === 1 ? 100 : 1 }, (_, i) => ({ id: `${page}-${i}`, transaction_date: '2025-01-01' })) }) } },
    })
    e.selectedDate.value = '2025-01-01'
    await e.loadDateTransactions('2025-01-01')
    await e.loadDateTransactions('2025-01-01', 2)
    expect(e.dateTransactions.value).toHaveLength(101)
    expect(e.dateTransactions.value[100].id).toBe('2-0')
  })
})

it('reports failed account-log reads separately from an empty successful result', async () => {
  const e = view('views/AccountLogView.vue', ['loadLogs'], {
    'vue-router': { useRoute: () => ({ params: {} }), useRouter: () => ({}) },
    '@/api/account': {},
    '@/api/accountLog': { accountLogApi: { getAll: async () => { throw Error('offline') } } },
  })
  expect(await e.loadLogs()).toBe('failed')
})
