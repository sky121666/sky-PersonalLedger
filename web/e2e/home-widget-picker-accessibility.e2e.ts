import { expect, test } from '@playwright/test'

for (const dark of [false, true]) {
  test(`account picker keeps readable metadata and predictable Tab focus in ${dark ? 'dark' : 'light'} theme`, async ({ page, browserName }) => {
    await page.setViewportSize({ width: 390, height: 844 })
    const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
    const status = await page.request.get('/api/v1/auth/status')
    if (!(await status.json()).data?.initialized) {
      expect((await page.request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
    }
    await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
      list: Array.from({ length: 40 }, (_, index) => ({
        id: `contrast-bank-${index}`, name: `合成银行卡 ${index}`, type: 'bank_card', icon: 'wallet', color: '#007AFF',
        current_balance: 800, initial_balance: 800, total_paid: 0, is_archived: false, sort_order: 0,
      })), total_assets: 32000, total_liabilities: 0, net_assets: 32000,
    } } }))
    await page.goto('/#/login')
    await page.getByLabel('密码', { exact: true }).fill(password)
    await page.getByRole('button', { name: '解锁', exact: true }).click()
    await expect(page).toHaveURL(/\/#\/$/)
    await page.locator('html').evaluate((el, enabled) => el.classList.toggle('dark', enabled), dark)
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    await gallery.getByRole('button', { name: '预览指定账户', exact: true }).click()
    const trigger = gallery.getByRole('button', { name: '组件关联账户', exact: true })
    await trigger.click()
    const search = gallery.getByRole('combobox', { name: '搜索账户', exact: true })
    const contrast = await gallery.locator('.picker-group').evaluate(el => {
      const luminance = (color: string) => color.match(/[\d.]+/g)!.slice(0, 3).map(Number)
        .map(value => value / 255).map(value => value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4)
        .reduce((sum, value, index) => sum + value * [.2126, .7152, .0722][index]!, 0)
      const foreground = luminance(getComputedStyle(el).color)
      const background = luminance(getComputedStyle(el.closest('.picker-panel')!).backgroundColor)
      return (Math.max(foreground, background) + .05) / (Math.min(foreground, background) + .05)
    })
    expect(contrast).toBeGreaterThanOrEqual(4.5)
    await page.screenshot({ path: test.info().outputPath('account-picker.png'), animations: 'disabled' })
    const options = gallery.getByRole('listbox', { name: '可选账户' })
    await options.scrollIntoViewIfNeeded()
    if (browserName === 'chromium') {
      const cdp = await page.context().newCDPSession(page)
      await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: true })
      const box = (await options.boundingBox())!
      const x = box.x + box.width / 2
      const start = box.y + box.height - 20
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y: start }] })
      for (let delta = 20; delta <= 140; delta += 20) {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: start - delta }] })
      }
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
      await cdp.detach()
    } else {
      await options.hover()
      await page.mouse.wheel(0, 150)
    }
    await expect.poll(() => options.evaluate(el => el.scrollTop)).toBeGreaterThan(20)
    await search.press('ArrowDown')
    await search.press('Enter')
    await expect(trigger).toBeFocused()
    await trigger.click()
    await search.press('Tab')
    await expect(gallery.getByRole('button', { name: '添加到首页', exact: true })).toBeFocused()
    await expect(search).toHaveCount(0)
    await trigger.click()
    await search.press('Shift+Tab')
    await expect(trigger).toBeFocused()
    await expect(search).toHaveCount(0)
    await page.keyboard.press('Escape')
    await expect(page.getByRole('button', { name: '添加小组件', exact: true })).toBeFocused()
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
  })
}

