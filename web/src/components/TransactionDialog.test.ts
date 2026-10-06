import { afterEach, describe, expect, it, vi } from 'vitest'
import { componentScript, deferred, flushWork } from '@/test/componentScript'

const tx = (id: string, amount = 30) => ({ id, type: 'expense', amount, account_id: 'account', category_id: 'food', member_id: 'child-A', paid_by_member_id: 'parent-B', transaction_date: '2026-10-06T10:00:00+08:00', remark: id, images: '["old.png"]' })
const dialogs: ReturnType<typeof componentScript>[] = []
afterEach(() => dialogs.splice(0).forEach(dialog => dialog.unmount()))

function setup(getById: any, update = vi.fn().mockResolvedValue({}), cleanup = vi.fn().mockResolvedValue([])) {
  const toast = { error: vi.fn(), success: vi.fn() }
  const dialog = componentScript('components/TransactionDialog.vue', ['form', 'submit', 'close', 'loadingInitialData', 'loading', 'transactionLoadFailed'], {
    '@/api/transaction': { transactionApi: { getById, update, create: vi.fn() } },
    '@/api/category': { categoryApi: { getList: async () => [{ id: 'food', type: 'expense' }] } },
    '@/api/account': { accountApi: { getList: async () => ({ list: [{ id: 'account' }] }) } },
    '@/api/family': { familyApi: { listMembers: async () => [] } },
    '@/api/tag': { tagApi: { list: async () => [] } },
    '@/composables/useToast': { toast },
    '@/utils/attachmentCleanup': { deleteRemovedAttachments: cleanup },
    '@/composables/useLedgerMutation': { notifyLedgerMutation: vi.fn() },
  }, { visible: false, editId: 'A' })
  dialogs.push(dialog)
  return { ...dialog, update, cleanup, toast }
}

async function open(dialog: ReturnType<typeof setup>, id: string) {
  dialog.props.editId = id
  dialog.props.visible = true
  await flushWork()
}

describe('transaction editor operation identity', () => {
  it('does not save late A details into B after closing and reopening', async () => {
    const a = deferred()
    const dialog = setup((id: string) => id === 'A' ? a.promise : Promise.resolve(tx('B', 200)))
    await open(dialog, 'A')
    dialog.entry.close()
    dialog.props.visible = false
    await flushWork()
    await open(dialog, 'B')
    a.resolve(tx('A'))
    await flushWork()
    await dialog.entry.submit()
    expect(dialog.update).toHaveBeenCalledWith('B', expect.objectContaining({ amount: 200, remark: 'B' }))
  })

  it('keeps owner and payer independent when only a remark changes', async () => {
    const dialog = setup(async () => tx('A'))
    await open(dialog, 'A')
    dialog.entry.form.value.remark = 'only remark edited'
    await dialog.entry.submit()
    expect(dialog.update).toHaveBeenCalledWith('A', expect.objectContaining({ member_id: 'child-A', paid_by_member_id: 'parent-B' }))
  })

  it('ignores a closed editor failure and finally while B details are loading', async () => {
    const a = deferred(), b = deferred()
    const dialog = setup((id: string) => id === 'A' ? a.promise : b.promise)
    await open(dialog, 'A')
    dialog.entry.close()
    dialog.props.visible = false
    await flushWork()
    await open(dialog, 'B')
    a.reject(new Error('old A failure'))
    await flushWork()
    expect(dialog.toast.error).not.toHaveBeenCalled()
    expect(dialog.entry.loadingInitialData.value).toBe(true)
    b.resolve(tx('B', 200))
    await flushWork()
    expect(dialog.entry.transactionLoadFailed.value).toBe(false)
  })

  it('uses the submitted attachment snapshot after a reopen and never closes B', async () => {
    const save = deferred()
    const dialog = setup(async (id: string) => tx(id), vi.fn(() => save.promise))
    await open(dialog, 'A')
    dialog.entry.form.value.images = '["retained.png"]'
    const saving = dialog.entry.submit()
    dialog.props.visible = false
    await flushWork()
    await open(dialog, 'B')
    save.resolve({})
    await saving
    expect(dialog.cleanup).toHaveBeenCalledWith('["old.png"]', '["retained.png"]')
    expect(dialog.emitted.filter(event => event[0] === 'update:visible')).toEqual([])
    expect(dialog.entry.form.value.remark).toBe('B')
  })
})

describe('editor edge cases', () => {
  it('switches the fixed target when editId changes while the dialog stays open', async () => {
    const a = deferred()
    const dialog = setup((id: string) => id === 'A' ? a.promise : Promise.resolve(tx('B', 200)))
    await open(dialog, 'A')
    dialog.props.editId = 'B'
    await flushWork()
    a.resolve(tx('A'))
    await flushWork()
    await dialog.entry.submit()
    expect(dialog.update).toHaveBeenCalledWith('B', expect.objectContaining({ amount: 200 }))
  })

  it('does not turn a payer-only historical transaction into an owned transaction', async () => {
    const dialog = setup(async () => ({ ...tx('A'), member_id: null }))
    await open(dialog, 'A')
    await dialog.entry.submit()
    expect(dialog.update).toHaveBeenCalledWith('A', expect.objectContaining({ member_id: undefined, paid_by_member_id: 'parent-B' }))
  })

  it('ignores details that complete after component destruction', async () => {
    const response = deferred()
    const dialog = setup(() => response.promise)
    await open(dialog, 'A')
    dialog.unmount()
    response.resolve(tx('A'))
    await flushWork()
    expect(dialog.entry.form.value.amount).toBe('')
    expect(dialog.toast.error).not.toHaveBeenCalled()
  })

  it('does not surface an old save failure or cleanup files after opening B', async () => {
    const response = deferred()
    const dialog = setup(async (id: string) => tx(id), vi.fn(() => response.promise))
    await open(dialog, 'A')
    const saving = dialog.entry.submit()
    dialog.props.visible = false
    await flushWork()
    await open(dialog, 'B')
    response.reject(new Error('old save failed'))
    await saving
    expect(dialog.toast.error).not.toHaveBeenCalled()
    expect(dialog.cleanup).not.toHaveBeenCalled()
    expect(dialog.entry.form.value.remark).toBe('B')
  })
})
