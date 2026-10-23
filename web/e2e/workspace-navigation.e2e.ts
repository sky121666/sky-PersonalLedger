import { expect, test, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.beforeEach(async ({ page }) => {
  page.on('pageerror', error => { throw error })
})

async function login(page: Page) {
  const status = await page.request.get('/api/v1/auth/status')
  expect(status.ok()).toBeTruthy()
  if (!(await status.json()).data?.initialized) {
    expect((await page.request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

async function mockHome(page: Page) {
  await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: { list: [], total_assets: 0, total_liabilities: 0, net_assets: 0 } } }))
  await page.route(/\/api\/v1\/transactions(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: { list: [], total: 0, page: 1, page_size: 20 } } }))
  await page.route('**/api/v1/statistics/overview', route => route.fulfill({ json: { code: 0, data: { income: 0, expense: 0, balance: 0, income_change: 0, expense_change: 0, daily_average: 0, transaction_count: 0 } } }))
  await page.route('**/api/v1/debt/summary', route => route.fulfill({ json: { code: 0, data: { total_debt: 0, total_paid: 0, total_principal: 0, progress: 0, active_loans: 0, paid_off_loans: 0, next_payment_day: 0, next_payment_name: '', days_until_next: 0 } } }))
  await page.route('**/api/v1/budgets/summary', route => route.fulfill({ json: { code: 0, data: { total_amount: 0, total_spent: 0, percentage: 0, daily_available: 0, days_remaining: 0, over_budget_categories: [] } } }))
  await page.route('**/api/v1/lendings/summary', route => route.fulfill({ json: { code: 0, data: { total_lend_out: 0, total_borrow_in: 0, active_lend_out: 0, active_borrow_in: 0, settled_lend_out: 0, settled_borrow_in: 0, total_receivable: 0, total_payable: 0, net_lending: 0 } } }))
  await page.route(/\/api\/v1\/family\/summary(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: { month: '2026-10', total_expense: 0, members: [] } } }))
  await page.route(/\/api\/v1\/ai\/reports(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: [] } }))
}

for (const width of [320, 390, 1440]) {
  test(`navigation shell stays coherent at ${width}px`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page)
    await login(page)
    const nav = page.getByRole('navigation', { name: '主导航' })
    await expect(nav).toBeVisible()
    for (const label of ['首页', '明细', '统计', '预算']) await expect(nav.getByRole('button', { name: label, exact: true })).toBeVisible()
    if (width < 768) {
      await expect(page.getByRole('button', { name: '更多导航', exact: true })).toBeVisible()
      await expect(page.getByRole('complementary', { name: '钉住侧栏' })).toHaveCount(0)
    } else {
      await expect(page.getByRole('button', { name: '打开更多导航', exact: true })).toBeVisible()
      await expect(page.getByRole('button', { name: '切换到侧栏导航' })).toBeVisible()
    }
    await expect(nav.getByRole('button', { name: '首页', exact: true })).toHaveAttribute('aria-current', 'page')
    await expect(page.getByRole('button', { name: '我的', exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: '记一笔', exact: true })).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    await page.screenshot({ path: testInfo.outputPath(`navigation-${width}.png`) })
  })
}

