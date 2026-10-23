import { expect, test, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
const provider = { id: 'provider-fixture', name: '测试分析方式', provider_type: 'openai_compatible', base_url: 'https://example.com/v1', model: 'fixture-model', enabled: true }
const schedule = { enabled: false, weekly_enabled: true, monthly_enabled: true, hour: 8 }
function report(id: string, title: string, month = '10') {
  return { id, report_type: 'monthly', status: 'completed', period_start: `2026-${month}-01`, period_end: `2026-${month}-22`,
    provider_id: provider.id, provider_name: provider.name, model: provider.model, prompt_version: 'personal-ledger-v3-masked', created_at: '2026-10-22T12:00:00Z',
    content_json: JSON.stringify({ title, summary: `${title}的内容`, suggestions: ['核对预算，不自动改写账本。'] }),
    snapshot_json: JSON.stringify({ currency: 'CNY', income_total: 500, expense_total: 120, net_cashflow: 380,
      top_expense_categories: [{ name: '餐饮', amount: 80 }, { name: '出行', amount: 40 }],
      budget: { period_start: `2026-${month}-01`, period_end: `2026-${month}-22`, settings_basis: 'current_budget_settings', spent: 1120, remaining: -820, monthly_budget: 300, used_percent: 373 }, family_members: [], account_changes: [] }) }
}
async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}
async function refresh(page: Page) {
  await page.getByRole('button', { name: '报告操作', exact: true }).click()
  await page.getByRole('menuitem', { name: '刷新报告', exact: true }).click()
}
async function openGenerate(page: Page) {
  await page.getByRole('button', { name: '新建分析', exact: true }).click()
  await expect(page.getByRole('dialog', { name: '新建分析', exact: true })).toBeVisible()
}
async function fits(page: Page) {
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false)
}
test.beforeAll(async ({ request }) => {
  if (process.env.LEDGER_WEB_E2E_ISOLATED !== '1') throw new Error('AI state tests require the isolated E2E runner')
  const status = await (await request.get('/api/v1/auth/status')).json()
  if (!status.data?.initialized) expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
})

