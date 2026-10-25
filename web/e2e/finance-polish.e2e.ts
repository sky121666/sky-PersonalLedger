import { expect, test, type APIRequestContext, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
const month = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' }).slice(0, 7)
const prefix = `界面适配-${Date.now()}`
let memberId = ''
let cashId = ''
let expenseId = ''
type Call = (path: string, method?: string, data?: unknown) => Promise<any>

async function api(request: APIRequestContext): Promise<Call> {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED, 'financial UI writes require the temporary isolated runner').toBe('1')
  const login = await request.post('/api/v1/auth/login', { data: { password } })
  expect(login.ok()).toBeTruthy()
  const headers = { Authorization: `Bearer ${(await login.json()).data.access_token}` }
  return async (path, method = 'GET', data) => {
    const response = await request.fetch(`/api/v1${path}`, { method, data, headers })
    expect(response.ok(), `${method} ${path}: ${response.status()}`).toBeTruthy()
    return (await response.json()).data
  }
}

test.beforeAll(async ({ request }) => {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED).toBe('1')
  const status = await request.get('/api/v1/auth/status')
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
  const call = await api(request)
  cashId = (await call('/accounts', 'POST', { name: `${prefix}日常银行卡`, type: 'bank_card', initial_balance: 5000 })).id
  memberId = (await call('/family/members', 'POST', { name: `${prefix}成员`, relationship: '模拟家人', color: '#159b67' })).id
  expenseId = (await call('/categories', 'POST', { name: `${prefix}医疗`, type: 'expense', icon: 'cross', color: '#007AFF' })).id
  const income = await call('/categories', 'POST', { name: `${prefix}工资`, type: 'income', icon: 'wallet', color: '#159b67' })
  for (const row of [
    { type: 'income', amount: 15860, category_id: income.id, day: '10', remark: '工资' },
    { type: 'expense', amount: 87, category_id: expenseId, day: '21', remark: '药品' },
    { type: 'expense', amount: 268, category_id: expenseId, day: '21', remark: '采购', member_id: memberId },
  ]) {
    await call('/transactions', 'POST', { ...row, account_id: cashId, remark: `${prefix}${row.remark}`, transaction_date: `${month}-${row.day}T12:00:00+08:00`, idempotency_key: crypto.randomUUID() })
  }
})

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

async function fits(page: Page) {
  await expect(page.locator('.finance-page')).not.toHaveClass(/fade-(enter|leave)-/)
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width)
  expect(await page.locator('main').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  await expect(page.locator('h1:visible')).toHaveCount(1)
}

