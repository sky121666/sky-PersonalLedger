import { computed, ref } from 'vue'
import dayjs from 'dayjs'
import { accountApi, type AccountListResponse } from '@/api/account'
import { statisticsApi, type OverviewResponse } from '@/api/statistics'
import { transactionApi, type Transaction } from '@/api/transaction'
import { budgetApi, type BudgetSummary, type BudgetListResponse } from '@/api/budget'
import { reminderApi, type DebtSummary } from '@/api/reminder'
import { lendingApi, type LendingSummary } from '@/api/lending'
import { familyApi, type FamilySummary } from '@/api/family'
import { aiApi, type AIReport } from '@/api/ai'
import { createRequestGeneration } from '@/utils/requestGeneration'
import type { ResourceState } from '@/components/home/readModels'

export interface HomeOverviewOptions {
  currentMonth?: string
  receivedAt?: () => number
  sessionGeneration?: () => number
  optional?: () => { lending: boolean; family: boolean; ai: boolean; budgetDetails: boolean; accountIds: string[] }
}

function state<T>(data: T | null, queryKey: string, receivedAt: number | null): ResourceState<T> {
  return {
    phase: data === null ? 'idle' : 'ready',
    data,
    queryKey,
    receivedAt,
  }
}

export function useHomeOverview(options: HomeOverviewOptions = {}) {
  const requests = createRequestGeneration()
  const receivedAt = options.receivedAt ?? Date.now
  const accounts = ref<ResourceState<AccountListResponse>>(state<AccountListResponse>(null, 'accounts', null))
  const overview = ref<ResourceState<OverviewResponse>>(state<OverviewResponse>(null, 'overview:current', null))
  const budget = ref<ResourceState<BudgetSummary>>(state<BudgetSummary>(null, 'budget:current', null))
  const debt = ref<ResourceState<DebtSummary>>(state<DebtSummary>(null, 'reminders:current', null))
  const recentTransactions = ref<ResourceState<Transaction[]>>(state<Transaction[]>(null, 'transactions:recent', null))
  const lending = ref<ResourceState<LendingSummary>>(state<LendingSummary>(null, 'lending:current', null))
  const family = ref<ResourceState<FamilySummary>>(state<FamilySummary>(null, 'family:current', null))
  const ai = ref<ResourceState<AIReport[]>>(state<AIReport[]>(null, 'ai:reports', null))
  const coreFailures = ref<string[]>([])
  const optionalFailures = ref<string[]>([])
  const failures = computed(() => [...coreFailures.value, ...optionalFailures.value])
  const budgetDetails = ref<ResourceState<BudgetListResponse>>(state<BudgetListResponse>(null, 'budgets:categories', null))
  const accountTransactions = ref<Record<string, ResourceState<Transaction[]>>>({})
  const optionalTasks = new Map<string, { promise: Promise<'success' | 'failed' | 'stale'> }>()
  const optionalSources = () => options.optional?.() ?? { lending: true, family: true, ai: true, budgetDetails: false, accountIds: [] }
  const session = () => options.sessionGeneration?.() ?? 0

  const loading = ref(false)
  const lastLoadedAt = ref<number | null>(null)

  const values = computed(() => ({
    accounts: accounts.value.data,
    overview: overview.value.data,
    budget: budget.value.data,
    debt: debt.value.data,
    recentTransactions: recentTransactions.value.data ?? [],
    lending: lending.value.data,
    family: family.value.data,
    aiReport: ai.value.data?.[0] ?? null,
  }))

  async function load(): Promise<'success' | 'partial' | 'failed' | 'stale'> {
    const generation = requests.begin()
    loading.value = true
    const at = receivedAt()
    const ownerGeneration = session()
    try {
      const results = await Promise.allSettled([
        accountApi.getList(),
        statisticsApi.getOverview(),
        transactionApi.getList({ page_size: 20 }),
        reminderApi.getDebtSummary(),
        budgetApi.getSummary(),
        loadOptional(true),
      ])
      if (!requests.isLatest(generation) || session() !== ownerGeneration) return 'stale'
      const nextFailures: string[] = []
      const [acc, ov, tx, debtResult, bud, optionalResult] = results
      if (acc.status === 'fulfilled') accounts.value = state(acc.value, 'accounts', at)
      else nextFailures.push('账户资产')
      if (ov.status === 'fulfilled') overview.value = state(ov.value, 'overview:current', at)
      else nextFailures.push('本月收支')
      if (tx.status === 'fulfilled') recentTransactions.value = state([...tx.value.list].sort((a, b) => new Date(b.transaction_date).getTime() - new Date(a.transaction_date).getTime()), 'transactions:recent', at)
      else nextFailures.push('近期交易')
      if (debtResult.status === 'fulfilled') debt.value = state(debtResult.value, 'reminders:current', at)
      else nextFailures.push('债务提醒')
      if (bud.status === 'fulfilled') budget.value = state(bud.value, 'budget:current', at)
      else nextFailures.push('预算')
      coreFailures.value = nextFailures
      lastLoadedAt.value = at
      if (optionalResult.status === 'rejected' || optionalResult.value === 'stale') return 'stale'
      if ([acc, ov, tx].some(item => item.status === 'rejected')) return 'failed'
      return failures.value.length ? 'partial' : 'success'
    } finally {
      if (requests.isLatest(generation)) loading.value = false
    }
  }

  async function loadOptional(force = false): Promise<'success' | 'partial' | 'stale'> {
    const sources = optionalSources()
    const month = options.currentMonth ?? dayjs().format('YYYY-MM')
    const ownerGeneration = session()
    const jobs: Array<Promise<'success' | 'failed' | 'stale'>> = []
    const activeKeys = new Set<string>()
    function schedule(key: string, run: () => Promise<unknown>, assign: (value: any) => void, fail: () => void) {
      activeKeys.add(key)
      const pending = optionalTasks.get(key)
      if (pending) { jobs.push(pending.promise); return }
      const task = {} as { promise: Promise<'success' | 'failed' | 'stale'> }
      const current = () => optionalTasks.get(key) === task && session() === ownerGeneration
      task.promise = Promise.resolve().then(run).then(value => {
        if (!current()) return 'stale' as const
        assign(value); return 'success' as const
      }, () => {
        if (!current()) return 'stale' as const
        fail(); return 'failed' as const
      }).finally(() => { if (optionalTasks.get(key) === task) optionalTasks.delete(key) })
      optionalTasks.set(key, task)
      jobs.push(task.promise)
    }
    function add<T>(enabled: boolean, name: string, resource: { value: ResourceState<T> }, run: () => Promise<T>, key: string) {
      if (!enabled) { resource.value = state<T>(null, key, null); return }
      activeKeys.add(key)
      if (!force && resource.value.phase === 'ready' && resource.value.queryKey === key && !optionalTasks.has(key)) return
      schedule(key, run, value => { resource.value = state(value, key, receivedAt()) }, () => {
        resource.value = { phase: 'error', data: null, queryKey: key, receivedAt: null, error: `${name}加载失败` }
      })
    }
    add(sources.lending, '借贷', lending, () => lendingApi.getSummary(), 'lending:current')
    add(sources.family, '家庭成员', family, () => familyApi.getSummary(month), `family:${month}`)
    add(sources.ai, 'AI 分析', ai, () => aiApi.listReports(), 'ai:reports')
    add(sources.budgetDetails, '分类预算', budgetDetails, () => budgetApi.getList(month), `budgets:${month}`)
    const ids = [...new Set(sources.accountIds)]
    for (const id of Object.keys(accountTransactions.value)) if (!ids.includes(id)) delete accountTransactions.value[id]
    for (const id of ids) {
      const key = `account:${id}`
      activeKeys.add(key)
      if (!force && accountTransactions.value[id]?.phase === 'ready' && !optionalTasks.has(key)) continue
      schedule(key, () => transactionApi.getList({ account_id: id, page_size: 3 }),
        value => { accountTransactions.value[id] = state(value.list, key, receivedAt()) },
        () => { accountTransactions.value[id] = { phase: 'error', data: null, queryKey: key, receivedAt: null, error: '账户记录加载失败' } },
      )
    }
    // Dropping one source must not invalidate requests for the other enabled widgets.
    for (const key of optionalTasks.keys()) if (!activeKeys.has(key)) optionalTasks.delete(key)
    const results = await Promise.all(jobs)
    if (session() !== ownerGeneration || results.includes('stale')) return 'stale'
    const enabled = optionalSources()
    optionalFailures.value = [
      ...(enabled.lending && lending.value.phase === 'error' ? ['借贷'] : []),
      ...(enabled.family && family.value.phase === 'error' ? ['家庭成员'] : []),
      ...(enabled.ai && ai.value.phase === 'error' ? ['AI 分析'] : []),
      ...(enabled.budgetDetails && budgetDetails.value.phase === 'error' ? ['分类预算'] : []),
      ...enabled.accountIds.filter(id => accountTransactions.value[id]?.phase === 'error').map(id => `账户记录:${id}`),
    ]
    return optionalFailures.value.length ? 'partial' : 'success'
  }

  function invalidate() { requests.begin(); optionalTasks.clear() }

  function reset() {
    invalidate()
    for (const resource of [accounts, overview, budget, debt, recentTransactions, lending, family, ai, budgetDetails]) {
      resource.value = { ...resource.value, phase: 'idle', data: null, receivedAt: null }
    }
    accountTransactions.value = {}; coreFailures.value = []; optionalFailures.value = []; loading.value = false
  }

  return {
    accounts, overview, budget, debt, recentTransactions, lending, family, ai,
    failures, loading, lastLoadedAt, values, budgetDetails, accountTransactions,
    load, loadOptional, invalidate, reset,
  }
}