test('optional cards distinguish outstanding balances, report states, empty results and outages', async ({ page }) => {
  const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
  const status = await page.request.get('/api/v1/auth/status')
  if (!(await status.json()).data?.initialized) {
    expect((await page.request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
  let phase = 'populated'
  let reportStatus = 'running'
  const month = '2026-10'
  await page.route('**/api/v1/lendings/summary', route => phase === 'outage'
    ? route.fulfill({ status: 503, json: { code: 500, message: 'synthetic outage' } })
    : route.fulfill({ json: { code: 0, data: {
      total_lend_out: 100, total_borrow_in: 100, active_lend_out: phase === 'empty' ? 0 : 1,
      active_borrow_in: phase === 'empty' ? 0 : 1, settled_lend_out: 0, settled_borrow_in: 0,
      total_receivable: phase === 'empty' ? 0 : 100, total_payable: phase === 'empty' ? 0 : 100, net_lending: 0,
    } } }))
  await page.route(/\/api\/v1\/family\/summary(?:\?|$)/, route => phase === 'outage'
    ? route.fulfill({ status: 503, json: { code: 500, message: 'synthetic outage' } })
    : route.fulfill({ json: { code: 0, data: { month, total_expense: phase === 'empty' ? 0 : 4515, members: [] } } }))
  await page.route(/\/api\/v1\/ai\/reports(?:\?|$)/, route => phase === 'outage'
    ? route.fulfill({ status: 503, json: { code: 500, message: 'synthetic outage' } })
    : route.fulfill({ json: { code: 0, data: phase === 'empty' ? [] : [{
      id: 'state-report', report_type: 'monthly', status: reportStatus, content_json: '{"summary":"合成摘要"}',
      snapshot_json: '{}', period_start: `${month}-01`, period_end: `${month}-31`,
      provider_id: 'synthetic', provider_name: '合成提供商', model: 'synthetic', prompt_version: '1',
      created_at: `${month}-21`, updated_at: `${month}-21`,
    }] } }))
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
  const writes: string[] = []
  page.on('request', request => { if (request.url().includes('/api/v1/') && request.method() !== 'GET') writes.push(request.url()) })
  await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
  await page.getByRole('button', { name: '添加小组件', exact: true }).click()
  const gallery = page.getByRole('dialog', { name: '组件画廊' })
  for (const title of ['借贷往来', '家庭支出', 'AI 分析']) {
    await gallery.getByRole('button', { name: `预览${title}`, exact: true }).click()
    await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
  }
  await page.keyboard.press('Escape')
  await page.getByRole('button', { name: '完成编辑', exact: true }).click()
  const grid = page.getByRole('region', { name: '首页小组件' })
  const lending = grid.getByRole('article', { name: '借贷往来', exact: true })
  const family = grid.getByRole('article', { name: '家庭支出', exact: true })
  const ai = grid.getByRole('article', { name: 'AI 分析', exact: true })
  await expect(lending.getByText('100.00', { exact: true })).toHaveCount(2)
  await expect(lending).not.toContainText('暂无未结清借贷')
  await expect(family).toContainText('4,515.00')
  for (const [state, label] of [['running', '生成中'], ['pending', '等待中'], ['failed', '生成失败'], ['completed', '已生成'], ['unexpected', '状态未知']]) {
    reportStatus = state!
    await page.getByRole('button', { name: '刷新首页数据', exact: true }).click()
    await expect(ai.locator('.widget-badge')).toHaveText(label!)
  }
  phase = 'outage'
  await page.getByRole('button', { name: '刷新首页数据', exact: true }).click()
  for (const card of [lending, family, ai]) await expect(card).toContainText('加载失败')
  await expect(lending).not.toContainText('暂无未结清借贷')
  await expect(ai).not.toContainText('还没有报告')
  phase = 'empty'
  await page.getByRole('button', { name: '刷新首页数据', exact: true }).click()
  await expect(family).toContainText('本月暂无支出')
  await expect(lending).toContainText('暂无未结清借贷')
  await expect(ai).toContainText('还没有报告')
  for (const card of [lending, family, ai]) expect((await card.boundingBox())!.height).toBeLessThan(140)
  expect(writes).toEqual([])
})
