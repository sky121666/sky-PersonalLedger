import { expect, test } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.beforeAll(async ({ request }) => {
  const response = await request.get('/api/v1/auth/status')
  expect(response.ok()).toBeTruthy()
  if (!(await response.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

test.beforeEach(async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-10-22T04:00:00Z'))
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
})

test('populated mobile budgets keep the header compact and editing reachable', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  const members = Array.from({ length: 3 }, (_, i) => ({
    id: `member-${i}`, name: `合成成员${i}`, is_enabled: true,
  }))
  await page.route('**/api/v1/family/members', route => route.fulfill({
    json: { code: 0, data: members },
  }))
  await page.route(/\/api\/v1\/budgets(?:\?|$)/, route => route.fulfill({
    json: { code: 0, data: {
      total_budget: { id: 'total', amount: 10000, spent: 8100, percentage: 81 },
      category_budgets: [{
        id: 'food', category_id: 'food', category_name: '餐饮',
        amount: 1000, spent: 1200, percentage: 120,
      }],
      member_budgets: members.map(member => ({
        id: `budget-${member.id}`, member_id: member.id, member_name: member.name,
        category_id: null, amount: 2000, spent: 800, percentage: 40,
      })),
    } },
  }))
  await page.goto('/#/budgets')
  await expect(page.getByText('合成成员2', { exact: true })).toBeVisible()
  const header = page.locator('.finance-page-head').filter({ hasText: '预算管理' })
  expect((await header.boundingBox())!.height).toBeLessThan(125)
  const editMember = page.getByRole('button', { name: '编辑合成成员2的总预算', exact: true })
  await editMember.scrollIntoViewIfNeeded()
  await expect(editMember).toBeVisible()
  await expect(editMember.locator('..')).toHaveCSS('opacity', '1')
  expect((await editMember.boundingBox())!.height).toBeGreaterThanOrEqual(44)
  await editMember.click()
  await expect(page.getByRole('heading', { name: '编辑成员预算', exact: true })).toBeVisible()
  await page.getByRole('button', { name: '关闭编辑成员预算', exact: true }).click()
  const editCategory = page.getByRole('button', { name: '编辑餐饮预算', exact: true })
  await editCategory.scrollIntoViewIfNeeded()
  await expect(editCategory.locator('..')).toHaveCSS('opacity', '1')
  await editCategory.click()
  await expect(page.getByRole('heading', { name: '编辑分类预算', exact: true })).toBeVisible()
})

for (const width of [320, 390, 1280]) {
  test(`long transaction notes preserve amount and actions at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    const remark = '合成数据：家庭聚餐预订与水果采购，较长备注用于验证窄屏不会挤出金额和删除按钮'
    const transaction = {
      id: 'long-note', type: 'expense', amount: 268.8,
      account_id: 'account', category_id: 'food',
      transaction_date: '2026-10-15T08:30:00+08:00', remark, source: 'manual',
      account: { id: 'account', name: '较长名称的合成支付宝账户', type: 'alipay' },
      category: { id: 'food', name: '餐饮', icon: 'wallet' },
    }
    await page.route(/\/api\/v1\/transactions(?:\?|$)/, route => route.fulfill({
      json: { code: 0, data: {
        list: [transaction],
        total: 1, page: 1, page_size: 20,
      } },
    }))
    await page.route('**/api/v1/transactions/long-note', route => route.fulfill({
      json: { code: 0, data: transaction },
    }))
    await page.goto('/#/transactions')
    const note = page.getByText(remark, { exact: true })
    await expect(note).toBeVisible()
    expect((await note.boundingBox())!.height).toBeLessThanOrEqual(24)
    expect((await page.getByText('餐饮', { exact: true }).boundingBox())!.height).toBeLessThanOrEqual(24)
    const amount = page.getByText('−268.80', { exact: true })
    const remove = page.getByRole('button', { name: `交易操作 ${remark}`, exact: true })
    await expect(amount).toBeVisible()
    await expect(remove).toBeVisible()
    const amountBox = (await amount.boundingBox())!
    const removeBox = (await remove.boundingBox())!
    expect(amountBox.x + amountBox.width).toBeLessThanOrEqual(removeBox.x)
    expect(removeBox.x + removeBox.width).toBeLessThanOrEqual(width)
    expect(await page.locator('main').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
    await remove.click()
    await expect(page.getByRole('menuitem', { name: '删除…', exact: true })).toBeVisible()
    await page.keyboard.press('Escape')
    await note.click()
    await expect(page.getByRole('dialog', { name: '编辑交易', exact: true })).toBeVisible()
    await expect(page.getByLabel('备注', { exact: true })).toHaveValue(remark)
  })
}

test('home distinguishes near-limit warnings and prioritizes actual overspending', async ({ page }) => {
  let alerts = [{ name: '居住', percentage: 0 }, { name: '购物', percentage: 32 }]
  await page.route('**/api/v1/budgets/summary', route => route.fulfill({
    json: { code: 0, data: {
      total_amount: 10000, total_spent: 8100, percentage: 81,
      daily_available: 100, days_remaining: 19, over_budget_categories: alerts,
    } },
  }))
  await page.reload()
  await expect(page.getByText('购物超支', { exact: true })).toBeVisible()
  await expect(page.getByText('居住超支', { exact: true })).toHaveCount(0)
  alerts = [{ name: '居住', percentage: 0 }]
  await page.getByRole('button', { name: '刷新首页数据', exact: true }).click()
  await expect(page.getByText('居住接近上限', { exact: true })).toBeVisible()
  await expect(page.getByText('居住超支', { exact: true })).toHaveCount(0)
})

for (const width of [320, 390, 1440]) {
  test(`transaction search leaves the title and filter readable at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    await page.goto('/#/transactions')
    await page.getByRole('searchbox', { name: '搜索', exact: true }).fill('手机套餐')
    const heading = page.getByRole('heading', { name: '账单明细', exact: true })
    await expect.poll(async () => (await heading.boundingBox())!.height).toBeLessThanOrEqual(30)
    const trigger = page.getByRole('button', { name: '全部类型', exact: true })
    await expect(trigger).toHaveAccessibleName('全部类型')
    expect((await trigger.boundingBox())!.height).toBeGreaterThanOrEqual(44)
    if (width >= 768) await expect(trigger.locator('span')).toBeVisible()
    await trigger.click()
    await page.getByLabel('开始日期', { exact: true }).fill('2026-10-01')
    await page.getByLabel('结束日期', { exact: true }).fill('2026-10-31')
    for (const control of [
      page.getByLabel('开始日期', { exact: true }),
      page.getByLabel('结束日期', { exact: true }),
      page.getByRole('button', { name: '重置', exact: true }),
    ]) {
      const bounds = (await control.boundingBox())!
      expect(bounds.x).toBeGreaterThanOrEqual(0)
      expect(bounds.x + bounds.width).toBeLessThanOrEqual(width)
    }
    await page.getByRole('button', { name: '重置', exact: true }).click()
    await expect(page.getByLabel('开始日期', { exact: true })).toHaveValue('')
    await expect(page.getByLabel('结束日期', { exact: true })).toHaveValue('')
    expect(await page.locator('main').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  })
}

for (const width of [390, 1440]) {
  test(`page navigation starts at the new page top at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    await page.route(/\/api\/v1\/transactions(?:\?|$)/, route => route.fulfill({
      json: { code: 0, data: {
        list: Array.from({ length: 20 }, (_, i) => ({
          id: `scroll-${i}`, type: 'expense', amount: 10,
          account_id: 'scroll-cash', category_id: 'scroll-food',
          transaction_date: '2026-10-14T12:00:00+08:00', remark: `模拟采购${i}`, source: 'manual',
          account: { id: 'scroll-cash', name: '模拟钱包', type: 'cash' },
          category: { id: 'scroll-food', name: '餐饮', icon: 'wallet' },
        })), total: 20, page: 1, page_size: 20,
      } },
    }))
    await page.goto('/#/transactions')
    await expect(page.getByText('模拟采购0', { exact: true })).toBeVisible()
    await page.locator('main').evaluate(el => el.scrollTo(0, 500))
    expect(await page.locator('main').evaluate(el => el.scrollTop)).toBeGreaterThan(200)
    await page.getByRole('button', { name: '统计', exact: true }).click()
    await expect(page.getByRole('heading', { name: '统计分析', exact: true })).toBeVisible()
    await expect.poll(() => page.locator('main').evaluate(el => el.scrollTop)).toBe(0)
    const summary = page.getByText('本月总支出', { exact: true })
    const bounds = (await summary.boundingBox())!
    expect(bounds.y).toBeGreaterThan(80)
    expect(bounds.y).toBeLessThan(250)
  })

  test(`sparse statistics span the chart and keep focused values visible at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    const days = ['2026-10-10', '2026-10-14', '2026-10-18', '2026-10-19']
    await page.route('**/api/v1/statistics/trend*', route => route.fulfill({
      json: { code: 0, data: {
        items: days.map((date, i) => ({ date, income: i === 0 ? 15000 : 0, expense: i === 1 ? 4000 : 10, balance: 0 })),
        total_income: 15000, total_expense: 4030,
      } },
    }))
    await page.goto('/#/statistics')
    const chart = page.locator('.statistics-chart-card')
    const firstDay = chart.getByText('1', { exact: true })
    const lastDay = chart.getByText('22', { exact: true })
    await expect(lastDay).toBeVisible()
    const first = (await firstDay.boundingBox())!
    const last = (await lastDay.boundingBox())!
    expect(last.x - first.x).toBeGreaterThan((await chart.boundingBox())!.width * 0.5)
    const day = chart.getByRole('button', { name: /10月19日.*收入.*支出/ })
    await day.focus()
    const tooltip = chart.getByRole('tooltip').last()
    await expect(tooltip).toHaveCSS('opacity', '1')
    const tip = (await tooltip.boundingBox())!
    expect(tip.x).toBeGreaterThanOrEqual(0)
    expect(tip.x + tip.width).toBeLessThanOrEqual(width)
    expect(tip.y).toBeGreaterThan((await chart.boundingBox())!.y)
    await page.screenshot({ path: test.info().outputPath(`sparse-trend-${width}.png`), animations: 'disabled' })
    await page.setViewportSize({ width: 320, height: 844 })
    await expect.poll(async () => {
      const visible = (await chart.locator('.statistics-trend-plot').boundingBox())!
      const resized = (await tooltip.boundingBox())!
      return resized.x + resized.width - visible.x - visible.width
    }).toBeLessThanOrEqual(0.01)
  })
}

test('category ranking orders the displayed amounts without changing the total', async ({ page }) => {
  await page.route('**/api/v1/statistics/categories*', route => route.fulfill({
    json: { code: 0, data: { total: 1300, items: [
      { category_id: 'food', category_name: '模拟餐饮', icon: 'wallet', color: '#00aa88', amount: 300, percentage: 23.1, count: 3 },
      { category_id: 'housing', category_name: '模拟居住', icon: 'home', color: '#ee6688', amount: 900, percentage: 69.2, count: 1 },
      { category_id: 'travel', category_name: '模拟交通', icon: 'car', color: '#4488ee', amount: 100, percentage: 7.7, count: 2 },
    ] } },
  }))
  await page.goto('/#/statistics')
  const housing = page.getByText('模拟居住', { exact: true })
  const food = page.getByText('模拟餐饮', { exact: true })
  const travel = page.getByText('模拟交通', { exact: true })
  await expect(travel).toBeVisible()
  expect((await housing.boundingBox())!.y).toBeLessThan((await food.boundingBox())!.y)
  expect((await food.boundingBox())!.y).toBeLessThan((await travel.boundingBox())!.y)
  await expect(page.getByText('共 ¥1,300.00', { exact: true })).toBeVisible()
  await page.getByText('环形图', { exact: true }).click()
  await expect(page.getByText('¥1,300.00', { exact: true })).toBeVisible()
})

test('narrow date filters leave room for the complete date and native picker', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 844 })
  await page.goto('/#/transactions')
  await page.getByRole('button', { name: '全部类型', exact: true }).click()
  await page.getByLabel('开始日期', { exact: true }).fill('2026-10-01')
  await page.getByLabel('结束日期', { exact: true }).fill('2026-10-31')
  for (const label of ['开始日期', '结束日期']) {
    const room = await page.getByLabel(label, { exact: true }).evaluate(element => {
      const style = getComputedStyle(element)
      const canvas = document.createElement('canvas')
      const context = canvas.getContext('2d')!
      context.font = `${style.fontSize} ${style.fontFamily}`
      return {
        available: element.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight),
        needed: context.measureText('2026/10/31').width + 24,
      }
    })
    expect(room.available).toBeGreaterThanOrEqual(room.needed)
  }
})

