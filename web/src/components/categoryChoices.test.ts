import { afterEach, describe, expect, it, vi } from 'vitest'
import { componentScript } from '@/test/componentScript'

const views: ReturnType<typeof componentScript>[] = []
afterEach(() => views.splice(0).forEach(view => view.unmount()))

function picker() {
  const view = componentScript('components/TransactionDialog.vue', ['categories', 'form', 'filteredCategories'], {
    '@/api/auth': { authApi: {} },
    '@/api/transaction': { transactionApi: {} },
    '@/api/category': { categoryApi: {} },
    '@/api/account': { accountApi: {} },
    '@/api/family': { familyApi: {} },
    '@/api/tag': { tagApi: {} },
    '@/utils/attachmentCleanup': { deleteRemovedAttachments: vi.fn() },
    '@/composables/useToast': { toast: { error: vi.fn() } },
    '@/composables/useLedgerMutation': { notifyLedgerMutation: vi.fn() },
  }, { visible: false })
  views.push(view)
  return view.entry
}

describe('transaction category choices preserve identity', () => {
  it('shows one primary choice per identical name without discarding source categories', () => {
    const e = picker()
    e.categories.value = [
      { id: 'food', type: 'expense', name: '餐饮' },
      ...Array.from({ length: 23 }, (_, i) => ({ id: `interest-${i}`, type: 'expense', name: '利息' })),
      { id: 'travel', type: 'expense', name: '交通' },
      { id: 'income', type: 'income', name: '利息' },
    ]
    expect(e.filteredCategories.value.map((c: { id: string }) => c.id)).toEqual(['food', 'interest-0', 'travel'])
    expect(e.categories.value).toHaveLength(26)
    e.form.value.type = 'income'
    expect(e.filteredCategories.value.map((c: { id: string }) => c.id)).toEqual(['income'])
  })

  it('retains the selected historical category rather than silently rebinding it', () => {
    const e = picker()
    e.categories.value = [
      { id: 'old-a', type: 'expense', name: '利息' },
      { id: 'old-b', type: 'expense', name: '利息' },
    ]
    e.form.value.category_id = 'old-b'
    expect(e.filteredCategories.value.map((c: { id: string }) => c.id)).toEqual(['old-b'])
    expect(e.form.value.category_id).toBe('old-b')
    e.form.value.type = 'transfer'
    expect(e.filteredCategories.value).toEqual([])
  })
})
