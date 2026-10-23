import { expect, test, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
test.beforeAll(async ({ request }) => {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED).toBe('1')
  const status = await request.get('/api/v1/auth/status')
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

async function unlock(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁' }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

async function fillTransaction(page: Page, accountId: string, amount = '10') {
  await page.getByRole('button', { name: '记一笔' }).click()
  const dialog = page.getByRole('dialog', { name: '新增交易' })
  await expect(dialog.locator('#transaction-amount')).toBeEnabled()
  await dialog.locator('#transaction-amount').fill(amount)
  await dialog.getByRole('button', { name: /^选择.+分类$/ }).first().click()
  await dialog.locator('select').filter({ has: page.locator(`option[value="${accountId}"]`) }).selectOption(accountId)
  return dialog
}

for (const width of [1440, 390]) {
  test(`ordinary creation survives lost response and reload at ${width}px`, async ({ page, request }) => {
    await page.setViewportSize({ width, height: 900 })
    const login = await request.post('/api/v1/auth/login', { data: { password } })
    const headers = { Authorization: `Bearer ${(await login.json()).data.access_token}` }
    const createdAccount = await request.post('/api/v1/accounts', { headers, data: {
      name: `重试隔离账户 ${width}`, type: 'cash', initial_balance: 100,
    } })
    expect(createdAccount.ok()).toBeTruthy()
    const accountId = (await createdAccount.json()).data.id
    const keys: string[] = []
    let loseResponse = true
    await page.route(/\/api\/v1\/transactions$/, async route => {
      if (route.request().method() !== 'POST') return route.continue()
      keys.push(route.request().postDataJSON().idempotency_key)
      const response = await route.fetch()
      expect(response.ok()).toBeTruthy()
      if (loseResponse) {
        loseResponse = false
        await route.abort('connectionreset')
      } else {
        await route.fulfill({ response })
      }
    })
    await page.goto('/#/login')
    await page.getByLabel('密码', { exact: true }).fill(password)
    await page.getByRole('button', { name: '解锁' }).click()
    await expect(page).toHaveURL(/\/#\/$/)
    await page.getByRole('button', { name: '记一笔' }).click()
    const dialog = page.getByRole('dialog', { name: '新增交易' })
    await expect(dialog.locator('#transaction-amount')).toBeEnabled()
    await dialog.locator('#transaction-amount').fill('10')
    await dialog.getByRole('button', { name: /^选择.+分类$/ }).first().click()
    await dialog.locator('select').filter({ has: page.locator(`option[value="${accountId}"]`) }).selectOption(accountId)
    await dialog.getByRole('button', { name: '保存记录', exact: true }).click()
    await expect(dialog.getByRole('status')).toContainText('上次记账结果尚未确认')
    await expect(dialog.locator('#transaction-amount')).toBeDisabled()
    await page.reload()
    await page.getByRole('button', { name: '记一笔' }).click()
    await expect(dialog.locator('#transaction-amount')).toHaveValue('10')
    await expect(dialog.locator('#transaction-amount')).toBeDisabled()
    await page.screenshot({ path: test.info().outputPath(`transaction-recovery-${width}.png`), fullPage: true })
    await dialog.getByRole('button', { name: '确认上次记账结果', exact: true }).click()
    await expect(dialog).toHaveCount(0)
    expect(keys).toHaveLength(2)
    expect(keys[0]).toBeTruthy()
    expect(keys[1]).toBe(keys[0])
    const account = await request.get(`/api/v1/accounts/${accountId}`, { headers })
    expect((await account.json()).data.current_balance).toBe(90)
    const transactions = await request.get(`/api/v1/transactions?account_id=${accountId}`, { headers })
    expect((await transactions.json()).data.total).toBe(1)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  })

  test(`pending creation blocks dismissal and duplicate writes at ${width}px`, async ({ page, request }) => {
    await page.setViewportSize({ width, height: 900 })
    const login = await request.post('/api/v1/auth/login', { data: { password } })
    const headers = { Authorization: `Bearer ${(await login.json()).data.access_token}` }
    const account = await request.post('/api/v1/accounts', { headers, data: {
      name: `延迟响应隔离账户 ${width}`, type: 'cash', initial_balance: 100,
    } })
    const accountId = (await account.json()).data.id
    const keys: string[] = []
    let release!: () => void
    const delayed = new Promise<void>(resolve => { release = resolve })
    await page.route(/\/api\/v1\/transactions$/, async route => {
      if (route.request().method() !== 'POST') return route.continue()
      keys.push(route.request().postDataJSON().idempotency_key)
      const response = await route.fetch()
      expect(response.ok()).toBeTruthy()
      if (keys.length === 1) await delayed
      await route.fulfill({ response })
    })
    await unlock(page)
    const dialog = await fillTransaction(page, accountId)
    await dialog.getByRole('button', { name: '保存记录', exact: true }).click()
    await expect.poll(() => keys.length).toBe(1)
    await expect(dialog.getByRole('button', { name: '关闭交易表单' })).toBeDisabled()
    await page.keyboard.press('Escape')
    await expect(dialog).toBeVisible()
    await expect(dialog.getByRole('button', { name: '保存中...', exact: true })).toBeDisabled()
    release()
    await expect(dialog).toHaveCount(0)
    await expect.poll(() => page.evaluate(() => Object.keys(sessionStorage)
      .some(key => key.startsWith('personal-ledger:transaction-write:')))).toBe(false)
    expect(keys).toHaveLength(1)
    // The late-success/reopened-key race remains covered by transactionCreation.test.ts.
    expect((await (await request.get(`/api/v1/accounts/${accountId}`, { headers })).json()).data.current_balance).toBe(90)
  })

  test(`deleted creation can end confirmation without recreating it at ${width}px`, async ({ page, request }) => {
    await page.setViewportSize({ width, height: 900 })
    const login = await request.post('/api/v1/auth/login', { data: { password } })
    const headers = { Authorization: `Bearer ${(await login.json()).data.access_token}` }
    const account = await request.post('/api/v1/accounts', { headers, data: {
      name: `已删除确认隔离账户 ${width}`, type: 'cash', initial_balance: 100,
    } })
    const accountId = (await account.json()).data.id
    let calls = 0
    const keys: string[] = []
    await page.route(/\/api\/v1\/transactions$/, async route => {
      if (route.request().method() !== 'POST') return route.continue()
      calls++
      keys.push(route.request().postDataJSON().idempotency_key)
      const response = await route.fetch()
      if (calls === 1) {
        const transactionId = (await response.json()).data.id
        expect((await request.delete(`/api/v1/transactions/${transactionId}`, { headers })).ok()).toBeTruthy()
        await route.abort('connectionreset')
      } else {
        await route.fulfill({ response })
      }
    })
    await unlock(page)
    const dialog = await fillTransaction(page, accountId)
    await dialog.getByRole('button', { name: '保存记录', exact: true }).click()
    await expect(dialog.getByRole('status')).toBeVisible()
    await dialog.getByRole('button', { name: '确认上次记账结果' }).click()
    await expect(dialog.getByRole('alert')).toContainText('结束确认不会新增或撤销交易')
    expect((await (await request.get(`/api/v1/accounts/${accountId}`, { headers })).json()).data.current_balance).toBe(100)
    await dialog.getByRole('button', { name: '核对后结束确认' }).click()
    await expect(dialog.locator('#transaction-amount')).toBeEnabled()
    await expect(dialog.locator('#transaction-amount')).toHaveValue('')
    await dialog.locator('#transaction-amount').fill('20')
    await dialog.getByRole('button', { name: /^选择.+分类$/ }).first().click()
    await dialog.locator('select').filter({ has: page.locator(`option[value="${accountId}"]`) }).selectOption(accountId)
    await dialog.getByRole('button', { name: '保存记录', exact: true }).click()
    await expect(dialog).toHaveCount(0)
    expect(keys).toHaveLength(3)
    expect(keys[1]).toBe(keys[0])
    expect(keys[2]).not.toBe(keys[0])
    expect((await (await request.get(`/api/v1/accounts/${accountId}`, { headers })).json()).data.current_balance).toBe(80)
    expect((await (await request.get(`/api/v1/transactions?account_id=${accountId}`, { headers })).json()).data.total).toBe(1)
  })
}

for (const width of [390, 1440]) {
  test(`unconfirmed creation opens details without discarding journal at ${width}`, async ({ page, request }) => {
    await page.setViewportSize({ width, height: 844 })
    const login = await request.post('/api/v1/auth/login', { data: { password } })
    const headers = { Authorization: `Bearer ${(await login.json()).data.access_token}` }
    const created = await request.post('/api/v1/accounts', { headers, data: { name: `确认跳转${width}`, type: 'cash', initial_balance: 100 } })
    const accountId = (await created.json()).data.id
    await page.route(/\/api\/v1\/transactions$/, route => route.request().method() === 'POST'
      ? route.fulfill({ status: 409, json: { code: 40913, message: '隔离确认冲突' } }) : route.continue())
    await unlock(page)
    const dialog = await fillTransaction(page, accountId)
    await dialog.getByRole('button', { name: '保存记录', exact: true }).click()
    await expect(dialog.getByRole('link', { name: '查看明细', exact: true })).toBeVisible()
    const journal = () => page.evaluate(() => Object.fromEntries(Object.entries(sessionStorage).filter(([key]) => key.startsWith('personal-ledger:transaction-write:'))))
    const before = await journal()
    expect(Object.keys(before)).toHaveLength(1)
    await dialog.getByRole('link', { name: '查看明细', exact: true }).click()
    await expect(page).toHaveURL(/#\/transactions$/)
    await expect(dialog).toHaveCount(0)
    expect(await page.locator('#app').evaluate(el => (el as HTMLElement).inert)).toBe(false)
    expect(await journal()).toEqual(before)
    await page.getByRole('button', { name: '记一笔', exact: true }).click()
    await expect(dialog.getByRole('status')).toContainText('上次记账结果尚未确认')
    await expect(dialog.locator('#transaction-amount')).toHaveValue('10')
  })
}
