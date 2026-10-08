import { expect, test, type Page } from '@playwright/test'
import dayjs from 'dayjs'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.beforeAll(async ({ request }) => {
  const status = await request.get('/api/v1/auth/status')
  expect(status.ok()).toBeTruthy()
  if (!(await status.json()).data?.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁' }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

const account = { id: 'reliable-wallet', name: '回归钱包', type: 'cash', color: '#3B82F6', current_balance: 1234, initial_balance: 1234, is_archived: false }
const transaction = (id: string, amount: number) => ({
  id, type: 'expense', amount, account_id: account.id, category_id: 'reliable-food',
  member_id: 'child-A', paid_by_member_id: 'parent-B', source: 'manual',
  transaction_date: '2026-10-06T10:00:00+08:00', remark: `受控交易${id}`, images: '', tags: '[]',
  account: { id: account.id, name: account.name }, category: { id: 'reliable-food', name: '餐饮' },
})

async function mockAccounts(page: Page) {
  await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: { list: [account], net_assets: 1234, total_assets: 1234, total_liabilities: 0 } } }))
}

test('late editor A cannot replace B and remark editing retains its separate payer', async ({ page }) => {
  await mockAccounts(page)
  await page.route(/\/api\/v1\/categories(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: [{ id: 'reliable-food', name: '餐饮', type: 'expense', color: '#3B82F6' }] } }))
  await page.route('**/api/v1/family/members', route => route.fulfill({ json: { code: 0, data: [
    { id: 'child-A', name: '孩子A', is_enabled: true }, { id: 'parent-B', name: '家长B', is_enabled: true },
  ] } }))
  await page.route(/\/api\/v1\/transactions(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: { list: [transaction('A', 30), transaction('B', 200)], total: 2 } } }))
  let releaseA!: () => void
  const pendingA = new Promise<void>(resolve => { releaseA = resolve })
  await page.route('**/api/v1/transactions/A', async route => {
    await pendingA
    await route.fulfill({ json: { code: 0, data: transaction('A', 30) } })
  })
  let saved: any
  await page.route('**/api/v1/transactions/B', async route => {
    if (route.request().method() === 'PUT') saved = route.request().postDataJSON()
    await route.fulfill({ json: { code: 0, data: transaction('B', 200) } })
  })
  await login(page)
  await page.goto('/#/transactions')
  await expect(page.getByRole('heading', { name: '账单明细' })).toBeVisible()
  const requestedA = page.waitForRequest('**/api/v1/transactions/A')
  await page.getByText('受控交易A', { exact: true }).click()
  await requestedA
  await expect(page.getByRole('dialog', { name: '编辑交易' }).getByLabel('金额', { exact: true })).toBeDisabled()
  await expect(page.getByRole('dialog', { name: '编辑交易' }).getByLabel('备注', { exact: true })).toBeDisabled()
  await page.getByRole('button', { name: '关闭交易表单' }).click()
  await page.getByText('受控交易B', { exact: true }).click()
  const dialog = page.getByRole('dialog', { name: '编辑交易' })
  await expect(dialog.getByLabel('金额', { exact: true })).toHaveValue('200')
  const responseA = page.waitForResponse('**/api/v1/transactions/A')
  releaseA()
  await responseA
  for (const width of [390, 1280, 1536]) {
    await page.setViewportSize({ width, height: 844 })
    await expect(dialog.getByLabel('金额', { exact: true })).toHaveValue('200')
    await expect(dialog.getByLabel('归属成员', { exact: true })).toHaveValue('child-A')
    await expect(dialog.getByLabel('付款成员', { exact: true })).toHaveValue('parent-B')
  }
  await dialog.getByLabel('备注', { exact: true }).fill('仅修改备注')
  await dialog.getByRole('button', { name: '保存记录' }).click()
  await expect(page.getByText('修改成功', { exact: true })).toBeVisible()
  expect(saved).toMatchObject({ amount: 200, member_id: 'child-A', paid_by_member_id: 'parent-B', remark: '仅修改备注' })
})

test('optional AI failure leaves core assets visible and refresh reports partial result', async ({ page }) => {
  await mockAccounts(page)
  await page.route(/\/api\/v1\/ai\/reports(?:\?|$)/, route => route.fulfill({ status: 503, json: { code: 500, message: 'controlled AI failure' } }))
  await login(page)
  await expect(page.getByRole('alert')).toContainText('AI 分析加载失败')
  await expect(page.getByText('1,234.00', { exact: true }).first()).toBeVisible()
  await page.getByRole('button', { name: '刷新首页数据' }).click()
  await expect(page.getByText('核心数据已刷新，部分辅助数据加载失败', { exact: true })).toBeVisible()
  await expect(page.getByText('刷新成功', { exact: true })).toHaveCount(0)
})

test('failed month switch hides previous amounts and identifies the selected query', async ({ page }) => {
  const currentMonth = dayjs().format('YYYY-MM')
  const priorMonth = dayjs().subtract(1, 'month').format('YYYY-MM')
  await page.route(/\/api\/v1\/statistics\/(overview|categories|trend)(?:\?|$)/, route => {
    const url = new URL(route.request().url())
    const fail = url.searchParams.get('month') === priorMonth
    const data = url.pathname.endsWith('overview')
      ? { income: 500, expense: 120, balance: 380 }
      : { items: [] }
    return route.fulfill({ status: fail ? 503 : 200, json: fail ? { code: 500, message: 'controlled month failure' } : { code: 0, data } })
  })
  await login(page)
  await page.goto('/#/statistics')
  await expect(page.getByText(dayjs(currentMonth).format('YYYY年M月'), { exact: true }).first()).toBeVisible()
  await expect(page.getByText('120.00', { exact: false }).first()).toBeVisible()
  await page.getByRole('button', { name: '上个月', exact: true }).click()
  const queryAlert = page.getByRole('alert').filter({ has: page.getByRole('button', { name: '重新加载统计' }) })
  await expect(queryAlert).toContainText(`${dayjs(priorMonth).format('YYYY年M月')}统计加载失败`)
  await expect(queryAlert).toContainText('尚无该查询的可用数据')
  await expect(page.getByText('120.00', { exact: false })).toHaveCount(0)
  await expect(page.getByText('本月暂无数据', { exact: true })).toHaveCount(0)
})
