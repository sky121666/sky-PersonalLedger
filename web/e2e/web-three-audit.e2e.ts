import { expect, test, type Page } from '@playwright/test'

// Every API request is intercepted; this suite never reads or writes a real ledger.
async function fixtures(page: Page) {
  const loan = {
    id: 'audit-loan', user_id: 1, type: 'lend_out', contact_name: '审计借款人',
    principal: 120, current_balance: 120, total_repaid: 0, is_settled: false,
    lend_date: '2026-10-01T12:30:00+08:00', evidence: '', remark: '',
    created_at: '2026-10-01T12:30:00+08:00', updated_at: '2026-10-01T12:30:00+08:00',
  }
  const updates: Record<string, unknown>[] = []
  const creates: Record<string, unknown>[] = []
  const pageErrors: string[] = []
  page.on('pageerror', error => pageErrors.push(error.message))
  const debt = {
    total_debt: 75, total_paid: 25, total_principal: 100, progress: 25,
    active_loans: 1, paid_off_loans: 0, next_payment_day: 1, next_payment_name: '合成还款提醒', days_until_next: 0,
  }
  const lendingSummary = {
    total_lend_out: 1, total_borrow_in: 0, active_lend_out: 1, active_borrow_in: 0,
    settled_lend_out: 0, settled_borrow_in: 0, total_receivable: 120, total_payable: 0, net_lending: 120,
  }
  const reads: Record<string, unknown> = {
    '/auth/status': { initialized: true },
    '/accounts': {
      list: [{
        id: 'managed-credit', name: '分期账户', type: 'credit', debt_tracking_mode: 'managed',
        current_balance: -9000, initial_balance: -9000, total_paid: 0, is_archived: false,
        icon: 'wallet', color: '#3B82F6', sort_order: 0,
      }],
      total_assets: 0, total_liabilities: 9000, net_assets: -9000,
    },
    '/statistics/overview': {
      income: 0, expense: 0, balance: 0, income_change: 0, expense_change: 0,
      daily_average: 0, transaction_count: 0,
    },
    '/transactions': { list: [], total: 0 },
    '/debt/summary': debt,
    '/debt/capabilities': {
      contract_version: 1, multiple_plans: true, explicit_allocation: true,
      reversal: true, managed_accounts: 'managed', external_cash_interest: true,
    },
    '/debt/plans': [], '/debt/operations': [], '/reminders': [],
    '/budgets/summary': {
      total_amount: 0, total_spent: 0, percentage: 0, daily_available: 0,
      days_remaining: 0, over_budget_categories: [],
    },
    '/lendings': [loan], '/lendings/summary': lendingSummary,
    '/family/summary': { month: '2026-10', total_expense: 0, members: [] },
    '/ai/reports': [],
  }
  await page.route('**/api/v1/**', async route => {
    const request = route.request()
    const path = new URL(request.url()).pathname.replace('/api/v1', '')
    let data: unknown
    if (path === '/auth/refresh') data = { access_token: 'isolated-audit-token', expires_in: 3600 }
    else if (path === '/lendings/audit-loan' && request.method() === 'PATCH') {
      const payload = request.postDataJSON()
      updates.push(payload)
      Object.assign(loan, payload)
      data = loan
    } else if (path === '/lendings' && request.method() === 'POST') {
      const payload = request.postDataJSON()
      creates.push(payload)
      data = { ...loan, ...payload, id: 'new-audit-loan' }
    } else if (request.method() === 'GET' && path in reads) data = reads[path]
    else {
      await route.fulfill({ status: 501, json: { code: 501, message: `Unexpected fixture request: ${request.method()} ${path}` } })
      return
    }
    await route.fulfill({ json: { code: 0, data } })
  })
  return { loan, updates, creates, pageErrors }
}

function editDialog(page: Page) {
  return page.getByRole('heading', { name: '编辑记录', exact: true }).locator('../..')
}

function file(name: string) {
  return { name, mimeType: 'text/plain', buffer: Buffer.from('synthetic audit attachment') }
}

