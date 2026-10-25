import { ref } from 'vue'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { componentScript, deferred, flushWork } from '@/test/componentScript'

const reminder = { id: 'debt-1', name: '贷款', loan_type: 'other', payment_day: 31, advance_days: 3, amount: 50, principal: 100, current_balance: 100, total_paid: 0, interest_paid: 0, color: '#2563EB', remark: '', evidence: '', is_enabled: true, created_at: '2026-01-01' }
const lending = { id: 'lending-1', user_id: 1, type: 'lend_out', contact_name: '张三', principal: 100, current_balance: 100, total_repaid: 0, lend_date: '2026-01-01', is_settled: false, created_at: '2026-01-01', updated_at: '2026-01-01' }

function sessionStorage() {
  const values = new Map<string, string>()
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => { values.set(key, value) },
    removeItem: (key: string) => { values.delete(key) },
  }
}

function setup(viewName: 'Reminder' | 'Lending' | 'Accounts', overrides: Record<string, unknown> = {}, globals: Record<string, unknown> = {}) {
  const toast = { error: vi.fn(), success: vi.fn(), warning: vi.fn() }
  const api = {
    create: vi.fn().mockResolvedValue({}), update: vi.fn().mockResolvedValue({}),
    recordPayment: vi.fn().mockResolvedValue({}), recordRepayment: vi.fn().mockResolvedValue({}),
    getList: vi.fn().mockResolvedValue(viewName === 'Accounts' ? { list: [], total_assets: 0, total_liabilities: 0 } : []),
    list: vi.fn().mockResolvedValue([]), getDebtSummary: vi.fn().mockResolvedValue({}), getSummary: vi.fn().mockResolvedValue({}),
    ...overrides,
  }
  const cleanup = vi.fn().mockResolvedValue([])
  const revision = ref(0)
  const notifyLedgerMutation = vi.fn(() => { revision.value += 1 })
  const common = ['openCreate', 'openEdit', 'closeDialog', 'submitForm', 'showDialog', 'form', 'saving']
  const payment = viewName === 'Reminder' ? ['openPayment', 'closePaymentDialog', 'submitPayment', 'showPaymentDialog', 'payingReminder', 'paymentAmount', 'paymentPrincipal', 'paymentInterest', 'paymentAccountId', 'paymentError', 'getDaysUntilPayment', 'pendingPayments', 'loadData'] : []
  const repay = viewName === 'Lending' ? ['openRepay', 'closeRepayDialog', 'submitRepay', 'showRepayDialog', 'repayingLending', 'repayForm', 'repaymentError', 'pendingRepayments', 'loadData'] : []
  const component = componentScript(`views/${viewName}View.vue`, [...common, ...payment, ...repay], {
    '@/composables/useToast': { toast },
    '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => revision, notifyLedgerMutation },
    '@/utils/attachmentCleanup': { deleteRemovedAttachments: cleanup },
    '@/api/account': { accountApi: viewName === 'Accounts' ? api : { getList: async () => ({ list: [] }) }, isDebtAccount: () => false },
    '@/api/debt': { debtApi: { capabilities: async () => ({ contract_version: 0 }) } },
    '@/api/reminder': { reminderApi: api },
    '@/api/lending': { lendingApi: api },
  }, {}, { sessionStorage: sessionStorage(), ...globals })
  return { ...component, api, toast, cleanup, notifyLedgerMutation }
}

function fillCreate(view: ReturnType<typeof setup>, name: string, label: string) {
  view.entry.openCreate('lend_out')
  if (name === 'Lending') Object.assign(view.entry.form.value, { contact_name: label, principal: 100 })
  else view.entry.form.value.name = label
}

afterEach(() => vi.useRealTimers())