test('top and rail modes are mutually exclusive and pinning stays consistent', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await mockHome(page)
  await login(page)
  const nav = page.getByRole('navigation', { name: '主导航' })
  await expect(nav).toHaveAttribute('data-projection', 'top')
  await expect(page.getByRole('complementary', { name: '钉住侧栏' })).toHaveCount(0)
  await page.getByRole('button', { name: '切换到侧栏导航', exact: true }).click()
  await expect(page.getByRole('complementary', { name: '钉住侧栏' })).toBeVisible()
  await expect(nav).toHaveAttribute('data-projection', 'rail')
  await page.screenshot({ path: testInfo.outputPath('navigation-rail.png') })
  await page.getByRole('button', { name: '打开更多导航', exact: true }).click()
  const menu = page.getByRole('region', { name: '更多功能', exact: true })
  await expect(menu).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('navigation-directory.png') })
  await expect(menu.getByRole('button', { name: '取消钉住预算', exact: true })).toBeVisible()
  await menu.getByRole('button', { name: '取消钉住预算', exact: true }).click()
  await expect(nav.getByRole('button', { name: '预算', exact: true })).toHaveCount(0)
  await expect(menu.getByRole('link', { name: '预算', exact: true })).toBeVisible()
  await menu.getByRole('button', { name: '钉住预算', exact: true }).click()
  await expect(menu.getByRole('button', { name: '取消钉住预算', exact: true })).toBeVisible()
  await expect(nav.getByRole('button', { name: '预算', exact: true })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(menu).toHaveCount(0)
  await expect(page.getByRole('button', { name: '打开更多导航', exact: true })).toBeFocused()
  await page.reload()
  await expect(page.getByRole('complementary', { name: '钉住侧栏' })).toBeVisible()
  await expect(nav.getByRole('button', { name: '预算', exact: true })).toBeVisible()
  await page.getByRole('button', { name: '展开侧边栏', exact: true }).click()
  await expect(page.getByRole('button', { name: '收起侧边栏', exact: true })).toBeVisible()
  await page.getByRole('button', { name: '切换到顶部导航', exact: true }).click()
  await expect(nav).toHaveAttribute('data-projection', 'top')
})

