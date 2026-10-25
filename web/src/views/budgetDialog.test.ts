import { ref } from 'vue'
import { afterEach, expect, it, vi } from 'vitest'
import { componentScript, deferred } from '@/test/componentScript'

const views: ReturnType<typeof componentScript>[] = []
afterEach(() => views.splice(0).forEach(view => view.unmount()))

function budget() {
  const setTotal = vi.fn()
  const toast = { success: vi.fn(), warning: vi.fn(), error: vi.fn() }
  const view = componentScript('views/BudgetView.vue', [
    'form', 'showDialog', 'saving', 'openTotalForm', 'closeDialog', 'submitForm',
  ], {
    '@/api/budget': { budgetApi: { setTotal, getList: async () => ({ total_budget: null }) } },
    '@/api/category': { categoryApi: { getList: async () => [] } },
    '@/api/family': { familyApi: { listMembers: async () => [] } },
    '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0) },
    '@/composables/useToast': { toast },
  })
  views.push(view)
  return { ...view.entry, setTotal, toast }
}

it('keeps the entered amount and releases the saving lock after a failed save', async () => {
  const e = budget()
  e.openTotalForm()
  e.form.value.amount = '650.25'
  e.setTotal.mockRejectedValue(Error('isolated failure'))
  await e.submitForm()
  expect(e.showDialog.value).toBe(true)
  expect(e.form.value.amount).toBe('650.25')
  expect(e.saving.value).toBe(false)
  expect(e.toast.error).toHaveBeenCalledWith('isolated failure')
})

it('does not send a second save while the first is pending', async () => {
  const e = budget()
  const pending = deferred()
  e.setTotal.mockReturnValue(pending.promise)
  e.openTotalForm()
  e.form.value.amount = '650'
  const first = e.submitForm()
  await e.submitForm()
  expect(e.setTotal).toHaveBeenCalledTimes(1)
  pending.resolve({})
  await first
  expect(e.showDialog.value).toBe(false)
})

it('does not close a new draft or announce success when an earlier save finishes', async () => {
  const e = budget()
  const pending = deferred()
  e.setTotal.mockReturnValue(pending.promise)
  e.openTotalForm()
  e.form.value.amount = '650'
  const first = e.submitForm()
  e.closeDialog()
  e.openTotalForm()
  e.form.value.amount = '900'
  pending.resolve({})
  await first
  expect(e.showDialog.value).toBe(true)
  expect(e.form.value.amount).toBe('900')
  expect(e.toast.success).not.toHaveBeenCalled()
})