describe('lending local date inputs', () => {
  it('sends an explicit instant when creating a lending from a datetime-local field', async () => {
    const view = setup('Lending')
    fillCreate(view, 'Lending', '模拟借款人')
    view.entry.form.value.lend_date = '2026-10-15T08:30'
    await view.entry.submitForm()
    expect(view.api.create).toHaveBeenCalledWith(expect.objectContaining({
      lend_date: new Date('2026-10-15T08:30').toISOString(),
    }))
    view.unmount()
  })

  it('normalizes an optional due date when creating a lending', async () => {
    const view = setup('Lending')
    fillCreate(view, 'Lending', '模拟借款人')
    view.entry.form.value.due_date = '2026-11-15T18:30'
    await view.entry.submitForm()
    expect(view.api.create).toHaveBeenCalledWith(expect.objectContaining({
      due_date: new Date('2026-11-15T18:30').toISOString(),
    }))
    view.unmount()
  })

  it('preserves a due date when editing only the contact name', async () => {
    const view = setup('Lending')
    const dueDate = new Date('2026-11-15T18:30').toISOString()
    view.entry.openEdit({ ...lending, due_date: dueDate })
    view.entry.form.value.contact_name = '已改名'
    await view.entry.submitForm()
    expect(view.api.update).toHaveBeenCalledWith(lending.id, expect.objectContaining({
      contact_name: '已改名', due_date: dueDate,
    }))
    view.unmount()
  })

  it('sends an explicit null when clearing a saved due date', async () => {
    const view = setup('Lending')
    view.entry.openEdit({ ...lending, due_date: '2026-11-15T18:30:00+08:00' })
    view.entry.form.value.due_date = ''
    await view.entry.submitForm()
    expect(view.api.update).toHaveBeenCalledWith(lending.id, expect.objectContaining({ due_date: null }))
    view.unmount()
  })

  it('replays a legacy minute precision pending request without changing its payload or key', async () => {
    const storage = sessionStorage()
    const key = '11111111-1111-4111-8111-111111111111'
    const payload = { amount: 50, record_date: '2026-10-15T08:30', create_transaction: false }
    const storageKey = `personal-ledger:pending-repayment:v1:lending:${lending.id}`
    storage.setItem(storageKey, JSON.stringify({ version: 1, kind: 'lending', targetId: lending.id, key, payload, attempt: 1 }))
    const view = setup('Lending', {}, { sessionStorage: storage })
    view.entry.openRepay(lending)
    expect(view.entry.repayForm.value.record_date).toBe(payload.record_date)
    await view.entry.submitRepay()
    expect(view.api.recordRepayment).toHaveBeenCalledWith(lending.id, { ...payload, idempotency_key: key })
    expect(storage.getItem(storageKey)).toBeNull()
    view.unmount()
  })

  it('keeps local repayment fields readable while retries resend the original instant', async () => {
    const send = vi.fn().mockRejectedValueOnce(Error('response lost')).mockResolvedValue({})
    const view = setup('Lending', { recordRepayment: send })
    view.entry.openRepay(lending)
    view.entry.repayForm.value.record_date = '2026-10-15T08:30'
    await view.entry.submitRepay()
    expect(send.mock.calls[0]![1].record_date).toBe(new Date('2026-10-15T08:30').toISOString())
    view.entry.closeRepayDialog()
    view.entry.openRepay(lending)
    expect(view.entry.repayForm.value.record_date).toBe('2026-10-15T08:30')
    await view.entry.submitRepay()
    expect(send.mock.calls[1]).toEqual(send.mock.calls[0])
    view.unmount()
  })
})

