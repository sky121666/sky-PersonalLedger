import { describe, expect, it, vi } from 'vitest'
import type { RouteRecordRaw } from 'vue-router'
import { ref } from 'vue'
import { componentScript, flushWork } from '@/test/componentScript'

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({ initialized: true, isLoggedIn: true }),
}))
vi.mock('vue-router', async importOriginal => {
  const actual = await importOriginal<typeof import('vue-router')>()
  function withoutViews(routes: readonly RouteRecordRaw[]): RouteRecordRaw[] {
    return routes.map(route => ({
      ...route,
      component: { render: () => null },
      children: route.children ? withoutViews(route.children) : undefined,
    }) as RouteRecordRaw)
  }
  return {
    ...actual,
    createWebHashHistory: actual.createMemoryHistory,
    createRouter: (options: Parameters<typeof actual.createRouter>[0]) =>
      actual.createRouter({ ...options, routes: withoutViews(options.routes) }),
  }
})

describe('unified debt navigation', () => {
  it.each([
    { account_id: 'card-1' },
    { operation_id: 'receipt-1', account_id: 'card-1' },
    { account_id: 'standalone' },
  ])('keeps old debt links and their context through the unified route: %j', async query => {
    const { default: router } = await import('./index')
    await router.push({ path: '/debt', query })
    expect(router.currentRoute.value.path).toBe('/reminders')
    expect(router.currentRoute.value.query).toEqual(query)
    expect(router.currentRoute.value.name).toBe('reminders')
  })
})

describe('legacy reminders inside debt management', () => {
  function setup() {
    const view = componentScript('views/ReminderView.vue', [
      'debtAccounts', 'openCreate', 'openEdit', 'showDialog', 'openPayment', 'showPaymentDialog',
      'confirmDelete', 'showDeleteModal',
    ], {
      '@/api/account': { accountApi: { getList: async () => ({ list: [
        { id: 'legacy-card', type: 'credit', debt_tracking_mode: 'legacy' },
        { id: 'managed-card', type: 'credit', debt_tracking_mode: 'managed' },
        { id: 'cash', type: 'cash' },
      ] }) }, isDebtAccount: (type: string) => type === 'credit' },
      '@/api/reminder': { reminderApi: { getList: async () => [], getDebtSummary: async () => null } },
      '@/utils/attachmentCleanup': { deleteRemovedAttachments: vi.fn() },
      '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0) },
      '@/composables/useToast': { toast: { error: vi.fn() } },
    }, { embedded: true, active: true })
    view.mount()
    return view
  }

  it('offers only legacy accounts for a new reminder so plans cannot be paid through the old path', async () => {
    const view = setup()
    await flushWork()
    view.entry.openCreate()
    expect(view.entry.debtAccounts.value.map((account: { id: string }) => account.id)).toEqual(['legacy-card'])
    view.unmount()
  })

  it('retains the saved account while editing an existing reminder instead of silently unbinding it', async () => {
    const view = setup()
    await flushWork()
    view.entry.openEdit({ id: 'saved', account_id: 'managed-card', name: '旧提醒', loan_type: 'credit_card' })
    expect(view.entry.debtAccounts.value.map((account: { id: string }) => account.id)).toContain('managed-card')
    view.unmount()
  })

  it.each([
    ['openCreate', 'showDialog', undefined],
    ['openPayment', 'showPaymentDialog', { id: 'saved', name: '旧提醒', amount: 30 }],
    ['confirmDelete', 'showDeleteModal', 'saved'],
  ])('dismisses the idle %s modal when its section becomes inactive', async (action, state, argument) => {
    const view = setup()
    view.entry[action as string](argument)
    expect(view.entry[state as string].value).toBe(true)
    view.props.active = false
    await flushWork()
    expect(view.entry[state as string].value).toBe(false)
    view.unmount()
  })
})