for (const width of [390, 1440]) {
  test.describe(`${width}px approved finance UI`, () => {
    test.use({ viewport: { width, height: 844 } })
    test.beforeEach(async ({ page }) => {
      await page.emulateMedia({ reducedMotion: 'reduce', colorScheme: 'light' })
      await login(page)
    })

    test('filters through a draft and keeps edit, delete cancellation and receipt protections reachable', async ({ page }) => {
      const queryUrls: string[] = []
      page.on('request', request => { if (new URL(request.url()).pathname === '/api/v1/transactions' && request.method() === 'GET') queryUrls.push(request.url()) })
      await page.goto('/#/transactions')
      await page.getByRole('searchbox', { name: '搜索', exact: true }).fill(`${prefix}药品`)
      await expect.poll(() => queryUrls.some(url => new URL(url).searchParams.get('keyword') === `${prefix}药品`)).toBe(true)
      await expect(page.locator('.transaction-row')).toHaveCount(1)
      await expect(page.locator('.transaction-day-sum')).toContainText('87.00')
      await page.getByRole('button', { name: '全部类型', exact: true }).click()
      const filter = page.getByRole('dialog', { name: '筛选明细', exact: true })
      await filter.getByRole('button', { name: '转账', exact: true }).click()
      const queryCount = queryUrls.length
      await page.keyboard.press('Escape')
      await expect(filter).toHaveCount(0)
      expect(queryUrls).toHaveLength(queryCount)
      await expect(page.getByRole('button', { name: '全部类型', exact: true })).toBeFocused()
      await page.getByRole('button', { name: '全部类型', exact: true }).click()
      await filter.getByLabel('开始日期').fill(`${month}-22`)
      await filter.getByLabel('结束日期').fill(`${month}-01`)
      await filter.getByRole('button', { name: '应用筛选', exact: true }).click()
      await expect(filter.getByRole('alert')).toContainText('开始日期不能晚于结束日期')
      expect(queryUrls).toHaveLength(queryCount)
      await filter.getByRole('button', { name: '重置', exact: true }).click()
      await filter.getByRole('button', { name: '支出', exact: true }).click()
      await filter.getByRole('button', { name: '应用筛选', exact: true }).click()
      await expect(filter).toHaveCount(0)
      await expect.poll(() => queryUrls.some(url => new URL(url).searchParams.get('type') === 'expense')).toBe(true)
      const trigger = page.getByRole('button', { name: `交易操作 ${prefix}药品`, exact: true })
      await trigger.click()
      const menu = page.getByRole('menu', { name: `交易操作 ${prefix}药品`, exact: true })
      await expect(menu.getByRole('menuitem', { name: '编辑', exact: true })).toBeFocused()
      await page.keyboard.press('ArrowDown')
      await expect(menu.getByRole('menuitem', { name: '删除…', exact: true })).toBeFocused()
      await page.keyboard.press('Escape')
      await expect(trigger).toBeFocused()
      await trigger.click()
      await menu.getByRole('menuitem', { name: '删除…', exact: true }).click()
      await expect(page.getByRole('dialog', { name: '确认删除', exact: true })).toBeVisible()
      await page.keyboard.press('Escape')
      await expect(page.getByText(`${prefix}药品`, { exact: true })).toBeVisible()
      await trigger.click()
      await menu.getByRole('menuitem', { name: '编辑', exact: true }).click()
      await expect(page.getByRole('dialog', { name: '编辑交易', exact: true })).toBeVisible()
      await page.getByRole('button', { name: '关闭交易表单', exact: true }).click()
      await page.getByRole('searchbox', { name: '搜索', exact: true }).fill(prefix)
      await expect(page.locator('.transaction-row').filter({ hasText: `${prefix}采购` })).toBeVisible()
      await trigger.click()
      const secondTrigger = page.getByRole('button', { name: `交易操作 ${prefix}采购`, exact: true })
      await secondTrigger.click()
      await expect(page.getByRole('menu')).toHaveCount(1)
      await expect(page.getByRole('menu', { name: `交易操作 ${prefix}采购`, exact: true })).toBeVisible()
      await page.keyboard.press('Escape')
      await fits(page)
      await page.screenshot({ path: test.info().outputPath(`transactions-${width}.png`), animations: 'disabled' })
    })

    test('reads real monthly categories and preserves signed zero baselines in the annual view', async ({ page, request }) => {
      const call = await api(request)
      const expectedExpense = (await call(`/statistics/trend?month=${month}`)).items.find((item: any) => item.date === `${month}-21`).expense
      const errors: string[] = []
      page.on('pageerror', error => errors.push(error.message))
      await page.goto('/#/statistics')
      await expect(page.locator('.statistics-trend-day')).not.toHaveCount(0)
      const income = page.locator('.statistics-summary strong.income')
      await expect(income).not.toContainText('—')
      const zero = page.locator('.statistics-trend-day').first()
      await expect(zero.locator('.statistics-bar')).toHaveCount(0)
      await page.locator(`[data-trend-day="${month}-21"]`).click()
      await expect(page.getByRole('tooltip')).toContainText(expectedExpense.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }))
      await page.keyboard.press('Home')
      await expect(zero).toBeFocused()
      await expect(page.getByRole('tooltip')).toContainText('0.00')
      await page.getByRole('button', { name: '收入', exact: true }).click()
      await expect(page.getByText(`${prefix}工资`, { exact: true })).toBeVisible()
      await fits(page)
      await page.screenshot({ path: test.info().outputPath(`statistics-${width}.png`), animations: 'disabled' })
      await page.route('**/api/v1/statistics/asset-trend*', route => route.fulfill({ json: { code: 0, data: {
        items: [
          { month: `${month.slice(0,4)}-01`, net_worth: -3200 },
          { month: `${month.slice(0,4)}-02`, net_worth: 0 },
          { month: `${month.slice(0,4)}-03`, net_worth: 2400 },
        ], current_net_worth: -3200, current_assets: 100, current_debts: 3300,
      } } }))
      await page.getByRole('button', { name: '年度', exact: true }).click()
      await expect(page.getByRole('heading', { name: '年度报告', exact: true })).toBeVisible()
      const negative = page.locator('.report-signed-bar.is-negative')
      await expect(negative).toBeVisible()
      expect(await negative.evaluate(el => {
        const bar = el.getBoundingClientRect(), slot = el.parentElement!.getBoundingClientRect()
        return Math.abs(bar.top - (slot.top + slot.height / 2)) < 1
      })).toBe(true)
      await expect(page.locator(`[data-asset-month="${month.slice(0,4)}-02"] i`)).toHaveCount(0)
      await page.locator('.report-signed-slot').last().click()
      await expect(page.locator('.report-asset-value')).toContainText('2,400.00')
      await fits(page)
      expect(errors).toEqual([])
      await page.screenshot({ path: test.info().outputPath(`annual-${width}.png`), animations: 'disabled' })
    })

    test('keeps member history, cancels drafts, and preserves open input when system appearance changes', async ({ page, request }) => {
      const call = await api(request)
      await page.goto('/#/appearance')
      await page.getByRole('button', { name: '跟随系统', exact: true }).click()
      await page.emulateMedia({ colorScheme: 'dark', reducedMotion: 'reduce' })
      await expect(page.locator('html')).toHaveClass(/dark/)
      await page.reload()
      await expect(page.getByRole('button', { name: '跟随系统', exact: true })).toHaveAttribute('aria-pressed', 'true')
      await page.goto('/#/family')
      await expect(page.getByText('未归属', { exact: true }).first()).toBeVisible()
      await page.getByRole('button', { name: '管理成员', exact: true }).click()
      const manage = page.getByRole('dialog', { name: '管理成员', exact: true })
      await manage.getByRole('button', { name: `编辑成员 ${prefix}成员`, exact: true }).click()
      const edit = page.getByRole('dialog', { name: '编辑成员', exact: true })
      await expect(edit.getByLabel('成员名称', { exact: true })).toBeFocused()
      await page.keyboard.press('Escape')
      await expect(edit).toHaveCount(0)
      await page.getByRole('button', { name: '管理成员', exact: true }).click()
      await manage.getByRole('button', { name: `编辑成员 ${prefix}成员`, exact: true }).click()
      await edit.getByLabel('成员名称', { exact: true }).fill('ABCDEFGHIJKLMNOPQRSTUVWXYZabcd')
      await page.emulateMedia({ colorScheme: 'light', reducedMotion: 'reduce' })
      await expect(page.locator('html')).not.toHaveClass(/dark/)
      await expect(edit.getByLabel('成员名称', { exact: true })).toHaveValue('ABCDEFGHIJKLMNOPQRSTUVWXYZabcd')
      await expect(edit.getByLabel('成员名称', { exact: true })).toBeFocused()
      await page.keyboard.press('Escape')
      await expect(page.getByRole('button', { name: '管理成员', exact: true })).toBeFocused()
      expect((await call('/family/members')).find((member: any) => member.id === memberId).name).toBe(`${prefix}成员`)
      await page.getByRole('button', { name: '管理成员', exact: true }).click()
      await manage.getByRole('button', { name: '新增成员', exact: true }).click()
      const add = page.getByRole('dialog', { name: '新增成员', exact: true })
      await expect(add.getByLabel('成员名称', { exact: true })).toBeFocused()
      await add.getByLabel('成员名称', { exact: true }).fill('隔离失败反馈验证')
      await page.route('**/api/v1/family/members', route => route.request().method() === 'POST'
        ? route.fulfill({ status: 503, json: { code: 503, message: '模拟成员保存失败' } })
        : route.continue())
      await add.getByRole('button', { name: '保存', exact: true }).click()
      const error = page.getByRole('alert').filter({ hasText: '模拟成员保存失败' })
      await expect(error).toBeVisible()
      await error.getByRole('button', { name: '关闭提示：模拟成员保存失败', exact: true }).click({ trial: true })
      await page.screenshot({ path: test.info().outputPath(`member-save-error-${width}.png`), animations: 'disabled' })
      await page.keyboard.press('Escape')
      await expect(add).toHaveCount(0)
      await fits(page)
      await page.screenshot({ path: test.info().outputPath(`family-${width}.png`), animations: 'disabled' })
    })

    test('pays and reverses two real plans with a fixed allocation summary and retained financial safeguards', async ({ page, request }) => {
      const call = await api(request)
      const card = await call('/accounts', 'POST', { name: `${prefix}${width}信用卡`, type: 'credit', initial_balance: 1000, debt_tracking_mode: 'managed' })
      const plans = []
      for (const [name, amount] of [['家电', 400], ['旅行', 200]] as const) plans.push(await call('/debt/plans', 'POST', {
        account_id: card.id, scope: 'account', name: `${prefix}${width}${name}`, original_principal: amount, opening_principal: amount, idempotency_key: crypto.randomUUID(),
      }))
      const cashBefore = (await call(`/accounts/${cashId}`)).current_balance
      await page.goto(`/#/reminders?account_id=${card.id}`)
      await expect(page.getByRole('article', { name: `分期 ${plans[0].name}`, exact: true })).toBeVisible()
      await page.getByRole('button', { name: '分期账户范围', exact: true }).click()
      await expect(page.getByRole('option').filter({ hasText: card.name })).toBeVisible()
      await page.keyboard.press('Escape')
      await page.getByRole('button', { name: '登记付款', exact: true }).click()
      const pay = page.getByRole('dialog', { name: '登记付款', exact: true })
      await pay.getByLabel('本次付款金额', { exact: true }).fill('150')
      await pay.getByLabel('付款账户', { exact: true }).selectOption(cashId)
      await pay.getByLabel(`${plans[0].name} 本金`, { exact: true }).fill('100')
      await expect(pay.getByRole('button', { name: '确认付款', exact: true })).toBeDisabled()
      await expect(pay.locator('.debt-allocation-summary')).toContainText('50.00')
      await pay.getByLabel(`${plans[1].name} 本金`, { exact: true }).fill('50')
      await expect(pay.getByRole('button', { name: '确认付款', exact: true })).toBeEnabled()
      await page.setViewportSize({ width, height: 600 })
      const footer = pay.locator('footer')
      expect((await footer.boundingBox())!.y + (await footer.boundingBox())!.height).toBeLessThanOrEqual(601)
      await pay.getByRole('button', { name: '确认付款', exact: true }).click()
      await expect(pay).toHaveCount(0)
      expect((await call(`/accounts/${card.id}`)).current_balance).toBe(850)
      expect((await call(`/accounts/${cashId}`)).current_balance).toBe(cashBefore - 150)
      const payment = (await call(`/debt/operations?account_id=${card.id}`)).find((operation: any) => operation.kind === 'payment')
      await page.getByRole('button', { name: `查看凭证 登记付款 ${payment.id}`, exact: true }).click()
      const receipt = page.getByRole('dialog', { name: '分期操作凭证', exact: true })
      await expect(receipt).toContainText(payment.id)
      await receipt.getByRole('button', { name: '撤销此操作', exact: true }).click()
      const reverse = page.getByRole('dialog', { name: '撤销分期操作', exact: true })
      await reverse.getByRole('button', { name: '确认撤销', exact: true }).click()
      await expect(reverse).toHaveCount(0)
      expect((await call(`/accounts/${card.id}`)).current_balance).toBe(1000)
      expect((await call(`/accounts/${cashId}`)).current_balance).toBe(cashBefore)
      await page.setViewportSize({ width, height: 844 })
      await page.locator('main').evaluate(element => element.scrollTo({ top: 0, behavior: 'instant' }))
      await fits(page)
      await page.screenshot({ path: test.info().outputPath(`debt-${width}.png`), animations: 'disabled' })
    })
  })
}