describe('planning form submission identity', () => {
  it.each(['Reminder', 'Lending', 'Accounts'] as const)('%s blocks a second save while its first request is pending', async name => {
    const pending = deferred()
    const create = vi.fn(() => pending.promise)
    const view = setup(name, { create })
    fillCreate(view, name, '原表单')
    const first = view.entry.submitForm()
    const duplicate = view.entry.submitForm()
    expect(create).toHaveBeenCalledTimes(1)
    pending.resolve({})
    await Promise.all([first, duplicate])
    expect(view.entry.showDialog.value).toBe(false)
    view.unmount()
  })

  it.each(['Reminder', 'Lending', 'Accounts'] as const)('%s keeps a reopened form intact when an earlier save finishes', async name => {
    const pending = deferred()
    const view = setup(name, { create: () => pending.promise })
    fillCreate(view, name, '原表单')
    const first = view.entry.submitForm()
    view.entry.closeDialog()
    fillCreate(view, name, '新表单')
    pending.resolve({})
    await first
    expect(view.entry.showDialog.value).toBe(true)
    expect(view.entry.form.value[name === 'Lending' ? 'contact_name' : 'name']).toBe('新表单')
    expect(view.toast.success).not.toHaveBeenCalled()
    expect(view.notifyLedgerMutation).toHaveBeenCalledTimes(1)
    await flushWork()
    expect(view.api.getList).toHaveBeenCalledTimes(name === 'Lending' ? 0 : 1)
    if (name === 'Lending') expect(view.api.list).toHaveBeenCalledTimes(1)
    view.unmount()
  })

  it.each(['Reminder', 'Lending'] as const)('%s captures saved attachment state before the request completes', async name => {
    const pending = deferred()
    const view = setup(name, { update: () => pending.promise })
    view.entry.openEdit({ ...(name === 'Reminder' ? reminder : lending), evidence: 'old-file' })
    view.entry.form.value.evidence = 'saved-file'
    const save = view.entry.submitForm()
    view.entry.form.value.evidence = 'later-file'
    pending.resolve({})
    await save
    expect(view.cleanup).toHaveBeenCalledWith('old-file', 'saved-file')
    view.unmount()
  })

  it.each(['Reminder', 'Lending', 'Accounts'] as const)('%s suppresses an old failure and retains the new form submission lock', async name => {
    const old = deferred()
    const current = deferred()
    const create = vi.fn().mockImplementationOnce(() => old.promise).mockImplementation(() => current.promise)
    const view = setup(name, { create })
    fillCreate(view, name, '原表单')
    const first = view.entry.submitForm()
    view.entry.closeDialog()
    fillCreate(view, name, '新表单')
    const second = view.entry.submitForm()
    old.reject(Error('old timeout'))
    await first
    expect(view.entry.saving.value).toBe(true)
    expect(view.toast.error).not.toHaveBeenCalled()
    await view.entry.submitForm()
    expect(create).toHaveBeenCalledTimes(2)
    current.resolve({})
    await second
    expect(view.entry.saving.value).toBe(false)
    view.unmount()
  })

  it.each(['Reminder', 'Lending', 'Accounts'] as const)('%s leaves a failed form editable and ignores its completion after unmount', async name => {
    const pending = deferred()
    const create = vi.fn().mockRejectedValueOnce(Error('first timeout')).mockImplementation(() => pending.promise)
    const view = setup(name, { create })
    fillCreate(view, name, '原表单')
    await view.entry.submitForm()
    expect(view.entry.showDialog.value).toBe(true)
    expect(view.entry.saving.value).toBe(false)
    const retried = view.entry.submitForm()
    view.unmount()
    pending.resolve({})
    await retried
    expect(view.toast.success).not.toHaveBeenCalled()
  })
})