for (const width of [390, 1440]) {
  test.describe(`three audited Web repairs at ${width}px`, () => {
    test.use({ viewport: { width, height: 900 } })

    test('reminder progress excludes managed debt and opens the reminder section', async ({ page }) => {
      const state = await fixtures(page)
      await page.goto('/#/')
      const card = page.getByRole('article', { name: '还款提醒', exact: true })
      await expect(card).toContainText('还款提醒，不含账户分期')
      await expect(card.locator('.widget-progress > span')).toHaveAttribute('style', /width: 25%/)
      await expect(card).toContainText('待还 75.00')
      await expect(card).not.toContainText('9,000.00')
      await card.getByRole('button', { name: '查看详情', exact: true }).click()
      await expect(page).toHaveURL(/\/#\/reminders\?view=reminders$/)
      await expect(page.getByRole('group', { name: '负债管理视图' })
        .getByRole('button', { name: '还款提醒', exact: true })).toHaveAttribute('aria-pressed', 'true')
      expect(state.pageErrors).toEqual([])
    })

    test('historical fields are read-only in edit and editable in create', async ({ page }) => {
      const state = await fixtures(page)
      await page.goto('/#/lendings')
      await page.getByRole('button', { name: '编辑借款 审计借款人' }).click()
      const dialog = editDialog(page)
      await expect(dialog.getByLabel('借贷本金', { exact: true })).not.toBeEditable()
      await expect(dialog.getByLabel('借贷发生日期', { exact: true })).not.toBeEditable()
      await expect(dialog.getByText('本金和发生日期为历史记录，编辑时不可修改')).toBeVisible()
      await dialog.getByPlaceholder('添加备注').fill('只改备注')
      await dialog.getByRole('button', { name: '保存', exact: true }).click()
      await expect(dialog).toHaveCount(0)
      expect(state.updates).toHaveLength(1)
      expect(state.updates[0]).toMatchObject({ remark: '只改备注' })
      expect(state.updates[0]).not.toHaveProperty('principal')
      expect(state.updates[0]).not.toHaveProperty('lend_date')
      await page.getByRole('button', { name: '记一笔借出', exact: true }).click()
      const create = page.getByRole('heading', { name: '记一笔借出', exact: true }).locator('../..')
      await expect(create.getByLabel('借贷本金', { exact: true })).toBeEditable()
      await expect(create.getByLabel('借贷发生日期', { exact: true })).toBeEditable()
      await create.getByPlaceholder('对方姓名').fill('新增借款人')
      await create.getByLabel('借贷本金', { exact: true }).fill('250')
      await create.getByLabel('借贷发生日期', { exact: true }).fill('2026-10-02T14:00')
      await create.getByRole('button', { name: '确认', exact: true }).click()
      await expect(create).toHaveCount(0)
      expect(state.creates[0]).toMatchObject({ principal: 250, lend_date: '2026-10-02T06:00:00.000Z' })
      expect(state.pageErrors).toEqual([])
    })

    test('partial uploads survive failure, reject concurrent drops and retry only the failure', async ({ page }) => {
      const state = await fixtures(page)
      const uploaded: string[] = []
      let releaseFailure!: () => void
      const pendingFailure = new Promise<void>(resolve => { releaseFailure = resolve })
      await page.route('**/api/v1/upload', async route => {
        const name = /filename="([^"]+)"/.exec(route.request().postDataBuffer()!.toString())![1]!
        uploaded.push(name)
        if (name === 'failed.txt' && uploaded.filter(value => value === name).length === 1) {
          await pendingFailure
          await route.fulfill({ status: 503, json: { code: 500, message: 'Synthetic upload failure' } })
        } else {
          await route.fulfill({ json: { code: 0, data: { path: `lendings/audit-loan/${name}`, url: '', filename: name, size: 26 } } })
        }
      })
      await page.goto('/#/lendings')
      await page.getByRole('button', { name: '编辑借款 审计借款人' }).click()
      const dialog = editDialog(page)
      const input = dialog.getByLabel('上传凭证附件')
      await input.setInputFiles([file('first.txt'), file('failed.txt'), file('last.txt')])
      await expect.poll(() => uploaded).toEqual(['first.txt', 'failed.txt'])
      await expect(dialog.getByText('first.txt', { exact: true })).toBeVisible()
      await expect(dialog.getByRole('button', { name: /保存|附件上传中/ })).toBeDisabled()
      await expect(input).toBeDisabled()
      const dropped = await page.evaluateHandle(() => {
        const data = new DataTransfer()
        data.items.add(new File(['duplicate'], 'duplicate.txt', { type: 'text/plain' }))
        return data
      })
      await input.locator('..').dispatchEvent('drop', { dataTransfer: dropped })
      releaseFailure()
      await expect(dialog.getByRole('alert')).toContainText('failed.txt 上传失败')
      await expect(dialog.getByText('last.txt', { exact: true })).toBeVisible()
      expect(uploaded).toEqual(['first.txt', 'failed.txt', 'last.txt'])
      await dialog.getByRole('button', { name: '重试上传 failed.txt' }).click()
      await expect(dialog.getByRole('alert')).toHaveCount(0)
      await expect(dialog.getByText('failed.txt', { exact: true })).toBeVisible()
      expect(uploaded).toEqual(['first.txt', 'failed.txt', 'last.txt', 'failed.txt'])
      await input.setInputFiles([file('fourth.txt'), file('fifth.txt'), file('overflow.txt')])
      await expect(dialog.getByText('fifth.txt', { exact: true })).toBeVisible()
      await expect(input).toHaveCount(0)
      expect(uploaded).toEqual(['first.txt', 'failed.txt', 'last.txt', 'failed.txt', 'fourth.txt', 'fifth.txt'])
      await dialog.getByRole('button', { name: '保存', exact: true }).click()
      await expect(dialog).toHaveCount(0)
      expect(JSON.parse(state.updates[0]!.evidence as string)).toEqual([
        'lendings/audit-loan/first.txt', 'lendings/audit-loan/last.txt', 'lendings/audit-loan/failed.txt',
        'lendings/audit-loan/fourth.txt', 'lendings/audit-loan/fifth.txt',
      ])
      await page.getByRole('button', { name: '编辑借款 审计借款人' }).click()
      for (const name of ['first.txt', 'last.txt', 'failed.txt', 'fourth.txt', 'fifth.txt']) {
        await expect(editDialog(page).getByText(name, { exact: true })).toBeVisible()
      }
      expect(state.pageErrors).toEqual([])
    })
  })
}
