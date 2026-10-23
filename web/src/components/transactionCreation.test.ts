import { afterEach, describe, expect, it, vi } from 'vitest'
import { componentScript, deferred, flushWork } from '@/test/componentScript'

const dialogs: ReturnType<typeof componentScript>[] = []
afterEach(() => dialogs.splice(0).forEach(d => d.unmount()))

function storage() {
  const data = new Map<string, string>()
  return { getItem: (k: string) => data.get(k) ?? null, setItem: (k: string, v: string) => { data.set(k, v) }, removeItem: (k: string) => { data.delete(k) } }
}

async function open(create: any, session = storage(), userId = 1) {
  const dialog = componentScript('components/TransactionDialog.vue', ['form', 'submit', 'finishCreateConfirmation'], {
    '@/api/transaction': { transactionApi: { create } },
    '@/api/auth': { authApi: { getProfile: async () => ({ id: userId }) } },
    '@/api/category': { categoryApi: { getList: async () => [{ id: 'food', type: 'expense' }] } },
    '@/api/account': { accountApi: { getList: async () => ({ list: [{ id: 'cash' }] }) } },
    '@/api/family': { familyApi: { listMembers: async () => [] } },
    '@/api/tag': { tagApi: { list: async () => [] } },
    '@/composables/useToast': { toast: { success: vi.fn(), error: vi.fn() } },
    '@/composables/useLedgerMutation': { notifyLedgerMutation: vi.fn() },
    '@/utils/attachmentCleanup': { deleteRemovedAttachments: async () => [] },
  }, { visible: true, editId: null }, { sessionStorage: session })
  dialogs.push(dialog)
  await flushWork()
  return dialog
}

function fill(d: ReturnType<typeof componentScript>, amount = '10') {
  Object.assign(d.entry.form.value, { amount, category_id: 'food', account_id: 'cash' })
}

describe('ordinary transaction creation retry', () => {
  it('retries the exact uncertain request instead of saving a changed form', async () => {
    const create = vi.fn().mockRejectedValueOnce(Error('response lost')).mockResolvedValue({ id: 'saved' })
    const d = await open(create)
    fill(d)
    await d.entry.submit()
    fill(d, '99')
    await d.entry.submit()
    const [first, second] = create.mock.calls.map(call => call[0])
    expect(first.idempotency_key).toMatch(/^[0-9a-f-]{36}$/i)
    expect(second).toEqual(first)
    expect(second.amount).toBe(10)
  })

  it('recovers the same key and amount after closing and reopening', async () => {
    const session = storage()
    const create = vi.fn().mockRejectedValueOnce(Error('response lost')).mockResolvedValue({ id: 'saved' })
    const first = await open(create, session)
    fill(first)
    await first.entry.submit()
    first.unmount()
    const second = await open(create, session)
    await second.entry.submit()
    expect(create).toHaveBeenCalledTimes(2)
    expect(create.mock.calls[1]![0]).toEqual(create.mock.calls[0]![0])
  })

  it('does not send a financial write when the confirmation record cannot be stored', async () => {
    const create = vi.fn()
    const d = await open(create, { ...storage(), setItem() { throw Error('quota') } })
    fill(d)
    await d.entry.submit()
    expect(create).not.toHaveBeenCalled()
  })

  it('does not expose another user pending request', async () => {
    const session = storage()
    const create = vi.fn().mockRejectedValue(Error('lost'))
    const first = await open(create, session, 1)
    fill(first)
    await first.entry.submit()
    const second = await open(create, session, 2)
    expect(second.entry.form.value.amount).toBe('')
  })

  it('permits a corrected new request after a definite first-attempt refusal', async () => {
    const create = vi.fn().mockRejectedValueOnce({ status: 400, message: 'invalid reference' }).mockResolvedValue({ id: 'saved' })
    const d = await open(create)
    fill(d)
    await d.entry.submit()
    fill(d, '20')
    await d.entry.submit()
    expect(create.mock.calls[1]![0].amount).toBe(20)
    expect(create.mock.calls[1]![0].idempotency_key).not.toBe(create.mock.calls[0]![0].idempotency_key)
  })

  it('keeps an ambiguous first attempt after a later refusal', async () => {
    const session = storage()
    const create = vi.fn().mockRejectedValueOnce(Error('lost')).mockRejectedValueOnce({ status: 400 })
    const d = await open(create, session)
    fill(d)
    await d.entry.submit()
    await d.entry.submit()
    const reopened = await open(create, session)
    expect(reopened.entry.form.value.amount).toBe('10')
  })

  it('does not let an older success clear a newer confirmation attempt', async () => {
    const session = storage(), firstResult = deferred(), secondResult = deferred()
    const create = vi.fn().mockImplementationOnce(() => firstResult.promise).mockImplementationOnce(() => secondResult.promise)
    const first = await open(create, session)
    fill(first)
    const saving = first.entry.submit()
    const second = await open(create, session)
    const confirming = second.entry.submit()
    firstResult.resolve({ id: 'saved' })
    await saving
    const reopened = await open(create, session)
    expect(reopened.entry.form.value.amount).toBe('10')
    secondResult.resolve({ id: 'saved' })
    await confirming
  })

  it('keeps the original key when an earlier success clears storage before confirmation starts', async () => {
    const session = storage(), result = deferred()
    const create = vi.fn().mockImplementationOnce(() => result.promise).mockResolvedValue({ id: 'saved' })
    const first = await open(create, session)
    fill(first)
    const saving = first.entry.submit()
    first.props.visible = false
    const reopened = await open(create, session)
    result.resolve({ id: 'saved' })
    await saving
    await reopened.entry.submit()
    expect(create).toHaveBeenCalledTimes(2)
    expect(create.mock.calls[1]![0].idempotency_key).toBe(create.mock.calls[0]![0].idempotency_key)
  })

  it.each([40903, 40913])('requires explicit completion after conflict %s and clears the old form', async code => {
    const create = vi.fn().mockRejectedValueOnce(Error('lost'))
      .mockRejectedValueOnce({ status: 409, code, message: '请核对原交易' }).mockResolvedValue({ id: 'new-intent' })
    const d = await open(create)
    fill(d)
    await d.entry.submit()
    await d.entry.submit()
    expect(d.entry.form.value.amount).toBe('10')
    expect(create).toHaveBeenCalledTimes(2)
    d.entry.finishCreateConfirmation()
    expect(d.entry.form.value.amount).toBe('')
    fill(d, '20')
    await d.entry.submit()
    expect(create.mock.calls[2]![0].amount).toBe(20)
    expect(create.mock.calls[2]![0].idempotency_key).not.toBe(create.mock.calls[0]![0].idempotency_key)
  })
})
