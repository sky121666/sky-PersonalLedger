import { expect, test, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.beforeAll(async ({ request }) => {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED, 'second-batch UI tests require the temporary database runner').toBe('1')
  const status = await request.get('/api/v1/auth/status')
  expect(status.ok()).toBeTruthy()
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

async function mock(page: Page) {
  await page.route(/\/api\/v1\/budgets(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
    total_budget: { id: 'total', amount: 9000, spent: 4515, percentage: 50 },
    member_budgets: [{ id: 'member-budget', member_id: 'member', member_name: '模拟家人', amount: 1500, spent: 300, percentage: 20 }],
    category_budgets: [{ id: 'category-budget', category_id: 'food', category_name: '餐饮', amount: 1800, spent: 134, percentage: 7 }],
  } } }))
  await page.route('**/api/v1/family/members', route => route.fulfill({ json: { code: 0, data: [
    { id: 'member', name: '模拟家人', relationship: '家人', color: '#159b67', is_default: true, is_enabled: true },
  ] } }))
  await page.route(/\/api\/v1\/categories(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: { list: [
    { id: 'food', name: '餐饮', type: 'expense', icon: 'utensils', color: '#007aff' },
    { id: 'travel', name: '交通', type: 'expense', icon: 'car', color: '#159b67' },
  ] } } }))
  await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
    list: [{ id: 'cash', name: '模拟现金', type: 'cash', icon: 'wallet', color: '#3b82f6', initial_balance: 100, current_balance: 100, total_paid: 0, is_archived: false, sort_order: 0 }],
    total_assets: 100, total_liabilities: 0, net_assets: 100,
  } } }))
  await page.route('**/api/v1/debt/capabilities', route => route.fulfill({ json: { code: 0, data: {
    contract_version: 1, multiple_plans: true, explicit_allocation: true, reversal: true, managed_accounts: 'new_accounts_only',
  } } }))
  await page.route(/\/api\/v1\/transactions(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: { list: [], total: 0, page: 1, page_size: 20 } } }))
}

for (const width of [320, 390, 1440]) {
  for (const theme of ['light', 'dark'] as const) {
    test(`budget and account dialogs keep focus, density and one title at ${width}px ${theme}`, async ({ page }) => {
      await page.setViewportSize({ width, height: 844 })
      await page.emulateMedia({ reducedMotion: 'reduce' })
      await login(page)
      await page.goto('/#/appearance')
      await page.getByRole('button', { name: theme === 'dark' ? '深色' : '浅色', exact: true }).click()

      await mock(page)
      await page.goto('/#/budgets')
      await expect(page.locator('main h1:visible')).toHaveCount(1)
      const heading = page.getByRole('heading', { name: '预算管理', exact: true })
      await expect(heading).toHaveCSS('font-size', width < 768 ? '20px' : '22px')
      const card = page.locator('.finance-card').filter({ hasText: '月度总预算' })
      await expect(card).toHaveCSS('border-radius', '22px')
      const add = page.getByRole('button', { name: '添加分类预算', exact: true }).first()
      await expect(add).toBeEnabled()
      await add.focus()
      await add.press('Enter')
      const budgetDialog = page.getByRole('dialog', { name: '添加分类预算', exact: true })
      await expect(budgetDialog).toBeVisible()
      await expect(budgetDialog.getByLabel('选择分类')).toHaveAttribute('name', 'category_id')
      await expect(budgetDialog.getByLabel('预算金额')).toHaveAttribute('name', 'amount')
      await expect(budgetDialog.getByRole('heading', { name: '添加分类预算' })).toBeFocused()
      const last = budgetDialog.getByRole('button').last()
      await last.focus()
      await page.keyboard.press('Tab')
      await expect(budgetDialog.getByRole('button', { name: '关闭添加分类预算' })).toBeFocused()
      await page.keyboard.press('Shift+Tab')
      await expect(last).toBeFocused()
      await page.keyboard.press('Escape')
      await expect(budgetDialog).toHaveCount(0)
      await expect(add).toBeFocused()

      await page.goto('/#/accounts')
      const accountAdd = page.getByRole('button', { name: '添加新账户', exact: true }).first()
      await accountAdd.focus()
      await accountAdd.press('Enter')
      const accountDialog = page.getByRole('dialog', { name: '添加新卡', exact: true })
      await expect(accountDialog).toBeVisible()
      await expect(accountDialog.getByLabel('卡片名称')).toHaveAttribute('name', 'name')
      await expect(accountDialog.getByLabel('账户类型')).toHaveAttribute('name', 'type')
      await expect(accountDialog.getByLabel('初始余额')).toHaveAttribute('name', 'initial_balance')
      await expect(accountDialog.getByRole('heading', { name: '添加新卡' })).toBeFocused()
      await accountDialog.getByRole('button', { name: '取消', exact: true }).click()
      await expect(accountDialog).toHaveCount(0)
      await expect(accountAdd).toBeFocused()
      expect(await page.locator('main').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
      await page.screenshot({ path: test.info().outputPath(`accounts-dialog-closed-${width}-${theme}.png`), animations: 'disabled' })
    })
  }
}

test('settings no longer duplicates business destinations', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await login(page)
  await page.goto('/#/settings')
  await expect(page.getByRole('heading', { name: '系统与安全', exact: true })).toBeVisible()
  await expect(page.getByRole('heading', { name: '数据管理', exact: true })).toBeVisible()
  for (const name of ['账户管理', '分类管理', '标签管理', '预算设置', '负债管理', '借贷往来', '家庭成员', 'AI 分析', '年度报告']) {
    await expect(page.getByRole('button', { name, exact: true })).toHaveCount(0)
  }
})