for (const width of [320, 768, 1024, 1920]) {
  for (const theme of ['light', 'dark'] as const) {
    test(`${width}px ${theme} keeps all adapted page surfaces and controls within the viewport`, async ({ page }) => {
      test.setTimeout(60_000)
      await page.setViewportSize({ width, height: 900 })
      await page.emulateMedia({ reducedMotion: 'reduce', colorScheme: theme === 'dark' ? 'light' : 'dark' })
      await login(page)
      await page.goto('/#/appearance')
      await page.getByRole('button', { name: theme === 'dark' ? '深色' : '浅色', exact: true }).click()
      await expect(page.locator('html')).toHaveClass(theme === 'dark' ? /dark/ : /^(?!.*\bdark\b)/)
      for (const [path, title] of Object.entries({ transactions: '账单明细', statistics: '统计分析', report: '年度报告', family: '家庭成员', reminders: '负债管理', appearance: '外观设置' })) {
        await page.goto(`/#/${path}`)
        await expect(page.getByRole('heading', { name: title, exact: true, level: 1 })).toBeVisible()
        await fits(page)
        const unnamed = await page.locator('button:visible').evaluateAll(buttons => buttons
          .filter(button => !button.getAttribute('aria-label') && !button.textContent?.trim()).length)
        expect(unnamed).toBe(0)
        if (width === 320 || (width === 1024 && path === 'reminders')) {
          await page.screenshot({ path: test.info().outputPath(`${path}-${width}-${theme}.png`), animations: 'disabled' })
        }
      }
      await page.getByRole('button', { name: '侧栏', exact: true }).click()
      await expect(page.locator('.ledger-workspace')).toHaveAttribute('data-mode', width < 768 ? 'mobile' : 'rail')
      await page.reload()
      await expect(page.getByRole('button', { name: '侧栏', exact: true })).toHaveAttribute('aria-pressed', 'true')
    })
  }
}

test('320px large summary amounts and long member names keep their full values', async ({ page, request }) => {
  await page.setViewportSize({ width: 320, height: 844 })
  await login(page)
  await page.route('**/api/v1/statistics/overview*', route => route.fulfill({ json: { code: 0, data: {
    expense: 1234567.89, income: 2345678.9, balance: 1111111.01,
  } } }))
  await page.goto('/#/statistics')
  await expect(page.getByText('¥1,234,567.89', { exact: true })).toBeVisible()
  await fits(page)
  const call = await api(request)
  const longName = `ABCDEFGHIJKLMNOPQRSTUVWXYZ${test.info().project.name.slice(0, 4)}`
  await call(`/family/members/${memberId}`, 'PUT', { name: longName, relationship: '模拟', color: '#159b67' })
  await page.goto('/#/family')
  await expect(page.getByText(longName, { exact: true })).toBeVisible()
  expect(await page.locator('.family-member-button').evaluateAll(rows => rows.every(row => row.scrollWidth <= row.clientWidth + 1))).toBe(true)
  await fits(page)
  await page.screenshot({ path: test.info().outputPath('family-long-320.png'), animations: 'disabled' })
})