test('switching projections preserves query, page instance and scroll; more keeps all destinations reachable', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await mockHome(page)
  await login(page)
  await page.goto('/#/reminders?view=reminders')
  await expect(page).toHaveURL(/\/#\/reminders\?view=reminders$/)
  const main = page.getByRole('main')
  await main.locator('.finance-page').evaluate(element => {
    element.setAttribute('data-instance-check', 'same')
    ;(element as HTMLElement).style.minHeight = '1800px'
  })
  await main.evaluate(element => { element.scrollTop = 120 })
  const previousScroll = await main.evaluate(element => element.scrollTop)
  expect(previousScroll).toBeGreaterThan(0)
  await page.getByRole('button', { name: '切换到侧栏导航', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/reminders\?view=reminders$/)
  await expect(main.locator('[data-instance-check="same"]')).toHaveCount(1)
  expect(await main.evaluate(element => element.scrollTop)).toBe(previousScroll)
  await page.getByRole('button', { name: '打开更多导航', exact: true }).click()
  const menu = page.getByRole('region', { name: '更多功能' })
  await expect(menu.getByRole('link', { name: '负债', exact: true })).toHaveAttribute('aria-current', 'page')
  await menu.getByRole('link', { name: '账户', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/accounts$/)
  await expect(menu).toHaveCount(0)
  await page.goto('/#/account-logs')
  await page.getByRole('button', { name: '打开更多导航', exact: true }).click()
  await expect(menu.getByRole('link', { name: '账户', exact: true })).toHaveAttribute('aria-current', 'page')
  await expect(menu.getByRole('link', { name: '账户日志', exact: true })).not.toHaveAttribute('aria-current', 'page')
})

test('keyboard disclosure and excessive pins fit narrow desktop and mobile projections', async ({ page }) => {
  await page.setViewportSize({ width: 1024, height: 800 })
  await mockHome(page)
  await login(page)
  const trigger = page.getByRole('button', { name: '打开更多导航', exact: true })
  await trigger.focus()
  await trigger.press('Enter')
  const menu = page.getByRole('region', { name: '更多功能' })
  await expect(menu.getByRole('link', { name: '首页', exact: true })).toBeFocused()
  for (const label of ['账户', '负债', '借贷', '账户日志', '家庭', 'AI 分析', '报告', '分类', '标签', '模板']) {
    await menu.getByRole('button', { name: `钉住${label}`, exact: true }).click()
    await expect(menu.getByRole('button', { name: `取消钉住${label}`, exact: true })).toHaveAttribute('aria-pressed', 'true')
  }
  await page.keyboard.press('Escape')
  await expect(trigger).toBeFocused()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.setViewportSize({ width: 320, height: 700 })
  const nav = page.getByRole('navigation', { name: '主导航' })
  await expect(nav).toHaveAttribute('data-projection', 'mobile')
  expect(await nav.getByRole('button').count()).toBe(5)
  await page.getByRole('button', { name: '更多导航', exact: true }).click()
  await expect(menu.getByRole('link', { name: 'AI 分析', exact: true })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
})

test('external navigation changes preserve an open transaction draft without finance writes', async ({ page, context }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await mockHome(page)
  await login(page)
  let financeWrites = 0
  page.on('request', request => {
    if (/\/api\/v1\/(transactions|accounts|debt|reminders|budgets)/.test(request.url()) && request.method() !== 'GET') financeWrites++
  })
  await page.getByRole('button', { name: '记一笔', exact: true }).click()
  const dialog = page.getByRole('dialog', { name: '新增交易' })
  await dialog.getByLabel('金额', { exact: true }).fill('123.45')
  const other = await context.newPage()
  await other.setViewportSize({ width: 1440, height: 900 })
  await other.goto('/#/')
  await other.getByRole('button', { name: '切换到侧栏导航', exact: true }).click()
  await expect(page.getByRole('complementary', { name: '钉住侧栏' })).toBeAttached()
  await expect(dialog.getByLabel('金额', { exact: true })).toHaveValue('123.45')
  expect(financeWrites).toBe(0)
  await dialog.getByRole('button', { name: '关闭交易表单' }).click()
  await expect(dialog).toHaveCount(0)
})

test('home grid responds to an expanded rail without a window resize', async ({ page }) => {
  await page.setViewportSize({ width: 960, height: 900 })
  await mockHome(page)
  await login(page)
  await page.getByRole('button', { name: '切换到侧栏导航' }).click()
  await page.getByRole('button', { name: '展开侧边栏', exact: true }).click()
  const grid = page.getByRole('region', { name: '首页小组件' })
  await expect.poll(() => grid.evaluate(element => getComputedStyle(element).gridTemplateColumns.split(' ').length)).toBe(2)
})

test('profile failure uses safe defaults and reloads only after identity is confirmed', async ({ page }) => {
  let available = false
  await page.route('**/api/v1/auth/profile', route => route.fulfill(available
    ? { json: { code: 0, data: { id: 501, username: 'fixture' } } }
    : { status: 503, json: { code: 500, message: 'fixture unavailable' } }))
  await page.setViewportSize({ width: 1440, height: 900 })
  await mockHome(page)
  await login(page)
  await expect(page.getByText('导航偏好暂不可用，账本功能仍可使用。')).toBeVisible()
  await expect(page.getByRole('navigation', { name: '主导航' })).toHaveAttribute('data-projection', 'top')
  available = true
  await page.getByRole('button', { name: '重试加载偏好' }).click()
  await expect(page.getByRole('button', { name: '重试加载偏好' })).toHaveCount(0)
  await page.getByRole('button', { name: '切换到侧栏导航' }).click()
  await expect(page.getByRole('complementary', { name: '钉住侧栏' })).toBeVisible()
})

test('navigation storage failure leaves displayed and persisted pins unchanged', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await mockHome(page)
  await login(page)
  await page.getByRole('button', { name: '打开更多导航' }).click()
  await page.evaluate(() => {
    const original = Storage.prototype.setItem
    Storage.prototype.setItem = function (key, value) {
      if (key.endsWith(':navigation')) throw new DOMException('fixture quota', 'QuotaExceededError')
      return original.call(this, key, value)
    }
  })
  await page.getByRole('button', { name: '取消钉住预算' }).click()
  await expect(page.getByRole('navigation', { name: '主导航' }).getByRole('button', { name: '预算', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: '取消钉住预算' })).toHaveAttribute('aria-pressed', 'true')
  await expect(page.getByText('导航偏好未保存，请重试加载；其他标签可能已更新')).toBeVisible()
})

test('logout and a different verified identity do not inherit the previous navigation', async ({ page }) => {
  let owner = 501
  await page.route('**/api/v1/auth/profile', route => route.fulfill({ json: { code: 0, data: { id: owner, username: `fixture-${owner}` } } }))
  await page.setViewportSize({ width: 1440, height: 900 })
  await mockHome(page)
  await login(page)
  await page.getByRole('button', { name: '切换到侧栏导航' }).click()
  await page.getByRole('button', { name: '打开更多导航' }).click()
  await page.getByRole('button', { name: '取消钉住预算' }).click()
  await page.keyboard.press('Escape')
  await page.getByRole('button', { name: '我的', exact: true }).click()
  await page.getByRole('button', { name: '退出登录', exact: true }).click()
  await page.getByRole('dialog', { name: '确认退出' }).getByRole('button', { name: '退出', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/login$/)
  owner = 502
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  const nav = page.getByRole('navigation', { name: '主导航' })
  await expect(nav).toHaveAttribute('data-projection', 'top')
  await expect(nav.getByRole('button', { name: '预算', exact: true })).toBeVisible()
  expect(await page.evaluate(() => Object.keys(localStorage).filter(key => key.includes(':501:') && key.endsWith(':navigation')).length)).toBe(1)
})

test('Escape returns to the current more trigger after another tab changes projection', async ({ page, context }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await mockHome(page)
  await login(page)
  await page.getByRole('button', { name: '打开更多导航' }).click()
  const other = await context.newPage()
  await other.setViewportSize({ width: 1440, height: 900 })
  await other.goto('/#/')
  await other.getByRole('button', { name: '切换到侧栏导航' }).click()
  await expect(page.getByRole('complementary', { name: '钉住侧栏' })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('region', { name: '更多功能' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: '打开更多导航' })).toBeFocused()
})

for (const version of ['invalid', 'future']) {
  test(`${version} navigation is reported and recovery preserves protected content`, async ({ page }) => {
    const key = 'personal-ledger:workspace:%2Fapi%2Fv1:501:navigation'
    const raw = version === 'invalid' ? '{broken' : '{"version":99,"revision":"future","value":{}}'
    await page.route('**/api/v1/auth/profile', route => route.fulfill({ json: { code: 0, data: { id: 501, username: 'fixture' } } }))
    await page.addInitScript(({ key, raw }) => { if (!localStorage.getItem(key)) localStorage.setItem(key, raw) }, { key, raw })
    await page.setViewportSize({ width: 1440, height: 900 })
    await mockHome(page)
    await login(page)
    await expect(page.getByRole('button', { name: '切换到侧栏导航' })).toBeDisabled()
    await expect(page.getByRole('button', { name: '重试加载偏好' })).toBeVisible()
    if (version === 'invalid') {
      await page.getByRole('button', { name: '恢复默认导航' }).click()
      await expect(page.getByRole('button', { name: '切换到侧栏导航' })).toBeEnabled()
      expect(await page.evaluate(key => JSON.parse(localStorage.getItem(key)!).version, key)).toBe(1)
    } else {
      await expect(page.getByText('导航偏好来自更高版本，原配置已保留，当前使用默认导航。')).toBeVisible()
      await expect(page.getByRole('button', { name: '恢复默认导航' })).toHaveCount(0)
      await page.getByRole('button', { name: '重试加载偏好' }).click()
      expect(await page.evaluate(key => localStorage.getItem(key), key)).toBe(raw)
      await page.getByRole('button', { name: '打开更多导航' }).click()
      const menu = page.getByRole('region', { name: '更多功能' })
      await expect(menu.getByRole('button', { name: '取消钉住预算' })).toBeDisabled()
      await menu.getByRole('link', { name: '账户', exact: true }).click()
      await expect(page).toHaveURL(/\/#\/accounts$/)
    }
  })
}