test('edits a saved service without replacing its key and selects a slow generated result', async ({ page }, info) => {
  let currentProvider = { ...provider }
  const newer = report('newer', '更新周期的报告', '11'), generated = report('generated', '十月重新生成报告')
  let reports = [newer, report('old', '十月历史报告')]
  let updatedBody: Record<string, unknown> | undefined
  let creates = 0
  await page.route('**/api/v1/ai/**', async route => {
    const req = route.request(), path = new URL(req.url()).pathname
    let data: unknown
    if (path.endsWith('/providers/presets')) data = []
    else if (path.endsWith(`/providers/${provider.id}`) && req.method() === 'PUT') { updatedBody = req.postDataJSON(); currentProvider = { ...currentProvider, ...updatedBody }; data = currentProvider }
    else if (path.endsWith('/providers')) { if (req.method() === 'POST') creates++; data = [currentProvider] }
    else if (path.endsWith('/schedule/settings')) data = schedule
    else if (path.endsWith('/reports/generate')) { await new Promise(resolve => setTimeout(resolve, 10_500)); reports = [newer, generated, ...reports.slice(1)]; data = generated }
    else if (path.endsWith('/reports')) data = reports
    else throw Error(`unexpected AI fixture route: ${path}`)
    await route.fulfill({ json: { code: 0, data } })
  })
  await login(page); await page.goto('/#/ai')
  await expect(page.getByRole('heading', { name: '更新周期的报告', exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'AI 设置', exact: true }).click()
  await page.getByRole('button', { name: `编辑 ${provider.name}`, exact: true }).click()
  await page.getByLabel('显示名称', { exact: true }).fill('修改后的分析方式')
  await expect(page.getByLabel('API Key', { exact: true })).toHaveValue('')
  await page.getByRole('button', { name: '保存配置', exact: true }).click()
  await expect(page.getByRole('button', { name: '编辑 修改后的分析方式', exact: true })).toBeVisible()
  expect(updatedBody).not.toHaveProperty('api_key'); expect(creates).toBe(0)
  await page.getByRole('button', { name: '返回 AI 分析', exact: true }).click()
  await openGenerate(page)
  await page.getByRole('combobox', { name: '时间范围', exact: true }).selectOption('custom')
  await page.getByLabel('开始日期', { exact: true }).fill('2026-10-01')
  await page.getByLabel('结束日期', { exact: true }).fill('2026-10-22')
  await page.getByRole('button', { name: '开始分析', exact: true }).click()
  await expect(page.getByRole('region', { name: 'AI 分析报告', exact: true })).toBeFocused()
  await expect(page.getByRole('heading', { name: '十月重新生成报告', exact: true })).toBeVisible({ timeout: 15_000 })
  await expect(page.getByText('2026-10-01 至 2026-10-22 · 按生成时的预算设置计算', { exact: true })).toBeVisible()
  await refresh(page)
  await expect(page.getByRole('heading', { name: '十月重新生成报告', exact: true })).toBeVisible()
  for (const width of [320, 390, 768, 1440, 1920]) {
    await page.setViewportSize({ width, height: 900 }); await fits(page)
    await expect.poll(async () => (await page.locator('.finance-frame').boundingBox())?.width || 0).toBeLessThanOrEqual(816)
    await page.screenshot({ path: info.outputPath(`report-${width}.png`), fullPage: true })
  }
})

test('ignores obsolete reads and distinguishes a read failure from an empty report list', async ({ page }) => {
  let hold = false, fail = false, calls = 0, release!: () => void
  const gate = new Promise<void>(resolve => { release = resolve })
  await page.route('**/api/v1/ai/**', async route => {
    const path = new URL(route.request().url()).pathname
    let data: unknown
    if (path.endsWith('/providers')) data = [provider]
    else if (path.endsWith('/reports')) {
      calls++
      if (fail) { await route.fulfill({ status: 503, json: { code: 50001, message: 'fixture unavailable' } }); return }
      if (hold) { hold = false; await gate; data = [report('stale', '陈旧快照')] } else data = [report('fresh', '最新快照')]
    } else throw Error(`unexpected read: ${path}`)
    await route.fulfill({ json: { code: 0, data } })
  })
  try {
    await login(page); await page.goto('/#/ai')
    await expect(page.getByRole('heading', { name: '最新快照', exact: true })).toBeVisible()
    const before = calls; hold = true; await refresh(page); await expect.poll(() => calls).toBe(before + 1)
    await refresh(page); await expect.poll(() => calls).toBe(before + 2)
    release(); await page.waitForLoadState('networkidle')
    await expect(page.getByRole('heading', { name: '陈旧快照', exact: true })).toHaveCount(0)
    fail = true; await refresh(page)
    await expect(page.getByRole('alert')).toContainText('当前显示的内容可能不是最新状态')
    await expect(page.getByRole('heading', { name: '最新快照', exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: '新建分析', exact: true })).toBeDisabled()
    fail = false; await page.getByRole('button', { name: '重试加载', exact: true }).click()
    await expect(page.getByRole('alert')).toHaveCount(0)
  } finally { release() }
})

async function fixture(page: Page) {
  const previous = report('previous', '上一份成功报告')
  const state = { reports: [previous], providers: [provider], generateCalls: 0, failList: false, failConfig: false, generatedParams: {} as Record<string, unknown> }
  await page.route('**/api/v1/ai/**', async route => {
    const path = new URL(route.request().url()).pathname
    let data: unknown
    if (path.endsWith('/providers/presets')) data = []
    else if (path.endsWith('/providers')) data = state.providers
    else if (path.endsWith('/schedule/settings')) {
      if (state.failConfig) { await route.fulfill({ status: 503, json: { code: 50001, message: 'schedule unavailable' } }); return }
      data = schedule
    } else if (path.endsWith('/reports/generate')) {
      state.generateCalls++; state.generatedParams = route.request().postDataJSON()
      state.reports = [{ ...previous, ...state.generatedParams, id: 'failed', status: 'failed', content_json: '', error_message: 'ai provider returned empty content' } as typeof previous, previous]
      await route.fulfill({ status: 502, json: { code: 50200, message: 'AI response incomplete' } }); return
    } else if (path.endsWith('/reports')) {
      if (state.failList) { await route.fulfill({ status: 503, json: { code: 50001, message: 'report status unavailable' } }); return }
      data = state.reports
    } else throw Error(`unexpected AI fixture route: ${path}`)
    await route.fulfill({ json: { code: 0, data } })
  })
  return state
}

for (const width of [390, 1440]) test.describe(`report-first at ${width}px`, () => {
  test.use({ viewport: { width, height: 900 } })
  test('period presets, date validation and keyboard dismissal preserve predictable controls', async ({ page }, info) => {
    await page.clock.setFixedTime(new Date('2026-10-22T12:00:00+08:00'))
    await fixture(page); await login(page); await page.goto('/#/ai'); await openGenerate(page)
    const dialog = page.getByRole('dialog', { name: '新建分析', exact: true })
    await expect(page.getByTestId('ai-period-summary')).toHaveText('2026-10-01 至 2026-10-22')
    await page.getByRole('combobox', { name: '报告类型', exact: true }).selectOption('weekly')
    await expect(page.getByTestId('ai-period-summary')).toHaveText('2026-10-19 至 2026-10-22')
    await page.getByRole('combobox', { name: '时间范围', exact: true }).selectOption('previous_month')
    await expect(page.getByTestId('ai-period-summary')).toHaveText('2026-09-01 至 2026-09-30')
    await page.getByRole('combobox', { name: '时间范围', exact: true }).selectOption('custom')
    await page.getByLabel('开始日期', { exact: true }).fill('2026-02-03')
    await page.getByLabel('结束日期', { exact: true }).fill('2026-02-20')
    await page.getByRole('combobox', { name: '报告类型', exact: true }).selectOption('family')
    await expect(page.getByLabel('开始日期', { exact: true })).toHaveValue('2026-02-03')
    await page.getByLabel('开始日期', { exact: true }).fill('2026-02-21')
    await page.getByRole('button', { name: '开始分析', exact: true }).click()
    await expect(page.getByRole('alert')).toContainText('开始日期不能晚于结束日期')
    await fits(page)
    if (width === 390) { expect((await dialog.boundingBox())?.height).toBe(900); expect((await page.getByRole('button', { name: '开始分析', exact: true }).boundingBox())!.y).toBeLessThan(900) }
    await page.screenshot({ path: info.outputPath('generate.png') })
    await page.keyboard.press('Escape'); await expect(dialog).toHaveCount(0)
    await expect(page.getByRole('button', { name: '新建分析', exact: true })).toBeFocused()
  })
  test('snapshot details disclose exact scope without cluttering the report', async ({ page }, info) => {
    const state = await fixture(page), snapshot = JSON.parse(state.reports[0]!.snapshot_json)
    snapshot.family_members = Array.from({ length: 6 }, (_, i) => ({ display_name: `成员${i+1}`, expense_total: 20, count: 1 }))
    snapshot.account_changes = Array.from({ length: 7 }, (_, i) => ({ account_name: `账户${i+1}`, balance_delta: 10 }))
    state.reports[0]!.snapshot_json = JSON.stringify(snapshot)
    await login(page); await page.goto('/#/ai')
    await expect(page.getByText('成员支出人数', { exact: true })).not.toBeVisible()
    await page.getByText('本次使用的数据', { exact: true }).click()
    await expect(page.locator('.ai-scope-list > div').filter({ hasText: '成员支出人数' })).toHaveText('成员支出人数6')
    await expect(page.locator('.ai-scope-list > div').filter({ hasText: '账户数量' })).toHaveText('账户数量7')
    await expect(page.getByText('成员6', { exact: true })).not.toBeVisible()
    await page.getByText('成员支出', { exact: true }).click(); await expect(page.getByText('成员6', { exact: true })).toBeVisible()
    await page.getByText('账户净变化', { exact: true }).click(); await expect(page.getByText('账户7', { exact: true })).toBeVisible()
    await fits(page); await page.screenshot({ path: info.outputPath('scope.png'), fullPage: true })
  })
  test('viewing history never clears the running-task guard', async ({ page }) => {
    const state = await fixture(page)
    state.reports.unshift({ ...report('running', '进行中的报告'), status: 'running' })
    await login(page); await page.goto('/#/ai')
    await expect(page.getByRole('heading', { name: '正在分析你的账本', exact: true })).toBeVisible()
    const scroller = page.locator('.workspace-content')
    const scrollTop = await scroller.evaluate(element => element.scrollTop)
    await page.getByRole('region', { name: 'AI 分析报告', exact: true }).evaluate(element => (element as HTMLElement).focus({ preventScroll: true }))
    expect(await scroller.evaluate(element => element.scrollTop)).toBe(scrollTop)
    await page.getByRole('button', { name: '历史报告', exact: true }).click()
    await page.getByRole('dialog', { name: '历史报告', exact: true }).getByRole('button', { name: /已完成/ }).first().click()
    await expect(page.getByRole('heading', { name: '正在分析你的账本', exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: '新建分析', exact: true })).toBeDisabled()
    expect(state.generateCalls).toBe(0)
  })
  test('confirmed failure retains previous success and retry uses the failed request period', async ({ page }, info) => {
    const state = await fixture(page); await login(page); await page.goto('/#/ai')
    state.failConfig = true
    await openGenerate(page); await page.getByRole('button', { name: '开始分析', exact: true }).click()
    await expect(page.getByRole('heading', { name: '这次分析没有完成', exact: true })).toBeVisible()
    await expect(page.getByRole('heading', { name: '上一份成功报告', exact: true })).toBeVisible()
    expect(state.generateCalls).toBe(1)
    await page.getByText('查看详情', { exact: true }).click()
    await expect(page.getByText('ai provider returned empty content', { exact: true })).toBeVisible()
    const noticeBounds = (await page.locator('.ai-notice').boundingBox())!
    const toolbarBounds = (await page.locator('.ai-toolbar').boundingBox())!
    const reportBounds = (await page.getByTestId('ai-report-document').boundingBox())!
    expect(toolbarBounds.y - noticeBounds.y - noticeBounds.height).toBeGreaterThanOrEqual(16)
    expect(reportBounds.y - toolbarBounds.y - toolbarBounds.height).toBeGreaterThanOrEqual(16)
    await fits(page); await page.screenshot({ path: info.outputPath('failure.png'), fullPage: true })
    await page.getByRole('button', { name: '重新尝试', exact: true }).click()
    await expect(page.getByLabel('开始日期', { exact: true })).toHaveValue(String(state.generatedParams.period_start))
    await expect(page.getByLabel('结束日期', { exact: true })).toHaveValue(String(state.generatedParams.period_end))
    await page.getByRole('button', { name: '取消', exact: true }).click()
    expect(state.generateCalls).toBe(1)
    await page.reload(); await expect(page.getByRole('heading', { name: '这次分析没有完成', exact: true })).toBeVisible()
  })
  test('unknown response requires checking state and never starts an automatic retry', async ({ page }) => {
    const state = await fixture(page); await login(page); await page.goto('/#/ai'); await expect(page.getByRole('heading', { name: '上一份成功报告', exact: true })).toBeVisible(); state.failList = true
    await openGenerate(page); await page.getByRole('button', { name: '开始分析', exact: true }).click()
    await expect(page.getByRole('heading', { name: '生成结果尚未确认', exact: true })).toBeVisible()
    await expect(page.getByRole('heading', { name: '上一份成功报告', exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: '新建分析', exact: true })).toBeDisabled()
    expect(state.generateCalls).toBe(1)
    state.failList = false; await page.getByRole('button', { name: '检查报告状态', exact: true }).click()
    await expect(page.getByRole('heading', { name: '这次分析没有完成', exact: true })).toBeVisible()
    expect(state.generateCalls).toBe(1)
  })
  test('first use leads to dedicated settings, with loading failure distinct from no configuration', async ({ page }, info) => {
    const state = await fixture(page); state.providers = []; state.reports = []; state.failConfig = true
    await login(page); await page.goto('/#/ai')
    await expect(page.getByRole('heading', { name: '让账本，多一份解读', exact: true })).toBeVisible()
    await fits(page); await page.screenshot({ path: info.outputPath('initial.png') })
    await page.getByRole('button', { name: '连接 AI 服务', exact: true }).click()
    await expect(page.getByRole('heading', { name: 'AI 设置', exact: true })).toBeVisible()
    await expect(page.getByText('状态未知', { exact: true })).toBeVisible()
    await page.getByRole('button', { name: '新增服务', exact: true }).click()
    await page.getByLabel('显示名称', { exact: true }).fill('未保存的演示服务')
    await page.getByRole('button', { name: '返回 AI 分析', exact: true }).click()
    await expect(page.getByRole('dialog', { name: '放弃未保存的修改？', exact: true })).toBeVisible()
    await page.getByRole('button', { name: '继续编辑', exact: true }).click()
    await expect(page.getByLabel('显示名称', { exact: true })).toHaveValue('未保存的演示服务')
    await fits(page); await page.screenshot({ path: info.outputPath('settings-editor.png'), fullPage: true })
  })
})
