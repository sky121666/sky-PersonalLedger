import { expect, test, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
test.beforeAll(async ({ request }) => {
  const status = await request.get('/api/v1/auth/status')
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})
async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁' }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

test('account-log outage stays unknown and retry can produce an honest empty state', async ({ page }) => {
  await login(page)
  let unavailable = true
  await page.route(/\/api\/v1\/account-logs(?:\?|$)/, route => route.fulfill({
    status: unavailable ? 503 : 200,
    json: unavailable ? { code: 500, message: 'fixture outage' } : { code: 0, data: { list: [], total: 0, page: 1, page_size: 50 } },
  }))
  await page.goto('/#/account-logs')
  await expect(page.getByRole('alert')).toContainText('流水加载失败')
  await expect(page.getByText('暂无流水记录', { exact: true })).toHaveCount(0)
  await expect(page.getByText('流水总数待加载')).toBeVisible()
  unavailable = false
  await page.getByRole('button', { name: '重新加载流水' }).click()
  await expect(page.getByText('暂无流水记录', { exact: true })).toBeVisible()
  await expect(page.getByRole('alert')).toHaveCount(0)
})

test('calendar exposes the full daily count and its next page', async ({ page }) => {
  await login(page)
  await page.route(/\/api\/v1\/transactions(?:\?|$)/, route => {
    const query = new URL(route.request().url()).searchParams
    const date = query.get('start_date')
    const second = query.get('page') === '2'
    const list = date ? Array.from({ length: second ? 1 : 100 }, (_, i) => ({
      id: `${second ? 2 : 1}-${i}`, type: !second && i < 3 ? ['income', 'expense', 'transfer'][i] : 'expense', amount: 1,
      account_id: 'fixture', category_id: 'food', transaction_date: `${date}T12:00:00+08:00`,
      remark: second ? '第101笔合成交易' : i < 3 ? '同备注交易' : `合成交易${i + 1}`, source: 'manual',
      account: { id: 'fixture', name: '合成账户', type: 'cash' }, category: { name: '餐饮' },
    })) : []
    return route.fulfill({ json: { code: 0, data: { list, total: date ? 101 : 0, page: second ? 2 : 1, page_size: 100 } } })
  })
  await page.reload()
  await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
  await page.getByRole('button', { name: '添加小组件', exact: true }).click()
  const gallery = page.getByRole('dialog', { name: '组件画廊' })
  await gallery.getByRole('button', { name: '预览收支日历', exact: true }).click()
  await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
  await page.keyboard.press('Escape')
  await page.getByRole('button', { name: '完成编辑', exact: true }).click()
  const calendar = page.getByRole('article', { name: '收支日历', exact: true })
  await calendar.getByText('20', { exact: true }).click()
  await expect(page.getByRole('region', { name: '所选日期交易' }).getByRole('heading').filter({ hasText: '101 笔' })).toBeVisible()
  const rows = page.getByRole('region', { name: '所选日期交易' })
  await expect(rows.getByRole('button', { name: '收入 同备注交易', exact: true })).toContainText('+1.00')
  await expect(rows.getByRole('button', { name: '支出 同备注交易', exact: true })).toContainText('-1.00')
  await expect(rows.getByRole('button', { name: '转账 同备注交易', exact: true }).locator('.amount-neutral')).toHaveText('1.00')
  await expect(page.getByRole('region', { name: '所选日期交易' }).getByRole('button')).toHaveCount(101)
  await page.getByRole('button', { name: '隐藏首页金额', exact: true }).click()
  await expect(rows.getByRole('button', { name: '收入 同备注交易', exact: true })).toContainText('****')
  await expect(rows).not.toContainText('+1.00')
  await page.getByRole('button', { name: '加载更多日期交易' }).click()
  await expect(page.getByText('第101笔合成交易')).toBeVisible()
  await expect(page.getByRole('region', { name: '所选日期交易' }).getByRole('heading').filter({ hasText: '101 笔' })).toBeVisible()
  await expect(page.getByRole('button', { name: '加载更多日期交易' })).toHaveCount(0)
  await expect(page.getByRole('region', { name: '所选日期交易' }).getByRole('button')).toHaveCount(101)
})

test('failed historical year does not relabel the last successful report', async ({ page }) => {
  await login(page)
  await page.route('**/api/v1/export/years', route => route.fulfill({ json: { code: 0, data: { years: [2026, 2025] } } }))
  await page.route(/\/api\/v1\/export\/report\/yearly\?year=2025$/, route => route.fulfill({ status: 503, json: { code: 500, message: 'fixture outage' } }))
  await page.goto('/#/report')
  await expect(page.getByText('年度财务总结', { exact: true })).toBeVisible()
  await expect(page.getByText('1月月', { exact: true })).toHaveCount(0)
  await page.getByRole('combobox').selectOption('2025')
  await expect(page.getByRole('alert').filter({ hasText: '2025 年报告加载失败' })).toBeVisible()
  await expect(page.getByText('年度财务总结', { exact: true })).toHaveCount(0)
  await expect(page.getByRole('button', { name: '重新加载报告' })).toBeVisible()
})

test('real repayment retries are idempotent and referenced account deletion is rejected', async ({ request }) => {
  const loginResponse = await request.post('/api/v1/auth/login', { data: { password } })
  const headers = { Authorization: `Bearer ${(await loginResponse.json()).data.access_token}` }
  const accountResponse = await request.post('/api/v1/accounts', { headers, data: { name: 'E2E还款合成账户', type: 'cash', initial_balance: 500 } })
  expect(accountResponse.ok()).toBeTruthy()
  const accountID = (await accountResponse.json()).data.id
  const reminderResponse = await request.post('/api/v1/reminders', { headers, data: { name: 'E2E合成债务', loan_type: 'other', payment_day: 15, principal: 100, current_balance: 100 } })
  expect(reminderResponse.ok()).toBeTruthy()
  const reminderID = (await reminderResponse.json()).data.id
  const edit = await request.patch(`/api/v1/reminders/${reminderID}`, { headers, data: { name: 'E2E合成债务已修改' } })
  expect(edit.ok()).toBeTruthy()
  const data = { amount: 110, principal_amount: 100, interest_amount: 10, account_id: accountID, idempotency_key: `e2e-${reminderID}` }
  const responses = await Promise.all([1, 2].map(() => request.post(`/api/v1/reminders/${reminderID}/payment`, { headers, data })))
  for (const response of responses) expect(response.ok()).toBeTruthy()
  const account = await request.get(`/api/v1/accounts/${accountID}`, { headers })
  expect((await account.json()).data.current_balance).toBe(390)
  const debt = await request.get(`/api/v1/reminders/${reminderID}`, { headers })
  expect((await debt.json()).data.current_balance).toBe(0)
  const conflict = await request.post(`/api/v1/reminders/${reminderID}/payment`, { headers, data: { ...data, amount: 111, interest_amount: 11 } })
  expect(conflict.status()).toBe(409)
  await request.patch(`/api/v1/accounts/${accountID}/archive`, { headers, data: { is_archived: true } })
  const deletion = await request.delete(`/api/v1/accounts/${accountID}`, { headers })
  expect(deletion.status()).toBe(409)
  expect((await request.get(`/api/v1/accounts/${accountID}`, { headers })).ok()).toBeTruthy()
})

test('committed repayment with a lost response survives reload without a second debit', async ({ page, request }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  const loginResponse = await request.post('/api/v1/auth/login', { data: { password } })
  const headers = { Authorization: `Bearer ${(await loginResponse.json()).data.access_token}` }
  const accountResponse = await request.post('/api/v1/accounts', { headers, data: { name: 'E2E响应丢失账户', type: 'cash', initial_balance: 500 } })
  expect(accountResponse.ok()).toBeTruthy()
  const accountID = (await accountResponse.json()).data.id
  const name = 'E2E响应丢失分期'
  const reminderResponse = await request.post('/api/v1/reminders', { headers, data: { name, loan_type: 'other', payment_day: 15, principal: 100, current_balance: 100 } })
  expect(reminderResponse.ok()).toBeTruthy()
  const reminderID = (await reminderResponse.json()).data.id
  const repaymentKeys: string[] = []
  let loseFirstResponse = true
  await page.route(`**/api/v1/reminders/${reminderID}/payment`, async route => {
    repaymentKeys.push(route.request().postDataJSON().idempotency_key)
    const response = await route.fetch()
    expect(response.ok()).toBeTruthy()
    if (loseFirstResponse) {
      loseFirstResponse = false
      await route.abort('connectionreset')
    } else {
      await route.fulfill({ response })
    }
  })
  await login(page)
  await page.goto('/#/reminders?view=reminders')
  const loanCard = page.locator('.group').filter({ hasText: name }).first()
  await loanCard.getByRole('button', { name: '+ 记录还款', exact: true }).click()
  const dialog = page.getByRole('dialog', { name: '记录还款', exact: true })
  await dialog.getByRole('spinbutton').nth(0).fill('110')
  await dialog.getByRole('spinbutton').nth(1).fill('100')
  await dialog.getByRole('spinbutton').nth(2).fill('10')
  await dialog.getByRole('combobox').selectOption(accountID)
  await dialog.getByRole('button', { name: '确认还款', exact: true }).click()
  await expect(dialog.getByRole('alert')).toContainText('上次还款结果尚未确认')
  await expect(dialog.getByRole('spinbutton').nth(0)).toBeDisabled()
  await page.reload()
  // The debt is now paid off: recovery must remain reachable outside the active list.
  await page.getByRole('button', { name: '确认上次还款结果', exact: true }).click()
  await expect(dialog.getByRole('spinbutton').nth(0)).toHaveValue('110')
  await expect(dialog.getByRole('spinbutton').nth(0)).toBeDisabled()
  await page.screenshot({ path: test.info().outputPath('repayment-recovery-390.png'), fullPage: true })
  await dialog.getByRole('button', { name: '确认上次还款结果', exact: true }).click()
  await expect(page.getByText('还款记录成功，已同步到明细', { exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: '确认上次还款结果', exact: true })).toHaveCount(0)
  expect(repaymentKeys).toHaveLength(2)
  expect(repaymentKeys[0]).toBeTruthy()
  expect(repaymentKeys[1]).toBe(repaymentKeys[0])
  const account = await request.get(`/api/v1/accounts/${accountID}`, { headers })
  expect((await account.json()).data.current_balance).toBe(390)
  const debt = await request.get(`/api/v1/reminders/${reminderID}`, { headers })
  expect((await debt.json()).data.total_paid).toBe(110)
})
