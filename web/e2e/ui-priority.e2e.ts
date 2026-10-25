import { expect, test, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
const categories = [
  { id: 'food', name: '餐饮', type: 'expense', icon: 'utensils', color: '#007aff' },
  ...Array.from({ length: 23 }, (_, i) => ({ id: `interest-${i}`, name: '利息', type: 'expense', icon: '', color: '' })),
  { id: 'travel', name: '交通', type: 'expense', icon: 'car', color: '#007aff' },
]

test.beforeAll(async ({ request }) => {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED, 'must use the temporary database runner').toBe('1')
  const status = await request.get('/api/v1/auth/status')
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBe(true)
  }
})

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

async function mockOptions(page: Page) {
  await page.route(/\/api\/v1\/categories(?:\?|$)/, route =>
    route.fulfill({ json: { code: 0, data: { list: categories } } }))
  await page.route(/\/api\/v1\/accounts(?:\?|$)/, route =>
    route.fulfill({ json: { code: 0, data: {
      list: [{ id: 'cash', name: '模拟钱包', type: 'cash', current_balance: 132032 }],
      total_assets: 132032, total_liabilities: 165687,
    } } }))
}

for (const width of [320, 390, 1440]) {
  test.describe(`${width}px priority UI`, () => {
    test.use({ viewport: { width, height: 844 } })
    test.beforeEach(async ({ page }) => {
      await login(page)
      await mockOptions(page)
      await page.emulateMedia({ reducedMotion: 'reduce' })
    })

    test('category groups keep common choices reachable and preserve historical selection', async ({ page }) => {
      await page.goto('/#/transactions')
      await page.getByRole('button', { name: '记一笔', exact: true }).click()
      const dialog = page.getByRole('dialog', { name: '新增交易', exact: true })
      await expect(dialog.getByRole('button', { name: '选择利息分类', exact: true })).toHaveCount(1)
      await expect(dialog.getByRole('button', { name: '选择交通分类', exact: true })).toBeInViewport()
      await dialog.locator('summary').filter({ hasText: '同名分类' }).click()
      const historicalChoice = dialog.getByRole('button', { name: '利息，同名分类 23', exact: true })
      await historicalChoice.click()
      await expect(historicalChoice).toHaveAttribute('aria-pressed', 'true')
      await page.getByRole('button', { name: '关闭交易表单', exact: true }).click()

      await page.route('**/api/v1/transactions/historical-category', route =>
        route.fulfill({ json: { code: 0, data: {
          id: 'historical-category', type: 'expense', amount: 10, account_id: 'cash',
          category_id: 'interest-22', transaction_date: '2026-10-01T12:00:00+08:00',
        } } }))
      await page.route(/\/api\/v1\/transactions(?:\?|$)/, route =>
        route.fulfill({ json: { code: 0, data: {
          list: [{ id: 'historical-category', type: 'expense', amount: 10, account_id: 'cash',
            category_id: 'interest-22', remark: '模拟历史分类', transaction_date: '2026-10-01T12:00:00+08:00' }],
          total: 1,
        } } }))
      await page.reload()
      await page.getByRole('button', { name: '查看交易 模拟历史分类', exact: true }).click()
      const edit = page.getByRole('dialog', { name: '编辑交易', exact: true })
      await expect(edit.getByRole('button', { name: '选择利息分类', exact: true })).toHaveAttribute('aria-pressed', 'true')
      let payload: Record<string, unknown> | undefined
      await page.route('**/api/v1/transactions/historical-category', async route => {
        if (route.request().method() !== 'PUT') return route.fallback()
        payload = route.request().postDataJSON()
        await route.fulfill({ json: { code: 0, data: { id: 'historical-category' } } })
      })
      await edit.getByLabel('备注', { exact: true }).fill('只改备注')
      await edit.getByRole('button', { name: '保存记录', exact: true }).click()
      await expect.poll(() => payload?.category_id).toBe('interest-22')
    })

    test('account summaries retain every cent and sign at narrow widths', async ({ page }) => {
      await page.goto('/#/accounts')
      await expect(page.getByText('¥-33,655.00', { exact: true })).toBeVisible()
      for (const text of ['¥-33,655.00', '¥132,032.00', '¥165,687.00']) {
        const value = page.getByText(text, { exact: true }).first()
        expect(await value.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
      }
      // Multi-million values must reflow instead of hiding important digits.
      await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
        list: [], total_assets: 123456789.01, total_liabilities: 987654321.09,
      } } }))
      await page.reload()
      const huge = page.getByText('¥987,654,321.09', { exact: true })
      await expect(huge).toBeVisible()
      expect(await huge.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
      expect(await page.locator('main').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
      await page.screenshot({ path: test.info().outputPath('accounts-large.png') })
    })

    test('member budget empty states provide an actionable next step and distinguish request failures', async ({ page }) => {
      await page.route(/\/api\/v1\/budgets(?:\?|$)/, route => route.fulfill({ json: {
        code: 0, data: { total_budget: { id: 'total', amount: 9000, spent: 4515, percentage: 50 }, category_budgets: [], member_budgets: [] },
      } }))
      let state: 'none' | 'disabled' | 'enabled' | 'failed' = 'none'
      await page.route('**/api/v1/family/members', route => state === 'failed'
        ? route.fulfill({ status: 503, json: { message: 'isolated outage' } })
        : route.fulfill({ json: { code: 0, data: state === 'none' ? [] : [{
          id: 'member', name: '模拟家人', is_enabled: state === 'enabled',
        }] } }))
      await page.goto('/#/budgets')
      await expect(page.getByRole('link', { name: '创建家庭成员', exact: true })).toBeVisible()
      await expect(page.getByRole('button', { name: '添加成员预算', exact: true })).toHaveCount(0)
      await page.screenshot({ path: test.info().outputPath('budgets-empty.png') })
      await page.getByRole('link', { name: '创建家庭成员', exact: true }).click()
      await expect(page).toHaveURL(/#\/family$/)
      state = 'disabled'
      await page.goto('/#/budgets')
      await expect(page.getByText('暂无启用成员', { exact: true })).toBeVisible()
      await expect(page.getByRole('link', { name: '管理家庭成员', exact: true })).toBeVisible()
      state = 'enabled'
      await page.reload()
      await expect(page.getByRole('button', { name: '添加成员预算', exact: true })).toBeEnabled()
      state = 'failed'
      await page.reload()
      await expect(page.getByRole('alert')).toContainText('成员加载失败')
      await expect(page.getByRole('link', { name: '创建家庭成员', exact: true })).toHaveCount(0)
      state = 'none'
      await page.getByRole('button', { name: '重新加载成员', exact: true }).click()
      await expect(page.getByRole('link', { name: '创建家庭成员', exact: true })).toBeVisible()
      await page.route(/\/api\/v1\/budgets(?:\?|$)/, route =>
        route.fulfill({ status: 503, json: { message: 'isolated budget outage' } }))
      await page.reload()
      await expect(page.getByRole('alert').filter({ hasText: '预算加载失败' })).toBeVisible()
      await expect(page.getByRole('link', { name: '创建家庭成员', exact: true })).toHaveCount(0)
    })

    if (width < 768) {
      test('keyboard focus and scroll-into-view stay above the floating mobile navigation', async ({ page }) => {
        await page.goto('/#/settings')
        const nav = page.locator('.workspace-mobile-nav')
        await expect(nav).toBeVisible()
        const target = page.getByRole('button', { name: '数据备份', exact: true })
        await target.evaluate(el => {
          const main = el.closest('main')!
          const navTop = document.querySelector('.workspace-mobile-nav')!.getBoundingClientRect().top
          main.scrollTop += el.getBoundingClientRect().top - navTop - 8
        })
        await target.focus()
        const navBox = (await nav.boundingBox())!
        await expect.poll(async () => (await target.boundingBox())!.y + (await target.boundingBox())!.height).toBeLessThanOrEqual(navBox.y - 8)
        const box = (await target.boundingBox())!
        expect(await target.evaluate(el => {
          const r = el.getBoundingClientRect()
          const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2)
          return hit === el || el.contains(hit)
        })).toBe(true)
        expect(box.height).toBeGreaterThanOrEqual(44)
        await page.screenshot({ path: test.info().outputPath('mobile-focus-clear.png') })
      })
    }
  })
}
