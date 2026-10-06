import { expect, test, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.beforeAll(async ({ request }) => {
  const status = await request.get('/api/v1/auth/status')
  expect(status.ok()).toBeTruthy()
  if (!(await status.json()).data?.initialized) {
    const initialized = await request.post('/api/v1/auth/init', { data: { password } })
    expect(initialized.ok()).toBeTruthy()
  }
})

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁' }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

test('transaction failures distinguish unknown, stale and incomplete lists and can retry', async ({ page }) => {
  await login(page)
  const pageErrors: string[] = []
  page.on('pageerror', error => pageErrors.push(error.message))
  let failFirstPage = true
  let failMore = true
  const transaction = (id: string, remark: string) => ({
    id, remark, type: 'expense', amount: 12.5, account_id: 'wallet',
    transaction_date: '2026-09-08T10:00:00+08:00', source: 'manual',
    account: { id: 'wallet', name: '现金' }, category: { name: '餐饮' }
  })
  await page.route(/\/api\/v1\/transactions(?:\?|$)/, async route => {
    const query = new URL(route.request().url()).searchParams
    const pageNumber = Number(query.get('page') || 1)
    const fail = query.has('keyword') || (pageNumber === 1 ? failFirstPage : failMore)
    await route.fulfill({
      status: fail ? 503 : 200,
      json: fail ? { code: 500, message: 'test outage' } : {
        code: 0, data: {
          list: [pageNumber === 1 ? transaction('first', '已加载的交易') : transaction('second', '第二页交易')],
          total: 2, page: pageNumber, page_size: 20
        }
      }
    })
  })
  await page.goto('/#/transactions')
  await expect(page.getByRole('alert')).toContainText('交易加载失败')
  await expect(page.getByText('暂无交易记录', { exact: true })).toHaveCount(0)
  await expect(page.getByRole('button', { name: '点击加载更多' })).toHaveCount(0)

  failFirstPage = false
  await page.getByRole('button', { name: '重新加载交易' }).click()
  await expect(page.getByText('已加载的交易', { exact: true })).toBeVisible()
  await expect(page.getByRole('alert')).toHaveCount(0)
  await page.getByRole('button', { name: '点击加载更多' }).click()
  await expect(page.getByRole('alert')).toContainText('更多交易加载失败')
  await expect(page.getByText('已加载的交易', { exact: true })).toBeVisible()

  failMore = false
  await page.getByRole('button', { name: '重试加载更多' }).click()
  await expect(page.getByText('第二页交易', { exact: true })).toBeVisible()
  await expect(page.getByText('已加载的交易', { exact: true })).toHaveCount(1)
  await page.getByPlaceholder('搜索', { exact: true }).fill('不同条件')
  await expect(page.getByRole('alert')).toContainText('上次成功加载的结果')
  await expect(page.getByText('已加载的交易', { exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: '点击加载更多' })).toHaveCount(0)
  expect(pageErrors).toEqual([])
})

test('account failures do not show zero assets and retain the last balances after a mutation', async ({ page }) => {
  await login(page)
  let failList = true
  const account = {
    id: 'test-account', name: '已加载的钱包', type: 'cash', color: '#3B82F6',
    current_balance: 125, initial_balance: 125, is_archived: false
  }
  await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({
    status: failList ? 503 : 200,
    json: failList ? { code: 500, message: 'test outage' } : {
      code: 0, data: { list: [account], total_assets: 125, total_liabilities: 0, net_assets: 125 }
    }
  }))
  await page.route('**/api/v1/accounts/test-account/archive', async route => {
    failList = true
    await route.fulfill({ json: { code: 0, data: null } })
  })
  await page.goto('/#/accounts')
  await expect(page.getByRole('alert')).toContainText('账户加载失败')
  await expect(page.getByText('净资产', { exact: true })).toHaveCount(0)
  await expect(page.getByText('添加第一个账户', { exact: true })).toHaveCount(0)

  failList = false
  await page.getByRole('button', { name: '重新加载账户' }).click()
  await expect(page.getByText('已加载的钱包', { exact: true })).toBeVisible()
  await expect(page.getByText('净资产', { exact: true })).toBeVisible()
  await page.getByRole('button', { name: '归档账户 已加载的钱包' }).click()
  await expect(page.getByRole('alert')).toContainText('账户和余额为上次成功加载的结果')
  await expect(page.getByText('已加载的钱包', { exact: true })).toBeVisible()
  await expect(page.getByText('¥125.00', { exact: true }).first()).toBeVisible()

  failList = false
  await page.getByRole('button', { name: '重新加载账户' }).click()
  await expect(page.getByRole('alert')).toHaveCount(0)
})