describe('repayment amount and retry identity', () => {
  it.each([[100, 10], [0, 10], [100, 0]])('accepts payment 110 against principal balance 100 with split %s / %s', async (principal, interest) => {
    const view = setup('Reminder')
    view.entry.openPayment(reminder)
    view.entry.paymentAmount.value = 110
    view.entry.paymentPrincipal.value = principal
    view.entry.paymentInterest.value = interest
    view.entry.paymentAccountId.value = 'cash-1'
    await view.entry.submitPayment()
    expect(view.api.recordPayment).toHaveBeenCalledWith('debt-1', 110, 'cash-1', 100, 10, expect.any(String))
    view.unmount()
  })

  it.each([[101, 0, 100], [10, 0, 0], [90, -10, 100]])('rejects invalid principal or negative split: %s / %s against %s', async (amount, interest, balance) => {
    const view = setup('Reminder')
    view.entry.openPayment({ ...reminder, current_balance: balance })
    view.entry.paymentAmount.value = amount
    view.entry.paymentInterest.value = interest
    view.entry.paymentAccountId.value = 'cash-1'
    await view.entry.submitPayment()
    expect(view.api.recordPayment).not.toHaveBeenCalled()
    expect(view.toast.warning).toHaveBeenCalled()
    view.unmount()
  })

  for (const kind of ['Reminder', 'Lending'] as const) {
    const apiMethod = kind === 'Reminder' ? 'recordPayment' : 'recordRepayment'
    const submitMethod = kind === 'Reminder' ? 'submitPayment' : 'submitRepay'
    function open(view: ReturnType<typeof setup>) {
      if (kind === 'Reminder') {
        view.entry.openPayment(reminder)
        view.entry.paymentAccountId.value = 'cash-1'
      } else view.entry.openRepay(lending)
    }
    function key(call: any[]) { return kind === 'Reminder' ? call[5] : call[1].idempotency_key }

    it(`${kind} blocks duplicate repayments and reuses the key after an uncertain response`, async () => {
      const pending = deferred()
      const send = vi.fn().mockImplementationOnce(() => pending.promise).mockResolvedValue({})
      const view = setup(kind, { [apiMethod]: send })
      open(view)
      const first = view.entry[submitMethod]()
      await view.entry[submitMethod]()
      expect(send).toHaveBeenCalledTimes(1)
      pending.reject(Error('timeout'))
      await first
      const firstKey = key(send.mock.calls[0]!)
      expect(firstKey).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
      await view.entry[submitMethod]()
      expect(key(send.mock.calls[1]!)).toBe(firstKey)
      open(view)
      await view.entry[submitMethod]()
      expect(key(send.mock.calls[2]!)).not.toBe(firstKey)
      view.unmount()
    })

    it.each([undefined, 408, 500])(`${kind} restores the original repayment after uncertain status %s when its amount is edited`, async status => {
      const send = vi.fn().mockRejectedValue(Object.assign(Error('timeout'), { status }))
      const view = setup(kind, { [apiMethod]: send })
      open(view)
      await view.entry[submitMethod]()
      if (kind === 'Reminder') view.entry.paymentAmount.value = 25
      else view.entry.repayForm.value.amount = 25
      await view.entry[submitMethod]()
      expect(key(send.mock.calls[1]!)).toBe(key(send.mock.calls[0]!))
      expect(send.mock.calls[1]).toEqual(send.mock.calls[0])
      expect(kind === 'Reminder' ? view.entry.paymentAmount.value : view.entry.repayForm.value.amount).toBe(kind === 'Reminder' ? 50 : 100)
      view.unmount()
    })

    it.each(['reopen', 'reload'] as const)(`${kind} confirms a committed repayment after %s without recording a second payment`, async recovery => {
      const storage = sessionStorage()
      const committed = new Set<string>()
      let writes = 0
      const send = vi.fn(async (...args: any[]) => {
        const identity = key(args)
        if (!committed.has(identity)) {
          committed.add(identity)
          writes += 1
          throw Error('response lost after commit')
        }
        return {}
      })
      let view = setup(kind, { [apiMethod]: send }, { sessionStorage: storage })
      open(view)
      await view.entry[submitMethod]()
      view.entry[kind === 'Reminder' ? 'closePaymentDialog' : 'closeRepayDialog']()
      if (recovery === 'reload') {
        view.unmount()
        view = setup(kind, { [apiMethod]: send }, { sessionStorage: storage })
      }
      view.api.getList.mockResolvedValue([{ ...reminder, current_balance: 0, paid_off_at: '2026-10-12' }])
      view.api.list.mockResolvedValue([{ ...lending, current_balance: 0, is_settled: true }])
      await view.entry.loadData()
      expect(view.entry[kind === 'Reminder' ? 'pendingPayments' : 'pendingRepayments'].value).toHaveLength(1)
      if (kind === 'Reminder') view.entry.openPayment({ ...reminder, current_balance: 0, amount: 0 })
      else view.entry.openRepay({ ...lending, current_balance: 0 })
      // Even a programmatic edit must not bypass the locked, previously sent payload.
      if (kind === 'Reminder') view.entry.paymentAmount.value = 25
      else view.entry.repayForm.value.amount = 25
      await view.entry[submitMethod]()
      expect(send).toHaveBeenCalledTimes(2)
      expect(send.mock.calls[1]).toEqual(send.mock.calls[0])
      expect(writes).toBe(1)
      expect(view.entry[kind === 'Reminder' ? 'showPaymentDialog' : 'showRepayDialog'].value).toBe(false)
      open(view)
      await view.entry[submitMethod]()
      expect(key(send.mock.calls[2]!)).not.toBe(key(send.mock.calls[0]!))
      view.unmount()
    })

    it(`${kind} releases a definitively rejected first request so its corrected amount can be submitted`, async () => {
      const send = vi.fn().mockRejectedValueOnce(Object.assign(Error('invalid amount'), { status: 400 })).mockResolvedValue({})
      const view = setup(kind, { [apiMethod]: send })
      open(view)
      await view.entry[submitMethod]()
      expect(view.entry[kind === 'Reminder' ? 'paymentError' : 'repaymentError'].value).toBe('invalid amount')
      if (kind === 'Reminder') view.entry.paymentAmount.value = 25
      else view.entry.repayForm.value.amount = 25
      await view.entry[submitMethod]()
      expect(key(send.mock.calls[1]!)).not.toBe(key(send.mock.calls[0]!))
      expect(kind === 'Reminder' ? send.mock.calls[1]![1] : send.mock.calls[1]![1].amount).toBe(25)
      view.unmount()
    })

    it(`${kind} cannot lose an unknown repayment when a later confirmation is unauthorized`, async () => {
      const send = vi.fn().mockRejectedValueOnce(Error('timeout')).mockRejectedValueOnce(Object.assign(Error('login expired'), { status: 401 })).mockResolvedValue({})
      const view = setup(kind, { [apiMethod]: send })
      open(view)
      await view.entry[submitMethod]()
      await view.entry[submitMethod]()
      view.entry[kind === 'Reminder' ? 'closePaymentDialog' : 'closeRepayDialog']()
      open(view)
      await view.entry[submitMethod]()
      expect(send.mock.calls[2]).toEqual(send.mock.calls[0])
      view.unmount()
    })

    it(`${kind} blocks sending if the pending operation cannot be persisted`, async () => {
      const view = setup(kind, {}, { sessionStorage: { ...sessionStorage(), setItem: () => { throw Error('storage unavailable') } } })
      open(view)
      await view.entry[submitMethod]()
      expect(view.api[apiMethod]).not.toHaveBeenCalled()
      expect(view.entry[kind === 'Reminder' ? 'showPaymentDialog' : 'showRepayDialog'].value).toBe(true)
      expect(view.toast.error).toHaveBeenCalled()
      view.unmount()
    })

    it(`${kind} retains a newer confirmation when an earlier rejection arrives late`, async () => {
      const storage = sessionStorage()
      const firstResponse = deferred()
      const secondResponse = deferred()
      const send = vi.fn().mockImplementationOnce(() => firstResponse.promise).mockImplementationOnce(() => secondResponse.promise).mockResolvedValue({})
      let view = setup(kind, { [apiMethod]: send }, { sessionStorage: storage })
      open(view)
      const first = view.entry[submitMethod]()
      view.entry[kind === 'Reminder' ? 'closePaymentDialog' : 'closeRepayDialog']()
      open(view)
      const second = view.entry[submitMethod]()
      firstResponse.reject(Object.assign(Error('temporarily insufficient balance'), { status: 400 }))
      await first
      secondResponse.reject(Error('response lost after retry committed'))
      await second
      view.unmount()
      view = setup(kind, { [apiMethod]: send }, { sessionStorage: storage })
      open(view)
      await view.entry[submitMethod]()
      expect(send.mock.calls[2]).toEqual(send.mock.calls[1])
      view.unmount()
    })

    it(`${kind} does not close a new repayment dialog after an old repayment succeeds`, async () => {
      const pending = deferred()
      const send = vi.fn(() => pending.promise)
      const view = setup(kind, { [apiMethod]: send })
      open(view)
      const first = view.entry[submitMethod]()
      view.entry[kind === 'Reminder' ? 'closePaymentDialog' : 'closeRepayDialog']()
      open(view)
      pending.resolve({})
      await first
      expect(view.entry[kind === 'Reminder' ? 'showPaymentDialog' : 'showRepayDialog'].value).toBe(true)
      expect(view.toast.success).not.toHaveBeenCalled()
      expect(view.notifyLedgerMutation).toHaveBeenCalledTimes(1)
      await view.entry[submitMethod]()
      expect(send.mock.calls[1]).toEqual(send.mock.calls[0])
      expect(view.entry[kind === 'Reminder' ? 'showPaymentDialog' : 'showRepayDialog'].value).toBe(false)
      view.unmount()
    })

    it(`${kind} suppresses an old repayment error without unlocking a newer request`, async () => {
      const old = deferred()
      const current = deferred()
      const send = vi.fn().mockImplementationOnce(() => old.promise).mockImplementation(() => current.promise)
      const view = setup(kind, { [apiMethod]: send })
      open(view)
      const first = view.entry[submitMethod]()
      view.entry[kind === 'Reminder' ? 'closePaymentDialog' : 'closeRepayDialog']()
      open(view)
      const second = view.entry[submitMethod]()
      old.reject(Error('old timeout'))
      await first
      await view.entry[submitMethod]()
      expect(send).toHaveBeenCalledTimes(2)
      expect(view.toast.error).not.toHaveBeenCalled()
      current.resolve({})
      await second
      view.unmount()
    })
  }

  it('creates a stable UUID retry key on LAN origins without crypto.randomUUID', async () => {
    const view = setup('Reminder', {}, { crypto: { getRandomValues: (bytes: Uint8Array<ArrayBuffer>) => globalThis.crypto.getRandomValues(bytes) } })
    view.entry.openPayment(reminder)
    view.entry.paymentAccountId.value = 'cash-1'
    await view.entry.submitPayment()
    expect(view.api.recordPayment).toHaveBeenCalledWith('debt-1', 50, 'cash-1', 50, 0, expect.stringMatching(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i))
    view.unmount()
  })
})