test('dense trend values stay inside the chart visible area', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 844 })
  await page.route('**/api/v1/statistics/trend*', route => route.fulfill({
    json: { code: 0, data: {
      items: Array.from({ length: 31 }, (_, i) => ({
        date: `2026-10-${String(i + 1).padStart(2, '0')}`,
        income: (i + 1) * 100, expense: i + 1, balance: (i + 1) * 99,
      })),
      total_income: 49600, total_expense: 496,
    } },
  }))
  await page.goto('/#/statistics')
  const chart = page.locator('.statistics-chart-card')
  for (const [label, value] of [[/^10月8日，收入/, '收入 ¥800.00'], [/^10月16日，收入/, '收入 ¥1,600.00']] as const) {
    await chart.getByRole('button', { name: label }).focus()
    const tip = chart.getByRole('tooltip').filter({ hasText: value })
    await expect(tip).toHaveCSS('opacity', '1')
    const visibleArea = (await chart.locator('.statistics-trend-plot').boundingBox())!
    const bounds = (await tip.boundingBox())!
    expect(bounds.x).toBeGreaterThanOrEqual(visibleArea.x)
    expect(bounds.x + bounds.width).toBeLessThanOrEqual(visibleArea.x + visibleArea.width)
  }
})

test.describe('touch statistics values', () => {
  test.use({ hasTouch: true })

  test('tapping a trend day reveals its values without hover or programmatic focus', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 })
    await page.route('**/api/v1/statistics/trend*', route => route.fulfill({
      json: { code: 0, data: {
        items: [{ date: '2026-10-10', income: 321.09, expense: 87.65, balance: 233.44 }],
        total_income: 321.09, total_expense: 87.65,
      } },
    }))
    await page.goto('/#/statistics')
    const chart = page.locator('.statistics-chart-card')
    await chart.getByRole('button', { name: /^10月10日，收入/ }).tap()
    const tip = chart.getByRole('tooltip')
    await expect(tip).toHaveCSS('opacity', '1')
    await expect(tip).toContainText('收入 ¥321.09')
    await expect(tip).toContainText('支出 ¥87.65')
    await page.screenshot({ path: test.info().outputPath('touch-trend.png'), animations: 'disabled' })
  })
})
