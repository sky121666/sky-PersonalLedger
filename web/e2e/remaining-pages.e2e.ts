import { expect, test, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
const longName = 'BANKACCOUNT1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ'
let accountId = ''

test.beforeAll(async ({ request }) => {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED, 'these fixtures require the isolated runner').toBe('1')
  const status = await request.get('/api/v1/auth/status')
  expect(status.ok()).toBeTruthy()
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
  const login = await request.post('/api/v1/auth/login', { data: { password } })
  expect(login.ok()).toBeTruthy()
  const headers = { Authorization: `Bearer ${(await login.json()).data.access_token}` }
  const account = await request.post('/api/v1/accounts', {
    headers,
    data: { name: longName, type: 'bank_card', initial_balance: 1200 },
  })
  expect(account.ok()).toBeTruthy()
  accountId = (await account.json()).data.id
  expect((await request.post('/api/v1/transactions', {
    headers,
    data: {
      type: 'expense', account_id: accountId, amount: 18,
      remark: '隔离流水兼容性验证', transaction_date: new Date().toISOString(),
      idempotency_key: crypto.randomUUID(),
    },
  })).ok()).toBeTruthy()
})

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

async function fits(page: Page, width: number) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)
  expect(await page.locator('main').first().evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  await expect(page.locator('h1:visible')).toHaveCount(1)
}

for (const width of [320, 390, 768, 1440]) {
  for (const theme of ['light', 'dark'] as const) {
    test(`remaining routes fit ${width}px in ${theme}, including a long account name`, async ({ page }) => {
      await page.setViewportSize({ width, height: 844 })
      await page.emulateMedia({ reducedMotion: 'reduce' })
      const errors: string[] = []
      page.on('pageerror', error => errors.push(error.message))
      await login(page)
      await page.goto('/#/appearance')
      await page.getByRole('button', { name: theme === 'dark' ? '深色' : '浅色', exact: true }).click()
      for (const path of [
        'accounts', 'budgets', 'lendings', 'categories', 'tags', 'templates',
        'account-logs', `account-logs/${accountId}`, 'ai', 'settings',
      ]) {
        await page.goto(`/#/${path}`)
        await expect(page.locator('main h1')).toBeVisible()
        if (path === 'accounts') await expect(page.getByText(longName, { exact: true }).first()).toBeVisible()
        if (path.startsWith('account-logs/')) {
          await expect(page.getByRole('heading', { name: `${longName} 流水`, exact: true })).toBeVisible()
        }
        await fits(page, width)
        if (width === 390 || width === 1440) {
          await page.screenshot({
            path: test.info().outputPath(`${path.replace('/', '-')}-${width}-${theme}.png`),
            animations: 'disabled',
          })
        }
      }
      expect(errors).toEqual([])
    })
  }
}

for (const width of [320, 1440]) {
  test(`setup database and password drafts fit ${width}px without applying configuration`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    const unexpectedWrites: string[] = []
    await page.route('**/api/v1/**', async route => {
      const request = route.request()
      const path = new URL(request.url()).pathname
      if (request.method() !== 'GET') unexpectedWrites.push(path)
      if (path === '/api/v1/auth/status') {
        await route.fulfill({ json: { code: 0, data: { initialized: false } } })
      } else if (path === '/api/v1/setup/status') {
        await route.fulfill({ json: { code: 0, data: {
          initialized: false,
          database: { driver: 'sqlite', path: './data/ledger.db', dsn_configured: false, max_open_conns: 1, max_idle_conns: 1 },
        } } })
      } else {
        await route.fulfill({ status: 501, json: { code: 501, message: 'Unexpected isolated setup request' } })
      }
    })
    await page.goto('/#/setup')
    await expect(page.getByRole('heading', { name: '选择数据库', exact: true })).toBeVisible()
    await page.getByRole('button', { name: '更换数据库', exact: true }).click()
    for (const driver of ['PostgreSQL', 'MySQL', 'SQLite']) {
      await page.getByRole('button', { name: driver, exact: true }).click()
      await fits(page, width)
    }
    await page.getByRole('button', { name: '取消更换', exact: true }).click()
    await page.getByRole('button', { name: '继续使用当前配置', exact: true }).click()
    await expect(page.getByRole('heading', { name: '设置访问密码', exact: true })).toBeVisible()
    await fits(page, width)
    expect(unexpectedWrites).toEqual([])
    await page.screenshot({ path: test.info().outputPath(`setup-${width}.png`), animations: 'disabled' })
  })
}
