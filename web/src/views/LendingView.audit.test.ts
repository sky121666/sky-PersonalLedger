import { readFileSync } from 'node:fs'
import { compile, createSSRApp, ref } from 'vue'
import { parse } from 'vue/compiler-sfc'
import { renderToString } from 'vue/server-renderer'
import { afterEach, expect, it, vi } from 'vitest'
import { componentScript } from '@/test/componentScript'

const views: ReturnType<typeof componentScript>[] = []
afterEach(() => views.splice(0).forEach(view => view.unmount()))
const loan = {
  id: 'loan', type: 'lend_out', contact_name: 'Alice', principal: 120,
  lend_date: '2026-10-01T12:30:00+08:00', evidence: '', is_settled: false,
  current_balance: 120, total_repaid: 0,
}

function setup() {
  const update = vi.fn(async () => ({}))
  const create = vi.fn(async () => ({}))
  const view = componentScript('views/LendingView.vue', [
    'openCreate', 'openEdit', 'form', 'editingLending', 'submitForm',
  ], {
    '@/api/lending': { lendingApi: { update, create } },
    '@/api/account': {},
    '@/composables/useToast': { toast: { error: vi.fn(), warning: vi.fn(), success: vi.fn() } },
    '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0), notifyLedgerMutation: vi.fn() },
    '@/utils/attachmentCleanup': { deleteRemovedAttachments: async () => [] },
  })
  views.push(view)
  return { ...view, update, create }
}

async function historicalInputs(entry: any) {
  const template = parse(readFileSync('src/views/LendingView.vue', 'utf8')).descriptor.template!
  const inputs = template.ast!.children.flatMap(function walk(node: any): any[] {
    if (node.type === 1 && node.tag === 'input' && node.props.some((p: any) =>
      p.name === 'model' && ['form.principal', 'form.lend_date'].includes(p.exp?.content))) return [node.loc.source]
    return (node.children || []).flatMap(walk)
  })
  const app = createSSRApp({ setup: () => entry, render: compile(`<div>${inputs.join('')}</div>`) })
  app.config.warnHandler = () => {}
  return renderToString(app)
}

it('makes historical principal and occurrence date read-only while editing', async () => {
  const view = setup()
  view.entry.openEdit(loan)
  const html = await historicalInputs(view.entry)
  expect(html.match(/readonly/g)).toHaveLength(2)
  expect(view.entry.form.value.principal).toBe(120)
})

it('keeps principal and occurrence date editable when creating a lending', async () => {
  const view = setup()
  view.entry.openEdit(loan)
  view.entry.openCreate('borrow_in')
  expect(await historicalInputs(view.entry)).not.toContain('readonly')
  view.entry.form.value.contact_name = 'Bob'
  view.entry.form.value.principal = 250
  view.entry.form.value.lend_date = '2026-10-02T14:00'
  await view.entry.submitForm()
  expect(view.create).toHaveBeenCalledWith(expect.objectContaining({ principal: 250, lend_date: '2026-10-02T06:00:00.000Z' }))
})

it('updates supported lending details without resubmitting historical fields', async () => {
  const view = setup()
  view.entry.openEdit(loan)
  view.entry.form.value.remark = 'updated note'
  await view.entry.submitForm()
  expect(view.update).toHaveBeenCalledWith('loan', expect.objectContaining({ remark: 'updated note' }))
  const payload = view.update.mock.calls[0] as unknown as [string, Record<string, unknown>]
  expect(payload[1]).not.toHaveProperty('principal')
  expect(payload[1]).not.toHaveProperty('lend_date')
})
