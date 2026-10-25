import { describe, expect, it, vi } from 'vitest'
import { reactive, ref } from 'vue'
import { componentScript, deferred, flushWork } from '@/test/componentScript'

const caps = { contract_version: 1, multiple_plans: true, explicit_allocation: true, reversal: true, managed_accounts: 'new_accounts_only', external_cash_interest: false, operation_history: true }
const card = { id: 'card', name: '模拟信用卡', type: 'credit', debt_tracking_mode: 'managed', current_balance: 1000, unplanned_debt: 100, unapplied_payment: 0, total_paid: 0, is_archived: false }
const plan = { id: 'A', account_id: 'card', name: '模拟分期', original_principal: 900, opening_principal: 900, principal_balance: 900, interest_balance: 0, principal_paid: 0, interest_paid: 0, estimated_interest: null, status: 'active', version: 1 }
const payment = { id: 'payment-1', kind: 'payment', account_id: 'card', source_account_id: 'cash', amount: 10, unapplied_amount: 10, reversed_by: null }
const paymentDetail = { operation: payment, allocations: [], account_effects: [], transactions: [], unallocated_amount: 10, active_allocations: [] }

function storage() {
  const entries = new Map<string, string>()
  return { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) }, removeItem: (key: string) => { entries.delete(key) } }
}

function setup(overrides: Record<string, any> = {}, session = storage()) {
  const account = { getList: vi.fn().mockResolvedValue({ list: [card, { id: 'cash', name: '模拟现金', type: 'cash', current_balance: 2000, is_archived: false }] }), ...overrides.account }
  const debt = {
    capabilities: vi.fn().mockResolvedValue(caps), plans: vi.fn().mockResolvedValue([plan]),
    operations: vi.fn().mockResolvedValue([payment]), details: vi.fn().mockResolvedValue(paymentDetail),
    send: vi.fn().mockResolvedValue(payment), ...overrides.debt,
  }
  const route = reactive({ query: { account_id: 'card' } as Record<string, string> })
  const router = { replace: vi.fn().mockResolvedValue(undefined), push: vi.fn() }
  const revision = ref(0)
  const component = componentScript('views/DebtView.vue', [
    'workspace', 'scope', 'parts', 'paymentForm', 'dialog', 'actionError', 'allocationReady',
    'loadData', 'openPayment', 'submitDialog', 'closeDialog', 'confirmPending', 'openOperation', 'openAllocation',
  ], {
    '@/api/debt': { debtApi: debt },
    '@/api/account': { accountApi: account },
    '@/api/auth': { authApi: { getProfile: async () => ({ id: 1 }) } },
    'vue-router': { useRoute: () => route, useRouter: () => router },
    '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => revision, notifyLedgerMutation: vi.fn() },
    '@/composables/useToast': { toast: { success: vi.fn(), error: vi.fn() } },
  }, {}, { sessionStorage: session })
  return { ...component, debt, account, route, router, session }
}

function fillPayment(view: ReturnType<typeof setup>) {
  view.entry.openPayment()
  Object.assign(view.entry.paymentForm.value, { amount: '10', source_account_id: 'cash' })
  view.entry.parts.value[0].principal = '10'
}