describe('repayment calendar month-end rules', () => {
  it.each([
    ['2026-04-30T12:00:00', 31, 0],
    ['2026-02-28T12:00:00', 31, 0],
    ['2028-02-29T12:00:00', 30, 0],
    ['2026-01-31T12:00:00', 30, 28],
    ['2026-04-29T12:00:00', 31, 1],
  ])('on %s the next day-%s payment is %s days away', (today, day, expected) => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(today))
    const view = setup('Reminder')
    expect(view.entry.getDaysUntilPayment(day)).toBe(expected)
    view.unmount()
  })
})

describe('family budget month and non-overlapping totals', () => {
  function family(budgetLoader = vi.fn().mockResolvedValue({ member_budgets: [] })) {
    const toast = { error: vi.fn() }
    const view = componentScript('views/FamilyView.vue', ['loadData', 'month', 'memberBudgets', 'memberBudgetStats', 'summary', 'loading', 'loadError'], {
      '@/composables/useToast': { toast },
      '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0) },
      '@/api/family': { familyApi: { listMembers: async () => [], getSummary: async (month: string) => ({ month, total_expense: 0, members: [] }), getStatistics: async (month: string) => ({ month, total_expense: 0, members: [] }) } },
      '@/api/budget': { budgetApi: { getList: budgetLoader } },
    })
    return { ...view, budgetLoader, toast }
  }

  it('requests the selected month and excludes late budgets from the previous month', async () => {
    const old = deferred()
    const loader = vi.fn().mockImplementationOnce(() => old.promise).mockResolvedValue({ member_budgets: [{ id: 'new-budget', member_id: 'one', category_id: null, amount: 200, spent: 50 }] })
    const view = family(loader)
    view.entry.month.value = '2026-04'
    const first = view.entry.loadData()
    view.entry.month.value = '2026-05'
    await view.entry.loadData()
    expect(loader.mock.calls).toEqual([['2026-04'], ['2026-05']])
    old.resolve({ member_budgets: [{ id: 'old-budget' }] })
    await first
    expect(view.entry.memberBudgets.value[0].id).toBe('new-budget')
    expect(view.entry.summary.value.month).toBe('2026-05')
    view.unmount()
  })

  it('prefers each member total over category budgets without counting spent twice', () => {
    const view = family()
    view.entry.memberBudgets.value = [
      { id: 'one-total', member_id: 'one', category_id: null, amount: 1000, spent: 400 },
      { id: 'one-food', member_id: 'one', category_id: 'food', amount: 300, spent: 200 },
      { id: 'two-food', member_id: 'two', category_id: 'food', amount: 200, spent: 50 },
      { id: 'two-travel', member_id: 'two', category_id: 'travel', amount: 100, spent: 20 },
    ]
    expect(view.entry.memberBudgetStats.value).toMatchObject({ amount: 1300, spent: 470, remaining: 830, percentage: 36 })
    view.unmount()
  })

  it('clears prior-month budgets when the newly selected month cannot load', async () => {
    const loader = vi.fn().mockResolvedValueOnce({ member_budgets: [{ id: 'old-budget' }] }).mockRejectedValue(Error('unavailable'))
    const view = family(loader)
    await view.entry.loadData()
    view.entry.month.value = '2000-01'
    await view.entry.loadData()
    await flushWork()
    expect(view.entry.memberBudgets.value).toEqual([])
    expect(view.entry.summary.value).toBeNull()
    expect(view.entry.loadError?.value).toBe('unavailable')
    loader.mockResolvedValueOnce({ member_budgets: [] })
    await view.entry.loadData()
    expect(view.entry.loadError.value).toBe('')
    view.unmount()
  })
})
