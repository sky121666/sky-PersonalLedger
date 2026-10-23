import { readFile } from 'node:fs/promises'
import { expect, test, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.beforeAll(async ({ request }) => {
  const response = await request.get('/api/v1/auth/status')
  if (!(await response.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

async function fits(page: Page) {
  expect(await page.locator('main').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
}

for (const width of [390, 1440]) {
  test.describe(`${width}px analysis workflows`, () => {
    test.use({ viewport: { width, height: 844 } })
    test.beforeEach(async ({ page }) => {
      await page.goto('/#/login')
      await page.getByLabel('密码', { exact: true }).fill(password)
      await page.getByRole('button', { name: '解锁', exact: true }).click()
      await expect(page).toHaveURL(/\/#\/$/)
    })

    test('changes statistics periods and income categories and downloads the annual CSV', async ({ page }) => {
      await page.goto('/#/statistics')
      await page.getByRole('button', { name: '上个月', exact: true }).click()
      const month = await page.locator('main .finance-page-head').textContent()
      const loadingIncome = page.waitForResponse(res => res.url().includes('/statistics/categories') && res.url().includes('type=income'))
      await page.getByRole('button', { name: '收入', exact: true }).click()
      expect((await loadingIncome).ok()).toBeTruthy()
      await fits(page)
      await page.getByRole('button', { name: '下个月', exact: true }).click()
      await expect(page.locator('main .finance-page-head')).not.toHaveText(month!)
      await page.goto('/#/report')
      await expect(page.getByText('年度财务总结', { exact: true })).toBeVisible()
      const year = await page.getByRole('combobox').inputValue()
      const exporting = page.waitForRequest(req => req.url().includes('/export/transactions/csv'))
      const downloading = page.waitForEvent('download')
      await page.locator('main button').filter({ has: page.locator('svg.lucide-download') }).click()
      const download = await downloading
      const url = new URL((await exporting).url())
      expect(url.searchParams.get('start_date')).toBe(`${year}-01-01`)
      expect(url.searchParams.get('end_date')).toBe(`${year}-12-31`)
      expect(await readFile((await download.path())!, 'utf8')).toContain('金额')
      await fits(page)
    })

    test('persists AI provider settings and renders generated reports with a simulated external response', async ({ page }) => {
      test.setTimeout(60_000)
      const name = `隔离AI走查${Date.now()}`
      let reports: unknown[] = []
      await page.route(/\/api\/v1\/ai\/reports(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: reports } }))
      // Provider CRUD uses the real isolated backend. Only the
      // external connection and generated response are simulated in this test.
      await page.route('**/api/v1/ai/providers/*/test', route => route.fulfill({ json: { code: 0, data: { ok: true } } }))
      await page.route('**/api/v1/ai/reports/generate', async route => {
        const params = route.request().postDataJSON()
        expect(params.mask_names).toBe(true)
        const report = {
          id: 'synthetic-report', report_type: params.report_type, period_start: params.period_start,
          period_end: params.period_end, status: 'completed', provider_id: params.provider_id,
          provider_name: name, model: 'synthetic-model',
          content_json: JSON.stringify({
            title: '模拟家庭财务分析', summary: '隔离模拟：本期现金流稳定，餐饮预算需要关注。',
            highlights: ['收入覆盖支出'], suggestions: ['下月减少非必要购物'],
            risks: [{ level: 'medium', title: '餐饮预算接近上限', detail: '长说明用于检查手机端的报告内容换行和风险卡片宽度。' }],
          }),
          snapshot_json: JSON.stringify({
            net_cashflow: 1200, income_total: 5000, budget: { spent: 3800, used_percent: 95 },
            family_members: [{ display_name: '成员1', expense_total: 1000, count: 5 }],
            account_changes: [{ account_name: '账户1', balance_delta: 1200 }],
          }),
        }
        reports = [report]
        await route.fulfill({ json: { code: 0, data: report } })
      })
      await page.route('**/api/v1/ai/reports/synthetic-report', async route => {
        expect(route.request().method()).toBe('DELETE')
        reports = []
        await route.fulfill({ json: { code: 0, data: null } })
      })
      await page.goto('/#/ai/settings')
      await page.getByRole('button', { name: '新增服务', exact: true }).click()
      await page.getByLabel('显示名称', { exact: true }).fill(name)
      await page.getByLabel('接口地址', { exact: true }).fill('https://ledger-preview.example.invalid')
      await page.getByLabel('模型', { exact: true }).fill('synthetic-model')
      await page.getByRole('button', { name: '保存配置', exact: true }).click()
      await page.getByRole('button', { name: `编辑 ${name}`, exact: true }).click()
      await page.getByLabel('显示名称', { exact: true }).fill(`${name}改`)
      await page.getByRole('button', { name: '保存配置', exact: true }).click()
      await expect(page.getByRole('button', { name: `编辑 ${name}改`, exact: true })).toBeVisible()
      await page.reload()
      const edit = page.getByRole('button', { name: `编辑 ${name}改`, exact: true })
      await expect(edit).toBeVisible()
      expect((await page.getByRole('button', { name: `删除 ${name}改`, exact: true }).boundingBox())!.height).toBeGreaterThanOrEqual(44)
      await page.getByRole('button', { name: `测试 ${name}改 的连接`, exact: true }).click()
      await expect(page.getByText(/连接测试通过/)).toBeVisible()
      await page.getByRole('button', { name: `停用 ${name}改`, exact: true }).click()
      await expect(page.getByRole('button', { name: `启用 ${name}改`, exact: true })).toBeVisible()
      await page.getByRole('button', { name: `启用 ${name}改`, exact: true }).click()
      await expect(page.getByRole('button', { name: `停用 ${name}改`, exact: true })).toBeVisible()
      await page.getByRole('button', { name: '返回 AI 分析', exact: true }).click()
      await page.getByRole('button', { name: '新建分析', exact: true }).click()
      await page.getByRole('combobox', { name: '报告类型', exact: true }).selectOption('family')
      await page.getByText('使用的服务', { exact: false }).click()
      const providerSelect = page.getByRole('combobox', { name: 'AI 服务', exact: true })
      const option = providerSelect.locator('option').filter({ hasText: `${name}改` })
      await providerSelect.selectOption((await option.getAttribute('value'))!)
      await page.getByRole('button', { name: '开始分析', exact: true }).click()
      const title = page.getByRole('heading', { name: '模拟家庭财务分析', exact: true })
      await expect(title).toBeVisible()
      await expect(page.getByText('餐饮预算接近上限', { exact: true })).toBeVisible()
      await page.getByText('本次使用的数据', { exact: true }).click()
      await page.getByText('成员支出', { exact: true }).click()
      await page.getByText('账户净变化', { exact: true }).click()
      await expect(page.getByText('成员1', { exact: true })).toBeVisible()
      await expect(page.getByText('账户1', { exact: true })).toBeVisible()
      await fits(page)
      await title.scrollIntoViewIfNeeded()
      await page.screenshot({ path: test.info().outputPath(`ai-report-${width}.png`), fullPage: true })
      await page.getByRole('button', { name: '报告操作', exact: true }).click()
      await page.getByRole('menuitem', { name: '删除此报告', exact: true }).click()
      await page.getByRole('button', { name: '确认删除', exact: true }).click()
      await expect(title).toHaveCount(0)
      await page.getByRole('button', { name: 'AI 设置', exact: true }).click()
      await expect(page.getByText('这是系统级任务，作用于系统内符合条件的用户。', { exact: true })).toBeVisible()
      await expect(page.getByRole('button', { name: '立即触发', exact: true })).toHaveCount(0)
      await page.getByRole('button', { name: `删除 ${name}改`, exact: true }).click()
      await page.getByRole('button', { name: '确认删除', exact: true }).click()
      await expect(edit).toHaveCount(0)
      await fits(page)
    })
  })
}