describe('Web multi-plan workflow reliability', () => {
  it('prevents a second payment while the first financial request is pending', async () => {
    const response = deferred()
    const view = setup({ debt: { send: vi.fn(() => response.promise) } })
    await flushWork()
    fillPayment(view)
    const first = view.entry.submitDialog()
    await view.entry.submitDialog()
    expect(view.debt.send).toHaveBeenCalledTimes(1)
    response.resolve(payment)
    await first
    view.unmount()
  })

  it('replays the exact payment after a lost response and form closure', async () => {
    const send = vi.fn().mockRejectedValueOnce(Error('response lost')).mockResolvedValue(payment)
    const view = setup({ debt: { send } })
    await flushWork()
    fillPayment(view)
    await view.entry.submitDialog()
    expect(view.entry.workspace.pending.value).not.toBeNull()
    view.entry.paymentForm.value.amount = '999'
    view.entry.closeDialog()
    await view.entry.confirmPending()
    expect(send).toHaveBeenCalledTimes(2)
    expect(send.mock.calls[1]![0].payload).toEqual(send.mock.calls[0]![0].payload)
    expect(send.mock.calls[1]![0].payload.amount).toBe(10)
    expect(send.mock.calls[1]![1]).toBe(send.mock.calls[0]![1])
    expect(view.entry.workspace.pending.value).toBeNull()
    view.unmount()
  })

  it('does not send a payment whose explicit allocations fail to balance', async () => {
    const view = setup()
    await flushWork()
    fillPayment(view)
    view.entry.paymentForm.value.amount = '11'
    await view.entry.submitDialog()
    expect(view.debt.send).not.toHaveBeenCalled()
    expect(view.entry.actionError.value).toContain('合计')
    view.unmount()
  })

  it('ignores a late operation detail response after selecting another receipt', async () => {
    const first = deferred()
    const view = setup({ debt: { details: vi.fn().mockReturnValueOnce(first.promise).mockResolvedValue({ ...paymentDetail, operation: { ...payment, id: 'new' } }) } })
    await flushWork()
    const old = view.entry.openOperation('old')
    await view.entry.openOperation('new')
    first.resolve(paymentDetail)
    await old
    expect(view.entry.workspace.detail.value.operation.id).toBe('new')
    view.unmount()
  })

  it('keeps a newer account snapshot when an earlier refresh finishes late', async () => {
    const first = deferred()
    const getList = vi.fn().mockReturnValueOnce(first.promise).mockResolvedValue({ list: [{ ...card, name: 'new snapshot' }] })
    const view = setup({ account: { getList } })
    await flushWork()
    await view.entry.loadData()
    first.resolve({ list: [{ ...card, name: 'old snapshot' }] })
    await flushWork()
    expect(view.entry.workspace.accounts.value[0].name).toBe('new snapshot')
    view.unmount()
  })

  it('blocks allocation after its authoritative detail request fails', async () => {
    const view = setup({ debt: { details: vi.fn().mockRejectedValue(Error('offline')) } })
    await flushWork()
    await view.entry.openAllocation(paymentDetail)
    expect(view.entry.allocationReady.value).toBe(false)
    await view.entry.submitDialog()
    expect(view.debt.send).not.toHaveBeenCalled()
    view.unmount()
  })

  it('does not downgrade into old repayment routes if debt capability is absent', async () => {
    const view = setup({ debt: { capabilities: vi.fn().mockRejectedValue({ status: 404 }) } })
    await flushWork()
    expect(view.entry.workspace.supported.value).toBeFalsy()
    expect(view.account.getList).not.toHaveBeenCalled()
    expect(view.debt.send).not.toHaveBeenCalled()
    view.unmount()
  })

  it('retains an idempotency conflict and blocks a new payment', async () => {
    const view = setup({ debt: { send: vi.fn().mockRejectedValue({ status: 409, code: 40903, message: 'conflict' }) } })
    await flushWork()
    fillPayment(view)
    await view.entry.submitDialog()
    expect(view.entry.workspace.pending.value).not.toBeNull()
    expect(view.entry.workspace.canWrite.value).toBeFalsy()
    await view.entry.submitDialog()
    expect(view.debt.send).toHaveBeenCalledTimes(1)
    view.unmount()
  })

  it.each([429, 401, 403, 400, 409])('keeps the original payment after a lost response and a %s confirmation refusal', async status => {
    const send = vi.fn()
      .mockRejectedValueOnce(Error('committed response lost'))
      .mockRejectedValueOnce({ status, code: status === 409 ? 40911 : status, message: 'confirmation refused' })
      .mockResolvedValue(payment)
    const view = setup({ debt: { send } })
    await flushWork()
    fillPayment(view)
    await view.entry.submitDialog()
    const original = view.entry.workspace.pending.value
    view.entry.closeDialog()
    await view.entry.confirmPending()
    expect(view.entry.workspace.pending.value?.key).toBe(original.key)
    expect(view.entry.workspace.canWrite.value).toBeFalsy()
    await view.entry.confirmPending()
    expect(send.mock.calls.map(call => call[1])).toEqual([original.key, original.key, original.key])
    expect(send.mock.calls[2]![0].payload).toEqual(send.mock.calls[0]![0].payload)
    expect(view.entry.workspace.pending.value).toBeNull()
    view.unmount()
  })

  it('releases a first payment that was definitely rejected before committing', async () => {
    const view = setup({ debt: { send: vi.fn().mockRejectedValue({ status: 400, message: 'invalid payment' }) } })
    await flushWork()
    fillPayment(view)
    await view.entry.submitDialog()
    expect(view.entry.workspace.pending.value).toBeNull()
    expect(view.entry.workspace.canWrite.value).toBeTruthy()
    view.unmount()
  })

  it('blocks new writes when pending-session evidence cannot be decoded', async () => {
    const session = storage()
    session.setItem('personal-ledger:debt-write:v1:1', '{invalid')
    const view = setup({}, session)
    await flushWork()
    expect(view.entry.workspace.canWrite.value).toBeFalsy()
    expect(view.entry.workspace.journalError.value).toContain('未确认')
    view.unmount()
  })

  it('asks the server to scope standalone history before its recent-operation limit', async () => {
    const view = setup()
    await flushWork()
    view.entry.scope.value = 'standalone'
    await flushWork()
    expect(view.debt.operations.mock.lastCall?.[1]).toMatchObject({ standalone_only: true })
    expect(view.router.replace).toHaveBeenLastCalledWith({ path: '/reminders', query: { account_id: 'standalone' } })
    view.unmount()
  })

  it('keeps a requested reminder section when navigation removes the previous account scope', async () => {
    const view = setup()
    await flushWork()
    view.route.query = { view: 'reminders' }
    await flushWork()
    expect(view.entry.scope.value).toBe('all')
    expect(view.router.replace).not.toHaveBeenCalled()
    view.unmount()
  })

  it('preserves an incoming receipt link while synchronizing its new account scope', async () => {
    const view = setup()
    await flushWork()
    view.route.query = { account_id: 'another-card', operation_id: 'payment-1' }
    await flushWork()
    expect(view.entry.scope.value).toBe('another-card')
    expect(view.router.replace).not.toHaveBeenCalled()
    expect(view.entry.workspace.detail.value?.operation.id).toBe('payment-1')
    view.unmount()
  })

  it('loads older receipts without losing or duplicating the first page', async () => {
    const firstPage = Array.from({ length: 100 }, (_, i) => ({ ...payment, id: `payment-${i}` }))
    const operations = vi.fn().mockResolvedValueOnce(firstPage).mockResolvedValueOnce([firstPage[99], { ...payment, id: 'older' }])
    const view = setup({ debt: { operations } })
    await flushWork()
    expect(view.entry.workspace.hasMoreOperations?.value).toBe(true)
    await view.entry.workspace.loadMoreOperations()
    expect(operations.mock.lastCall?.[1]).toMatchObject({ before: 'payment-99' })
    expect(view.entry.workspace.operations.value).toHaveLength(101)
    expect(view.entry.workspace.operations.value.at(-1).id).toBe('older')
    expect(view.entry.workspace.hasMoreOperations.value).toBe(false)
    view.unmount()
  })

  it('ignores an old history page after the account scope changes', async () => {
    const older = deferred()
    const firstPage = Array.from({ length: 100 }, (_, i) => ({ ...payment, id: `payment-${i}` }))
    const operations = vi.fn().mockResolvedValueOnce(firstPage).mockReturnValueOnce(older.promise).mockResolvedValue([{ ...payment, id: 'standalone-new' }])
    const view = setup({ debt: { operations } })
    await flushWork()
    expect(typeof view.entry.workspace.loadMoreOperations).toBe('function')
    const previousPage = view.entry.workspace.loadMoreOperations()
    view.entry.scope.value = 'standalone'
    await flushWork()
    older.resolve([{ ...payment, id: 'old-scope' }])
    await previousPage
    expect(view.entry.workspace.operations.value.map((item: any) => item.id)).toEqual(['standalone-new'])
    view.unmount()
  })
})
