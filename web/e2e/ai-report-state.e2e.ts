import { expect, test, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
const provider = {
  id: 'provider-fixture', name: '测试分析方式', provider_type: 'openai_compatible',
  base_url: 'https://example.com/v1', model: 'fixture-model', enabled: true
}
const schedule = { enabled: false, weekly_enabled: true, monthly_enabled: true, hour: 8 }

function report(id: string, title: string, month = '05') {
  return {
    id, report_type: 'weekly', status: 'completed',
    period_start: `2026-${month}-18T00:00:00Z`, period_end: `2026-${month}-24T23:59:59Z`,
    provider_id: provider.id, provider_name: provider.name, model: provider.model,
    content_json: JSON.stringify({ title, summary: `${title}的内容` }),
    snapshot_json: JSON.stringify({ income_total: 500, expense_total: 120, net_cashflow: 380,
      budget: { period_start: `2026-${month}-01`, period_end: `2026-${month}-24`, settings_basis: 'current_budget_settings', spent: 1120, remaining: -820, monthly_budget: 300, used_percent: 373 },
      family_members: [], account_changes: [] })
  }
}

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

test.beforeAll(async ({ request }) => {
  const status = await (await request.get('/api/v1/auth/status')).json()
  if (!status.data?.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

test('AI edits an existing provider and keeps the generated report selected after a slow response', async ({ page }, testInfo) => {
  let currentProvider = { ...provider }
  const newer = report('june', '六月报告', '06')
  const generated = report('may-new', '五月重新生成报告')
  let reports = [newer, report('may-old', '五月历史报告')]
  let updatedBody: Record<string, unknown> | undefined
  let createdProviders = 0
  await page.route('**/api/v1/ai/**', async route => {
    const request = route.request()
    const path = new URL(request.url()).pathname
    let data: unknown
    if (path.endsWith('/providers/presets')) data = []
    else if (path.endsWith(`/providers/${provider.id}`) && request.method() === 'PUT') {
      updatedBody = request.postDataJSON()
      currentProvider = { ...currentProvider, ...updatedBody }
      data = currentProvider
    } else if (path.endsWith('/providers')) {
      if (request.method() === 'POST') createdProviders++
      data = [currentProvider]
    } else if (path.endsWith('/schedule/settings')) data = schedule
    else if (path.endsWith('/reports/generate')) {
      // The backend allows 30 seconds for AI. A healthy result after the
      // general 10-second API timeout must still reach the user.
      await new Promise(resolve => setTimeout(resolve, 10_500))
      reports = [newer, generated, ...reports.slice(1)]
      data = generated
    } else if (path.endsWith('/reports')) data = reports
    else throw new Error(`unexpected AI fixture route: ${path}`)
    await route.fulfill({ json: { code: 0, data } })
  })
  await login(page)
  await page.goto('/#/ai')
  await expect(page.getByRole('heading', { name: '六月报告', exact: true })).toBeVisible()
  await page.getByRole('button', { name: `编辑 Provider ${provider.name}`, exact: true }).click()
  await page.getByLabel('Provider 名称', { exact: true }).fill('修改后的分析方式')
  await expect(page.getByLabel('Provider API Key', { exact: true })).toHaveValue('')
  await page.getByRole('button', { name: '保存修改', exact: true }).click()
  await expect.poll(() => updatedBody?.name).toBe('修改后的分析方式')
  expect(updatedBody).not.toHaveProperty('api_key')
  expect(createdProviders).toBe(0)

  await page.getByLabel('报告开始日期').fill('2026-05-18')
  await page.getByLabel('报告结束日期').fill('2026-05-24')
  await page.getByRole('button', { name: '生成 AI 报告', exact: true }).click()
  await expect(page.getByRole('heading', { name: '五月重新生成报告', exact: true })).toBeVisible({ timeout: 15_000 })
  await page.getByText('2026-05-01 至 2026-05-24 · 按当前预算设置计算', { exact: true }).scrollIntoViewIfNeeded()
  await expect(page.getByText('2026-05-01 至 2026-05-24 · 按当前预算设置计算', { exact: true })).toBeVisible()
  const budgetCard = page.getByText('预算使用', { exact: true }).locator('../..')
  await expect.poll(async () => (await budgetCard.boundingBox())?.width || 0).toBeGreaterThan(120)
  await page.getByRole('button', { name: '刷新', exact: true }).click()
  await expect(page.getByRole('heading', { name: '五月重新生成报告', exact: true })).toBeVisible()
  for (const width of [390, 1280, 1536]) {
    await page.setViewportSize({ width, height: 844 })
    await budgetCard.scrollIntoViewIfNeeded()
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)
    await expect.poll(async () => (await budgetCard.boundingBox())?.width || 0).toBeGreaterThan(120)
    await page.screenshot({ path: testInfo.outputPath(`ai-${width}.png`) })
  }
})

test('AI rejects a late refresh and shows recoverable read errors without an empty history', async ({ page }) => {
  let reportsCalls = 0
  let holdNextReport = false
  let failReports = false
  let releaseOld!: () => void
  const oldGate = new Promise<void>(resolve => { releaseOld = resolve })
  const latest = report('latest', '最新快照')
  await page.route('**/api/v1/ai/**', async route => {
    const path = new URL(route.request().url()).pathname
    let data: unknown
    if (path.endsWith('/providers/presets')) data = []
    else if (path.endsWith('/providers')) data = [provider]
    else if (path.endsWith('/schedule/settings')) data = schedule
    else if (path.endsWith('/reports')) {
      reportsCalls++
      if (failReports) {
        await route.fulfill({ status: 503, json: { code: 50001, message: 'fixture unavailable' } })
        return
      }
      if (holdNextReport) {
        holdNextReport = false
        await oldGate
        data = [report('stale', '陈旧快照')]
      } else data = [latest]
    } else throw new Error(`unexpected AI fixture route: ${path}`)
    await route.fulfill({ json: { code: 0, data } })
  })
  try {
    await login(page)
    await page.goto('/#/ai')
    await expect(page.getByRole('heading', { name: '最新快照', exact: true })).toBeVisible()
    const initialCalls = reportsCalls
    holdNextReport = true
    await page.getByRole('button', { name: '刷新', exact: true }).click()
    await expect.poll(() => reportsCalls).toBe(initialCalls + 1)
    await page.getByRole('button', { name: '刷新', exact: true }).click()
    await expect.poll(() => reportsCalls).toBe(initialCalls + 2)
    releaseOld()
    await page.waitForLoadState('networkidle')
    await expect(page.getByRole('heading', { name: '最新快照', exact: true })).toBeVisible()
    await expect(page.getByRole('heading', { name: '陈旧快照', exact: true })).toHaveCount(0)
    failReports = true
    await page.getByRole('button', { name: '刷新', exact: true }).click()
    await expect(page.getByRole('alert').filter({ hasText: '当前显示的内容可能不是最新状态' })).toBeVisible()
    await expect(page.getByRole('heading', { name: '最新快照', exact: true })).toBeVisible()
    await expect(page.getByText('暂无报告', { exact: true })).toHaveCount(0)
    failReports = false
    await page.getByRole('button', { name: '重试', exact: true }).click()
    await expect(page.getByRole('alert').filter({ hasText: '当前显示的内容可能不是最新状态' })).toHaveCount(0)
  } finally {
    releaseOld()
  }
})
