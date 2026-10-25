import { describe, expect, it, vi } from 'vitest'
import { ref } from 'vue'
import { componentScript, flushWork } from '@/test/componentScript'
import { isDebtAccount } from '@/utils/accountTypeRules'

function setup() {
  const router = { push: vi.fn() }
  const api = { create: vi.fn(async (_data: unknown) => ({ id: 'new-card' })), update: vi.fn(async (_id: string, _data: unknown) => ({})),
    getList: async () => ({ list: [], total_assets: 0, total_liabilities: 0 }) }
  const view = componentScript('views/AccountsView.vue', ['form', 'isFormValid', 'openCreate', 'openEdit', 'submitForm'], {
    'vue-router': { useRouter: () => router },
    '@/api/account': { accountApi: api, isDebtAccount },
    '@/api/debt': { debtApi: { capabilities: async () => ({
      contract_version: 1, multiple_plans: true, explicit_allocation: true, reversal: true, managed_accounts: 'new_accounts_only',
    }) } },
    '@/composables/useToast': { toast: { success: vi.fn(), error: vi.fn() } },
    '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0), notifyLedgerMutation: vi.fn() },
  })
  view.mount()
  return { ...view, api, router }
}

describe('wallet managed-mode compatibility', () => {
  it.each([0, 1000, '1000'])('accepts Vue numeric input coercion for a new managed opening balance %s', async amount => {
    const view = setup()
    await flushWork()
    view.entry.openCreate()
    Object.assign(view.entry.form.value, { name: '模拟分期信用卡', type: 'credit', debt_tracking_mode: 'managed', initial_balance: amount })
    expect(view.entry.isFormValid.value).toBe(true)
    await view.entry.submitForm()
    expect(view.api.create).toHaveBeenCalledWith(expect.objectContaining({
      debt_tracking_mode: 'managed', initial_balance: Number(amount),
    }))
    expect(view.router.push).toHaveBeenCalledWith({ path: '/reminders', query: { account_id: 'new-card' } })
    view.unmount()
  })

  it('omits the new field for legacy creation and never converts a saved account while editing', async () => {
    const view = setup()
    await flushWork()
    view.entry.openCreate()
    Object.assign(view.entry.form.value, { name: '旧模式信用卡', type: 'credit', initial_balance: '100' })
    await view.entry.submitForm()
    expect(view.api.create.mock.calls[0]![0]).not.toHaveProperty('debt_tracking_mode')
    view.entry.openEdit({ id: 'legacy', name: '旧账户', type: 'credit', icon: '', color: '#007AFF', initial_balance: 100 })
    view.entry.form.value.name = '旧账户改名'
    await view.entry.submitForm()
    expect(view.api.update).toHaveBeenCalledWith('legacy', expect.not.objectContaining({ debt_tracking_mode: expect.anything() }))
    view.unmount()
  })
})
