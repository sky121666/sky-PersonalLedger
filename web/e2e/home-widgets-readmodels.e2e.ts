import { selectWidgetAccount } from './widgetGallery'
import { expect, test, type Page } from '@playwright/test'
import dayjs from 'dayjs'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

async function login(page: Page) {
  const status = await page.request.get('/api/v1/auth/status')
  expect(status.ok()).toBeTruthy()
  if (!(await status.json()).data?.initialized) {
    expect((await page.request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

const account = {
  id: 'widget-cash', name: '合成现金', type: 'cash', icon: 'wallet', color: '#007AFF',
  initial_balance: 1000, current_balance: 1000, total_paid: 0, is_archived: false, sort_order: 0,
}
const month = dayjs().format('YYYY-MM')
const transaction = {
  id: 'widget-transfer', type: 'transfer', amount: 100, account_id: account.id, to_account_id: 'widget-bank',
  category_id: null, transaction_date: `${month}-20T10:00:00+08:00`, remark: '合成转账', images: '', tags: '',
  source: 'manual', recurring_id: null, account: { id: account.id, name: account.name },
}

async function mockHome(page: Page) {
  await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
    list: [account], total_assets: 1000, total_liabilities: 0, net_assets: 1000,
  } } }))
  await page.route(/\/api\/v1\/statistics\/overview(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
    income: 500, expense: 300, balance: 200, income_change: 0, expense_change: 0, daily_average: 10, transaction_count: 1,
  } } }))
  await page.route(/\/api\/v1\/transactions(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
    list: [transaction], total: 1, page: 1, page_size: 20,
  } } }))
  await page.route('**/api/v1/debt/summary', route => route.fulfill({ json: { code: 0, data: {
    total_debt: 75, total_paid: 25, total_principal: 100, progress: 25, active_loans: 1,
    paid_off_loans: 0, next_payment_day: 22, next_payment_name: '合成房贷', days_until_next: 4,
  } } }))
  await page.route('**/api/v1/budgets/summary', route => route.fulfill({ json: { code: 0, data: {
    total_amount: 100, total_spent: 130, percentage: 130, daily_available: -2, days_remaining: 10,
    over_budget_categories: [{ name: '餐饮', percentage: 130 }],
  } } }))
  await page.route('**/api/v1/lendings/summary', route => route.fulfill({ json: { code: 0, data: {
    total_lend_out: 0, total_borrow_in: 0, active_lend_out: 0, active_borrow_in: 0,
    settled_lend_out: 0, settled_borrow_in: 0, total_receivable: 0, total_payable: 0, net_lending: 0,
  } } }))
  await page.route(/\/api\/v1\/family\/summary(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
    month, total_expense: 0, members: [],
  } } }))
  await page.route(/\/api\/v1\/ai\/reports(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: [] } }))
}

for (const populated of [false, true]) {
  test(`summary card group survives breakpoints, navigation and independent saved sizes (${populated ? 'populated' : 'empty'})`, async ({ page }, testInfo) => {
    test.setTimeout(90_000)
    await page.emulateMedia({ reducedMotion: 'reduce' })
    const unexpectedRequests: string[] = []
    // These layout checks use browser fixtures only, including authentication.
    await page.route('**/api/v1/**', route => {
      const path = new URL(route.request().url()).pathname
      const data = path === '/api/v1/auth/status' ? { initialized: true }
        : path === '/api/v1/auth/refresh' ? { access_token: 'layout-fixture', expires_in: 3600 }
          : path === '/api/v1/auth/profile' ? { id: 1, username: 'layout-fixture' }
            : []
      if (!['/api/v1/auth/status', '/api/v1/auth/refresh', '/api/v1/auth/profile', '/api/v1/categories'].includes(path)) {
        unexpectedRequests.push(`${route.request().method()} ${path}`)
      }
      return route.fulfill({ json: { code: 0, data } })
    })
    await mockHome(page)
    if (populated) {
      await page.route('**/api/v1/lendings/summary', route => route.fulfill({ json: { code: 0, data: {
        total_lend_out: 2000, total_borrow_in: 800, active_lend_out: 1, active_borrow_in: 1,
        settled_lend_out: 0, settled_borrow_in: 0, total_receivable: 2000, total_payable: 800, net_lending: 1200,
      } } }))
      await page.route(/\/api\/v1\/family\/summary(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
        month, total_expense: 4515, members: [],
      } } }))
      await page.route(/\/api\/v1\/ai\/reports(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: [{
        id: 'group-report', report_type: 'monthly', status: 'completed',
        content_json: JSON.stringify({ summary: '本月餐饮支出为 9,999.99，建议核对分类。'.repeat(16) }),
        snapshot_json: '{}', period_start: `${month}-01`, period_end: `${month}-28`,
        provider_id: 'synthetic', provider_name: '合成提供商', model: 'synthetic', prompt_version: '1',
        created_at: `${month}-21`, updated_at: `${month}-21`,
      }] } }))
    }
    await page.setViewportSize({ width: 1440, height: 900 })
    await page.goto('/#/')
    const grid = page.getByRole('region', { name: '首页小组件' })
    const titles = ['借贷往来', 'AI 分析', '家庭支出']
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    for (const title of titles) {
      await gallery.getByRole('button', { name: `预览${title}`, exact: true }).click()
      await gallery.getByRole('button', { name: '小', exact: true }).click()
      await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
    }
    await page.keyboard.press('Escape')
    await page.getByRole('button', { name: '完成编辑', exact: true }).click()
    await page.reload()

    const widths = [320, 375, 390, 430, 600, 767, 768, 800, 880, 920, 1024, 1280, 1440, 1643, 1920]
    const geometries: unknown[] = []
    for (const navigation of ['top', 'rail', 'expanded'] as const) {
      await page.setViewportSize({ width: 1440, height: 900 })
      if (navigation === 'rail') await page.getByRole('button', { name: '切换到侧栏导航', exact: true }).click()
      if (navigation === 'expanded') await page.getByRole('button', { name: '展开侧边栏', exact: true }).click()
      for (const width of widths) {
        await page.setViewportSize({ width, height: 900 })
        const expectedColumns = async () => grid.evaluate(element => element.clientWidth < 400 ? 1 : element.clientWidth < 688 ? 2 : 4)
        await expect.poll(async () => grid.evaluate(element => getComputedStyle(element).gridTemplateColumns.split(' ').length)).toBe(await expectedColumns())
        const measure = () => grid.evaluate(element => {
          const bounds = element.getBoundingClientRect()
          const cards = Array.from(element.querySelectorAll<HTMLElement>('[data-widget-id]')).map(cell => {
            const r = cell.getBoundingClientRect()
            const article = cell.querySelector<HTMLElement>('article')!
            return { id: cell.dataset.widgetId, x: r.x, y: r.y, width: r.width, height: r.height, overflow: article.scrollWidth - article.clientWidth }
          })
          return { width: bounds.width, cards, pageOverflow: document.documentElement.scrollWidth - innerWidth }
        })
        await expect.poll(async () => {
          const { width: gridWidth, cards } = await measure()
          const group = cards.filter(card => ['lending', 'ai', 'family'].includes(card.id!))
          return group.every(card => Math.abs(card.width - (width < 768 ? gridWidth : (gridWidth - 16) / 2)) < 1)
        }).toBe(true)
        const result = await measure()
        const group = result.cards.filter(card => ['lending', 'ai', 'family'].includes(card.id!))
        expect(result.pageOverflow).toBeLessThanOrEqual(1)
        for (const card of result.cards) {
          expect(card.overflow, `${navigation} ${width}px ${card.id}`).toBeLessThanOrEqual(1)
          for (const other of result.cards.filter(other => other.id !== card.id)) {
            const overlaps = Math.min(card.x + card.width, other.x + other.width) - Math.max(card.x, other.x) > 1
              && Math.min(card.y + card.height, other.y + other.height) - Math.max(card.y, other.y) > 1
            expect(overlaps, `${navigation} ${width}px ${card.id}/${other.id}`).toBe(false)
          }
        }
        if (width < 768) {
          expect(group[1]!.y - group[0]!.y - group[0]!.height).toBeCloseTo(16, 0)
        } else {
          expect(group[0]!.y).toBeCloseTo(group[1]!.y, 0)
          expect(group[1]!.x - group[0]!.x - group[0]!.width).toBeCloseTo(16, 0)
        }
        expect(group[2]!.y - group[1]!.y - group[1]!.height).toBeCloseTo(16, 0)
        geometries.push({ navigation, viewportWidth: width, ...result })
      }
    }

    for (const width of [800, 430]) {
      await page.setViewportSize({ width, height: 900 })
      await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
      for (const title of titles) {
        await grid.getByRole('button', { name: `${title}选项`, exact: true }).click()
        const menu = page.getByRole('region', { name: `${title}选项菜单`, exact: true })
        await menu.getByLabel(`${title}尺寸`, { exact: true }).selectOption('medium')
        await page.keyboard.press('Escape')
      }
      await page.getByRole('button', { name: '完成编辑', exact: true }).click()
      await page.reload()
      for (const title of titles) await expect(grid.getByRole('article', { name: title, exact: true })).toHaveClass(/home-widget-medium/)
      await page.setViewportSize({ width: width === 800 ? 430 : 800, height: 900 })
      for (const title of titles) await expect(grid.getByRole('article', { name: title, exact: true })).toHaveClass(/home-widget-small/)
      await page.setViewportSize({ width, height: 900 })
      await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
      for (const title of titles) {
        await grid.getByRole('button', { name: `${title}选项`, exact: true }).click()
        await page.getByRole('region', { name: `${title}选项菜单`, exact: true }).getByLabel(`${title}尺寸`, { exact: true }).selectOption('small')
        await page.keyboard.press('Escape')
      }
      await page.getByRole('button', { name: '完成编辑', exact: true }).click()
      await page.reload()
      for (const title of titles) await expect(grid.getByRole('article', { name: title, exact: true })).toHaveClass(/home-widget-small/)
      await grid.getByRole('article', { name: '借贷往来', exact: true }).scrollIntoViewIfNeeded()
      await page.screenshot({ path: testInfo.outputPath(`summary-group-${width}.png`) })
    }
    expect(unexpectedRequests).toEqual([])
    await testInfo.attach('summary-group-geometries', { body: JSON.stringify(geometries, null, 2), contentType: 'application/json' })
  })
}

for (const width of [320, 390, 1440]) {
  test(`small AI card clamps long summaries and preserves size and privacy at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page)
    const summary = '本月餐饮支出为 9,999.99，建议核对分类。'.repeat(16)
    await page.route(/\/api\/v1\/ai\/reports(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: [{
      id: 'small-report', report_type: 'monthly', status: 'completed', content_json: JSON.stringify({ summary }),
      snapshot_json: '{}', period_start: `${month}-01`, period_end: `${month}-28`,
      provider_id: 'synthetic', provider_name: '合成提供商', model: 'synthetic', prompt_version: '1',
      created_at: `${month}-21`, updated_at: `${month}-21`,
    }] } }))
    await login(page)
    const writes: string[] = []
    page.on('request', request => { if (/\/api\/v1\/(?!auth\/)/.test(request.url()) && request.method() !== 'GET') writes.push(request.url()) })
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    await gallery.getByRole('button', { name: '预览AI 分析', exact: true }).click()
    await gallery.getByRole('button', { name: '小', exact: true }).click()
    await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
    await page.keyboard.press('Escape')
    await page.getByRole('button', { name: '完成编辑', exact: true }).click()
    await page.reload()
    const grid = page.getByRole('region', { name: '首页小组件' })
    const card = grid.getByRole('article', { name: 'AI 分析', exact: true })
    const copy = card.locator('.widget-copy')
    await expect(card).toHaveClass(/home-widget-small/)
    await expect(copy).toHaveText(summary)
    await expect(card).toContainText('已生成')
    const gridWidth = (await grid.boundingBox())!.width
    expect((await card.boundingBox())!.width).toBeCloseTo(width >= 768 ? (gridWidth - 16) / 2 : gridWidth, 0)
    const compactHeight = (await copy.boundingBox())!.height
    expect(compactHeight).toBeLessThanOrEqual(60)
    expect(await copy.evaluate(el => el.scrollHeight)).toBeGreaterThan(compactHeight)
    expect(await card.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
    await page.getByRole('button', { name: '隐藏首页金额', exact: true }).click()
    await expect(copy).toHaveText('摘要已隐藏')
    await expect(card).not.toContainText('9,999.99')
    await page.getByRole('button', { name: '显示首页金额', exact: true }).click()
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await grid.getByRole('button', { name: 'AI 分析选项', exact: true }).click()
    await page.getByRole('region', { name: 'AI 分析选项菜单', exact: true }).getByLabel('AI 分析尺寸', { exact: true }).selectOption('medium')
    await page.keyboard.press('Escape')
    await page.getByRole('button', { name: '完成编辑', exact: true }).click()
    await page.reload()
    await expect(card).toHaveClass(/home-widget-medium/)
    await expect(copy).toHaveText(summary)
    expect((await card.boundingBox())!.width).toBeCloseTo(gridWidth, 0)
    expect((await copy.boundingBox())!.height).toBeGreaterThan(compactHeight)
    expect(writes).toEqual([])
  })

  test(`small lending card preserves both balances and saved size at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page)
    await page.route('**/api/v1/lendings/summary', route => route.fulfill({ json: { code: 0, data: {
      total_lend_out: 2000, total_borrow_in: 800, active_lend_out: 1, active_borrow_in: 1,
      settled_lend_out: 0, settled_borrow_in: 0, total_receivable: 2000, total_payable: 800, net_lending: 1200,
    } } }))
    await login(page)
    const writes: string[] = []
    page.on('request', request => { if (/\/api\/v1\/(?!auth\/)/.test(request.url()) && request.method() !== 'GET') writes.push(request.url()) })
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    await gallery.getByRole('button', { name: '预览借贷往来', exact: true }).click()
    await gallery.getByRole('button', { name: '小', exact: true }).click()
    await expect(gallery.getByRole('button', { name: '小', exact: true })).toHaveAttribute('aria-pressed', 'true')
    await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
    await page.keyboard.press('Escape')
    await page.getByRole('button', { name: '完成编辑', exact: true }).click()
    await page.reload()
    const grid = page.getByRole('region', { name: '首页小组件' })
    const card = grid.getByRole('article', { name: '借贷往来', exact: true })
    await expect(card).toHaveClass(/home-widget-small/)
    await expect(card).toContainText('2,000.00')
    await expect(card).toContainText('800.00')
    await expect(card.locator('.lending-panels > div').first()).toContainText('应收')
    await expect(card.locator('.lending-panels > div').last()).toContainText('应付')
    const gridWidth = (await grid.boundingBox())!.width
    expect((await card.boundingBox())!.width).toBeCloseTo(width >= 768 ? (gridWidth - 16) / 2 : gridWidth, 0)
    expect(await card.evaluate(el => el.scrollHeight - el.clientHeight)).toBeLessThanOrEqual(1)
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await grid.getByRole('button', { name: '借贷往来选项', exact: true }).click()
    const menu = page.getByRole('region', { name: '借贷往来选项菜单', exact: true })
    await menu.getByLabel('借贷往来尺寸', { exact: true }).selectOption('medium')
    await page.keyboard.press('Escape')
    await page.getByRole('button', { name: '完成编辑', exact: true }).click()
    await page.reload()
    await expect(card).toHaveClass(/home-widget-medium/)
    expect((await card.boundingBox())!.width).toBeCloseTo(gridWidth, 0)
    expect(writes).toEqual([])
  })

  test(`widget editing waits for confirmed preferences at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page)
    let releaseProfile!: () => void
    const profileGate = new Promise<void>(resolve => { releaseProfile = resolve })
    await page.route('**/api/v1/auth/profile', async route => {
      await profileGate
      await route.fulfill({ json: { code: 0, data: { id: 501, username: 'delayed-profile-fixture' } } })
    })
    try {
      await login(page)
      const edit = page.getByRole('button', { name: '编辑小组件', exact: true })
      await expect(edit).toBeVisible()
      await expect(edit).toBeDisabled()
      await expect(page.getByRole('toolbar', { name: '首页布局编辑' })).toHaveCount(0)
      releaseProfile()
      await expect(edit).toBeEnabled()
      await edit.click()
      await expect(page.getByRole('toolbar', { name: '首页布局编辑' })).toBeVisible()
      await page.getByRole('button', { name: '添加小组件', exact: true }).click()
      await expect(page.getByRole('dialog', { name: '组件画廊' })).toBeVisible()
    } finally {
      releaseProfile()
    }
  })

  test(`account picker searches long lists and preserves gallery keyboard context at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page)
    const accounts = Array.from({ length: 160 }, (_, i) => ({ ...account, id: `cash-${i}`, name: `备用现金 ${i}` }))
    accounts.push({ ...account, id: 'card', name: '旅行备用卡', type: 'credit', current_balance: -200 })
    accounts.push({ ...account, id: 'bank', name: '旅行备用卡', type: 'bank_card', current_balance: 800 })
    await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
      list: accounts, total_assets: 160800, total_liabilities: 200, net_assets: 160600,
    } } }))
    await login(page)
    const writes: string[] = []
    page.on('request', request => { if (request.url().includes('/api/v1/') && request.method() !== 'GET') writes.push(request.url()) })
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    const categories = gallery.getByRole('group', { name: '组件分类' })
    await categories.getByRole('button', { name: '账户', exact: true }).click()
    await expect(gallery.getByRole('button', { name: '预览本月预算', exact: true })).toHaveCount(0)
    await gallery.getByRole('button', { name: '预览指定账户', exact: true }).click()
    const trigger = gallery.getByRole('button', { name: '组件关联账户', exact: true })
    await expect(gallery.getByRole('button', { name: '添加到首页', exact: true })).toBeDisabled()
    await trigger.click()
    const search = gallery.getByRole('combobox', { name: '搜索账户', exact: true })
    await expect(search).toBeFocused()
    const options = gallery.getByRole('listbox', { name: '可选账户' })
    await expect(options.getByRole('option')).toHaveCount(162)
    expect((await options.boundingBox())!.height).toBeLessThanOrEqual(320)
    await search.fill(' 不存在 ')
    await expect(gallery.getByRole('status')).toContainText('没有匹配的账户')
    await search.fill(' 旅行 ')
    await expect(options.getByRole('option')).toHaveCount(2)
    await expect(options.getByRole('group', { name: '银行卡与储蓄' })).toContainText('800.00')
    await expect(options.getByRole('group', { name: '信用与贷款' })).toContainText('-200.00')
    await search.press('ArrowDown')
    await search.press('Enter')
    await expect(trigger).toContainText('旅行备用卡')
    await expect(trigger).toContainText('银行卡')
    await expect(trigger).toBeFocused()
    await trigger.click()
    await search.press('Escape')
    await expect(search).toHaveCount(0)
    await expect(gallery).toBeVisible()
    await expect(trigger).toBeFocused()
    await trigger.click()
    await gallery.locator('.gallery-preview-heading').getByRole('heading', { name: '指定账户', exact: true }).click()
    await expect(search).toHaveCount(0)
    await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
    await expect(gallery.getByRole('button', { name: '定位已有组件', exact: true })).toBeEnabled()
    await page.keyboard.press('Escape')
    const grid = page.getByRole('region', { name: '首页小组件' })
    await expect(grid.getByRole('article', { name: '指定账户', exact: true })).toContainText('银行卡 · 旅行备用卡')
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
    expect(writes).toEqual([])
    expect(await page.locator('body').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  })

  test(`empty financial cards stay compact without hiding real unattributed expenses at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page)
    await page.route(/\/api\/v1\/family\/summary(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
      month, total_expense: 4515, members: [],
    } } }))
    await login(page)
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    for (const title of ['借贷往来', '家庭支出', 'AI 分析']) {
      await gallery.getByRole('button', { name: `预览${title}`, exact: true }).click()
      if (title === '借贷往来' || title === 'AI 分析') await gallery.getByRole('button', { name: '中', exact: true }).click()
      await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
    }
    await page.keyboard.press('Escape')
    const grid = page.getByRole('region', { name: '首页小组件' })
    const ai = grid.getByRole('article', { name: 'AI 分析', exact: true })
    const lending = grid.getByRole('article', { name: '借贷往来', exact: true })
    const family = grid.getByRole('article', { name: '家庭支出', exact: true })
    await expect(ai).toContainText('还没有报告')
    await expect(lending).toContainText('暂无未结清借贷')
    expect((await ai.boundingBox())!.height).toBeLessThan(140)
    expect((await lending.boundingBox())!.height).toBeLessThan(140)
    await expect(family).toContainText('4,515.00')
    await expect(family).not.toContainText('0人')
    await expect(family).toContainText('未归属')
    for (const card of [ai, lending, family]) {
      expect(await card.evaluate(el => el.scrollHeight - el.clientHeight)).toBeLessThanOrEqual(1)
    }
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
  })
}

test('account picker respects hidden amounts', async ({ page }) => {
  await mockHome(page)
  await login(page)
  await page.getByRole('button', { name: '隐藏首页金额', exact: true }).click()
  await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
  await page.getByRole('button', { name: '添加小组件', exact: true }).click()
  const gallery = page.getByRole('dialog', { name: '组件画廊' })
  await gallery.getByRole('button', { name: '预览指定账户', exact: true }).click()
  await gallery.getByRole('button', { name: '组件关联账户', exact: true }).click()
  const options = gallery.getByRole('listbox', { name: '可选账户' })
  await expect(options).not.toContainText('1,000.00')
  await expect(options).toContainText('****')
  await page.keyboard.press('Escape')
  await page.keyboard.press('Escape')
  await page.getByRole('button', { name: '取消编辑', exact: true }).click()
})

for (const condition of ['empty', 'failed'] as const) {
  test(`account picker blocks additions when accounts are ${condition}`, async ({ page }) => {
    await mockHome(page)
    await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => condition === 'failed'
      ? route.fulfill({ status: 503, json: { code: 500, message: '合成账户读取失败' } })
      : route.fulfill({ json: { code: 0, data: { list: [], total_assets: 0, total_liabilities: 0, net_assets: 0 } } }))
    await login(page)
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    await gallery.getByRole('button', { name: '预览指定账户', exact: true }).click()
    await expect(gallery.getByRole('button', { name: '添加到首页', exact: true })).toBeDisabled()
    if (condition === 'failed') {
      await expect(gallery.getByRole('button', { name: '组件关联账户', exact: true })).toBeDisabled()
      await expect(gallery.getByRole('status')).toContainText('账户加载失败')
    } else {
      await gallery.getByRole('button', { name: '组件关联账户', exact: true }).click()
      await expect(gallery.getByRole('status')).toContainText('暂无可选账户')
    }
  })
}

for (const width of [1440, 1920]) {
  test(`home keeps its original centered 768px container at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 1000 })
    await mockHome(page)
    await page.route(/\/api\/v1\/statistics\/overview(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
      income: 15860, expense: 4515, balance: 11345, income_change: 0, expense_change: 0, daily_average: 150, transaction_count: 30,
    } } }))
    await login(page)
    const content = page.locator('.home-content')
    await expect(content).toHaveCSS('max-width', '768px')
    const bounds = (await content.boundingBox())!
    const main = (await page.getByRole('main').boundingBox())!
    expect(bounds.width).toBeCloseTo(768, 0)
    expect(Math.abs(bounds.x + bounds.width / 2 - main.x - main.width / 2)).toBeLessThan(1)
    const assetsContent = page.getByRole('article', { name: '净资产', exact: true }).locator('.home-widget-body')
    await expect.poll(() => assetsContent.evaluate(element => element.scrollHeight - element.clientHeight)).toBeLessThanOrEqual(1)
    const flow = page.getByRole('article', { name: '本月收支', exact: true })
    await expect(flow).toContainText('+15,860.00')
    const lines = await flow.locator('.flow-grid strong').evaluateAll(items => items.map(item => {
      const range = document.createRange()
      range.selectNodeContents(item)
      return range.getClientRects().length
    }))
    expect(lines).toEqual([1, 1, 1])
    const accountsContent = page.getByRole('article', { name: '我的账户', exact: true }).locator('.home-widget-body')
    await expect.poll(() => accountsContent.evaluate(element => element.scrollHeight - element.clientHeight)).toBeLessThanOrEqual(1)
    await page.getByRole('button', { name: '切换到侧栏导航', exact: true }).click()
    await expect.poll(async () => {
      const box = (await content.boundingBox())!
      const area = (await page.getByRole('main').boundingBox())!
      return Math.abs(box.x + box.width / 2 - area.x - area.width / 2)
    }).toBeLessThan(1)
    await expect(content).toHaveCSS('max-width', '768px')
  })
}

for (const width of [390, 1440]) {
  test(`reading layout uses full rows and content height without nested scrolling at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page)
    await page.route(/\/api\/v1\/transactions(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
      list: Array.from({ length: 12 }, (_, index) => ({ ...transaction, id: `reading-card-${index}` })),
      total: 12, page: 1, page_size: 20,
    } } }))
    await login(page)
    const grid = page.getByRole('region', { name: '首页小组件' })
    const transactions = grid.getByRole('article', { name: '最近交易', exact: true })
    await expect(transactions.locator('.transaction-row')).toHaveCount(5)
    const gridWidth = (await grid.boundingBox())!.width
    for (const title of ['净资产', '本月收支', '我的账户', '最近交易', ...(width < 768 ? ['还款提醒'] : [])]) {
      const card = grid.getByRole('article', { name: title, exact: true })
      expect((await card.boundingBox())!.width, title).toBeCloseTo(gridWidth, 0)
    }
    const assets = (await grid.getByRole('article', { name: '净资产', exact: true }).boundingBox())!
    const flow = (await grid.getByRole('article', { name: '本月收支', exact: true }).boundingBox())!
    expect(flow.height).toBeLessThan(assets.height)
    for (const body of await grid.locator('.home-widget-body').all()) {
      expect(await body.evaluate(el => el.scrollHeight - el.clientHeight)).toBeLessThanOrEqual(1)
    }
    const geometry = await transactions.boundingBox()
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    expect((await transactions.boundingBox())!.height).toBeCloseTo(geometry!.height, 0)
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
  })

  test(`gallery shares the home width projection and uses content height at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page); await login(page)
    const assets = page.getByRole('article', { name: '净资产', exact: true })
    const homeWidth = (await assets.boundingBox())!.width
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    await expect(gallery).toHaveCSS('transform', 'none')
    await gallery.getByRole('button', { name: '预览净资产', exact: true }).click()
    const preview = gallery.locator('.widget-preview-surface')
    await expect.poll(async () => (await preview.boundingBox())!.width).toBeCloseTo(homeWidth, 0)
    const assetHeight = (await preview.boundingBox())!.height
    await gallery.getByRole('button', { name: '预览本月收支', exact: true }).click()
    expect((await preview.boundingBox())!.height).toBeLessThan(assetHeight)
    if (width < 768) {
      expect(await gallery.locator('.widget-gallery-list').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
      expect(await gallery.locator('.widget-preview-canvas').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
    }
    await gallery.getByRole('button', { name: '预览最近交易', exact: true }).click()
    await gallery.getByRole('button', { name: '大', exact: true }).click()
    await expect(gallery.locator('.transaction-row')).toHaveCount(5)
    await gallery.getByRole('button', { name: '预览收支日历', exact: true }).click()
    await expect(gallery.locator('.calendar-day')).toHaveCount(42)
    await expect(gallery.getByRole('heading', { name: dayjs().format('YYYY年M月'), exact: true })).toBeVisible()
    await page.keyboard.press('Escape')
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
  })

  test(`removing a widget keeps focus on a surviving edit control at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page); await login(page)
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    const grid = page.getByRole('region', { name: '首页小组件' })
    if (width < 768) {
      await grid.getByRole('button', { name: '本月预算选项', exact: true }).click()
      await page.getByRole('region', { name: '本月预算选项菜单', exact: true })
        .getByRole('button', { name: '移除本月预算（两端）', exact: true }).click()
    } else {
      await grid.getByRole('button', { name: '移除本月预算（两端）', exact: true }).click()
    }
    await expect(grid.getByRole('button', { name: '还款提醒选项', exact: true })).toBeFocused()
    await page.getByRole('button', { name: '撤销布局操作', exact: true }).click()
    await expect(grid.getByRole('heading', { name: '本月预算', exact: true })).toBeVisible()
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
  })

  test(`drag snapshot preserves a horizontally scrolled account strip at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page)
    await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
      list: Array.from({ length: 6 }, (_, index) => ({ ...account, id: `ghost-account-${index}`, name: `合成账户${index + 1}` })),
      total_assets: 6000, total_liabilities: 0, net_assets: 6000,
    } } }))
    await login(page)
    const strip = page.getByRole('region', { name: '账户概览', exact: true })
    await strip.focus()
    await strip.press('End')
    await expect.poll(() => strip.evaluate(el => Math.abs(el.scrollWidth - el.clientWidth - el.scrollLeft))).toBeLessThan(1)
    const left = await strip.evaluate(el => el.scrollLeft)
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    const handle = page.getByRole('button', { name: '拖动我的账户', exact: true })
    await handle.hover()
    const bounds = (await handle.boundingBox())!
    await page.mouse.move(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2)
    await page.mouse.down()
    await expect(page.locator('.widget-drag-preview .account-tiles')).toHaveJSProperty('scrollLeft', left)
    await page.keyboard.press('Escape')
    await page.mouse.up()
    await expect(page.locator('.widget-drag-preview')).toHaveCount(0)
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
  })

  test(`original home card hierarchy survives custom layout editing at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page); await login(page)
    const grid = page.getByRole('region', { name: '首页小组件' })
    const assets = grid.getByRole('article', { name: '净资产', exact: true })
    const budget = grid.getByRole('article', { name: '本月预算', exact: true })
    for (const dark of [false, true]) {
      await page.locator('html').evaluate((el, value) => el.classList.toggle('dark', value), dark)
      await expect(assets).toHaveCSS('color', 'rgb(255, 255, 255)')
      await expect(assets).toHaveCSS('background-image', /linear-gradient/)
      await expect(assets.getByText('总资产', { exact: true })).toBeVisible()
      await expect(assets.getByText('总负债', { exact: true })).toBeVisible()
      await expect(budget).toHaveCSS('background-image', /linear-gradient/)
      const flow = grid.getByRole('article', { name: '本月收支', exact: true })
      const positions = await flow.locator('.flow-grid > div').evaluateAll(items => items.map(item => item.getBoundingClientRect().top))
      expect(new Set(positions).size).toBe(1)
      await expect(grid.getByRole('article', { name: '我的账户', exact: true }).getByText('现金', { exact: true })).toBeVisible()
      const icon = grid.getByRole('article', { name: '最近交易', exact: true }).locator('.transaction-icon').first()
      await expect(icon).toHaveCSS('border-radius', '16px')
    }
    const before = await assets.boundingBox()
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    const after = await assets.boundingBox()
    expect(after?.height).toBeCloseTo(before!.height, 0)
    await expect(assets).toHaveCSS('background-image', /linear-gradient/)
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    await gallery.getByRole('button', { name: '预览净资产', exact: true }).click()
    await expect(gallery.getByRole('article', { name: '净资产', exact: true })).toHaveCSS('background-image', /linear-gradient/)
    await page.keyboard.press('Escape')
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
  })

  test(`home widgets expose real read models at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page)
    await login(page)
    await expect(page.getByRole('heading', { name: '净资产', exact: true })).toBeVisible()
    await expect(page.getByRole('heading', { name: '本月收支', exact: true })).toBeVisible()
    await expect(page.getByRole('heading', { name: '本月预算', exact: true })).toBeVisible()
    await expect(page.getByRole('heading', { name: '还款提醒', exact: true })).toBeVisible()
    await expect(page.getByRole('region', { name: '首页小组件' }).getByRole('heading', { name: '最近交易', exact: true })).toBeVisible()
    await expect(page.getByRole('heading', { name: '我的账户', exact: true })).toBeVisible()
    await expect(page.getByText('1,000.00', { exact: true }).first()).toBeVisible()
    await expect(page.getByText('130%', { exact: true }).first()).toBeVisible()
    await expect(page.getByText('还款提醒，不含账户分期', { exact: true }).first()).toBeVisible()
    const transactionsCard = page.getByRole('article', { name: '最近交易' })
    await expect(transactionsCard.getByText('合成转账', { exact: true })).toBeVisible()
    await expect(transactionsCard.getByText('转账', { exact: true })).toBeVisible()
    await expect(transactionsCard.locator('.amount-neutral')).toHaveText('100.00')
    expect(await page.locator('main').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
    await page.screenshot({ path: test.info().outputPath(`home-widgets-${width}.png`), fullPage: true, animations: 'disabled' })
  })
}

test('home widgets preserve navigation and transaction edit protection', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await mockHome(page)
  await login(page)
  await page.getByRole('article').filter({ has: page.getByRole('heading', { name: '还款提醒', exact: true }) }).getByRole('button', { name: '查看详情', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/reminders\?view=reminders$/)
  await page.goto('/#/')
  await page.getByRole('button', { name: '明细', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/transactions$/)
})

for (const width of [320, 390, 768, 1280, 1440]) {
  test(`long amounts and 200 percent text stay inside widgets at ${width}px`, async ({ page }, info) => {
    await page.setViewportSize({ width, height: 900 })
    await mockHome(page)
    const longAmount = 123456789012.34
    await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
      list: [{ ...account, name: '用于验证超长账户名称仍然可以辨识的合成账户', current_balance: longAmount }],
      total_assets: longAmount, total_liabilities: 0, net_assets: longAmount,
    } } }))
    await page.route(/\/api\/v1\/statistics\/overview(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
      income: longAmount, expense: longAmount, balance: -longAmount,
      income_change: 0, expense_change: 0, daily_average: 10, transaction_count: 1,
    } } }))
    await login(page)
    const grid = page.getByRole('region', { name: '首页小组件' })
    await expect(grid.getByRole('article', { name: '净资产', exact: true })).toContainText('123,456,789,012.34')
    // Freeze computed text sizes before applying 2x: no deviceScaleFactor or inherited double scaling.
    await grid.evaluate(root => {
      const sizes = Array.from(root.querySelectorAll<HTMLElement>('*')).map(el => ({
        el, size: parseFloat(getComputedStyle(el).fontSize),
      }))
      for (const { el, size } of sizes) el.style.fontSize = `${size * 2}px`
    })
    await expect.poll(() => grid.locator('article').evaluateAll(cards => cards.filter(card =>
      card.scrollWidth > card.clientWidth + 1,
    ).map(card => card.getAttribute('aria-label')))).toEqual([])
    await expect.poll(() => page.getByRole('main').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
    const overlaps = await grid.locator('.home-widget-header').evaluateAll(headers => headers.filter(header => {
      const title = header.querySelector('h3')!.getBoundingClientRect()
      const action = header.querySelector('.widget-link')!.getBoundingClientRect()
      return Math.min(title.right, action.right) - Math.max(title.left, action.left) > 1
        && Math.min(title.bottom, action.bottom) - Math.max(title.top, action.top) > 1
    }).map(header => header.textContent))
    expect(overlaps).toEqual([])
    for (const dark of [false, true]) {
      await page.locator('html').evaluate((el, dark) => el.classList.toggle('dark', dark), dark)
      await expect(page.locator('.ledger-workspace')).toHaveCSS('background-color', dark ? 'rgb(11, 11, 13)' : 'rgb(242, 242, 247)')
      await expect(page.getByRole('main').locator(':scope > div').last()).toHaveCSS('background-color', dark ? 'rgb(11, 11, 13)' : 'rgb(242, 242, 247)')
      await page.screenshot({ path: info.outputPath(`widget-text-200-${width}-${dark ? 'dark' : 'light'}.png`), fullPage: true, animations: 'disabled' })
    }
  })
}

test('widget detail actions have 44px touch targets', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 900 })
  await mockHome(page); await login(page)
  const sizes = await page.getByRole('region', { name: '首页小组件' })
    .getByRole('button', { name: '查看详情', exact: true }).evaluateAll(buttons => buttons.map(button => {
      const rect = button.getBoundingClientRect()
      return { width: rect.width, height: rect.height }
    }))
  expect(sizes).toHaveLength(6)
  for (const size of sizes) {
    expect(size.width).toBeGreaterThanOrEqual(44)
    expect(size.height).toBeGreaterThanOrEqual(44)
  }
})

test('original account strip supports keyboard scrolling to offscreen accounts', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 900 })
  await mockHome(page)
  await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
    list: Array.from({ length: 6 }, (_, index) => ({ ...account, id: `keyboard-account-${index}`, name: `合成账户${index + 1}` })),
    total_assets: 6000, total_liabilities: 0, net_assets: 6000,
  } } }))
  await login(page)
  const strip = page.getByRole('region', { name: '账户概览', exact: true })
  await strip.focus()
  await expect(strip).toBeFocused()
  await strip.press('ArrowRight')
  await expect.poll(() => strip.evaluate(element => element.scrollLeft)).toBeGreaterThan(0)
  await strip.press('End')
  await expect.poll(() => strip.evaluate(element => Math.abs(element.scrollWidth - element.clientWidth - element.scrollLeft))).toBeLessThan(1)
  await expect(strip.getByText('合成账户6', { exact: true })).toBeInViewport()
  const rightEdge = await strip.evaluate(element => element.scrollLeft)
  await strip.press('ArrowLeft')
  await expect.poll(() => strip.evaluate(element => element.scrollLeft)).toBeLessThan(rightEdge)
  await strip.press('Home')
  await expect.poll(() => strip.evaluate(element => element.scrollLeft)).toBe(0)
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await strip.press('ArrowRight')
  await expect.poll(() => strip.evaluate(element => element.scrollLeft)).toBeGreaterThan(0)
  await strip.press('Home')
  await expect.poll(() => strip.evaluate(element => element.scrollLeft)).toBe(0)
})

test('records local home and gallery responsiveness without duplicate preview reads', async ({ page }, info) => {
  const errors: string[] = []
  const reads: string[] = []
  const writes: string[] = []
  page.on('pageerror', error => errors.push(error.message))
  await mockHome(page); await login(page)
  const startupReads: string[] = []
  page.on('request', request => {
    if (request.method() === 'GET' && /\/api\/v1\/(?:accounts|statistics\/overview|transactions|debt\/summary|budgets\/summary)(?:\?|$)/.test(request.url())) {
      startupReads.push(new URL(request.url()).pathname)
    }
  })
  await page.reload()
  await expect(page.getByRole('article', { name: '净资产', exact: true })).toContainText('1,000.00')
  const localHomeReadyMilliseconds = await page.evaluate(() => performance.now())
  expect(startupReads.sort()).toEqual([
    '/api/v1/accounts', '/api/v1/budgets/summary', '/api/v1/debt/summary',
    '/api/v1/statistics/overview', '/api/v1/transactions',
  ])
  await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
  page.on('request', request => {
    if (!request.url().includes('/api/v1/')) return
    if (request.method() === 'GET') reads.push(new URL(request.url()).pathname)
    else writes.push(request.url())
  })
  const measurements: number[] = []
  for (let i = 0; i < 3; i++) {
    const started = await page.evaluate(() => performance.now())
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    await expect(gallery).toBeVisible()
    measurements.push(await page.evaluate(started => performance.now() - started, started))
    for (const name of ['净资产', '本月预算', '指定账户', '收支日历']) {
      await gallery.getByRole('button', { name: `预览${name}`, exact: true }).click()
    }
    await page.keyboard.press('Escape')
  }
  expect(reads).toEqual([])
  expect(writes).toEqual([])
  expect(errors).toEqual([])
  await info.attach('local-interaction-metrics', { contentType: 'application/json', body: Buffer.from(JSON.stringify({
    browser: info.project.name, galleryOpenMilliseconds: measurements, localHomeReadyMilliseconds, startupReads,
    note: 'Local production build; Playwright action latency included. Not field INP or physical-device results.',
    readRequestsDuringPreviews: reads, writeRequests: writes,
  }, null, 2)) })
})

test('missing total budget and zero spending are distinct from an outage', async ({ page }) => {
  await mockHome(page); await login(page)
  let total = 0
  await page.route('**/api/v1/budgets/summary', route => route.fulfill({ json: { code: 0, data: {
    total_amount: total, total_spent: 0, percentage: 0, daily_available: 0, days_remaining: 10, over_budget_categories: [],
  } } }))
  const card = page.getByRole('article', { name: '本月预算', exact: true })
  await page.getByRole('button', { name: '刷新首页数据', exact: true }).click()
  await expect(card).toContainText('尚未设置总预算')
  total = 1000
  await page.getByRole('button', { name: '刷新首页数据', exact: true }).click()
  await expect(card).toContainText('已用 0.00')
  await expect(card).toContainText('剩余 1,000.00')
  await page.route('**/api/v1/budgets/summary', route => route.fulfill({ status: 503, json: { code: 500, message: 'synthetic outage' } }))
  await page.getByRole('button', { name: '刷新首页数据', exact: true }).click()
  await expect(card).toContainText('预算加载失败')
  await expect(card).not.toContainText('尚未设置总预算')
})

test('dark widget metadata and detail links remain readable', async ({ page }) => {
  await mockHome(page); await login(page)
  await page.locator('html').evaluate(el => el.classList.add('dark'))
  const colors = await page.getByRole('article', { name: '净资产', exact: true })
    .locator('.widget-split, .widget-link').evaluateAll(elements => elements.map(el => getComputedStyle(el).color))
  const luminance = (rgb: number[]) => rgb.map(v => v / 255).map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4)
    .reduce((total, value, i) => total + value * [.2126, .7152, .0722][i]!, 0)
  const background = luminance([28, 28, 30])
  for (const color of colors) {
    const foreground = luminance(color.match(/[\d.]+/g)!.slice(0, 3).map(Number))
    expect((foreground + .05) / (background + .05)).toBeGreaterThanOrEqual(4.5)
  }
})

test('large budget and medium account share on-demand reads and respect amount privacy', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 }); await mockHome(page)
  let budgetReads = 0
  let accountReads = 0
  await page.route(/\/api\/v1\/budgets(?:\?|$)/, route => {
    budgetReads++
    return route.fulfill({ json: { code: 0, data: { total_budget: null, member_budgets: [], category_budgets: [
      { id: 'food', category_name: '合成餐饮预算', amount: 2000, spent: 1234.56 },
    ] } } })
  })
  await page.route(/\/api\/v1\/transactions\?.*account_id=/, route => {
    expect(new URL(route.request().url()).searchParams.get('account_id')).toBe(account.id)
    accountReads++
    return route.fulfill({ json: { code: 0, data: { list: [{ ...transaction, amount: 321.09 }], total: 1 } } })
  })
  await login(page)
  const grid = page.getByRole('region', { name: '首页小组件' })
  await expect(grid.getByRole('article', { name: '净资产', exact: true })).toContainText('1,000.00')
  expect([budgetReads, accountReads]).toEqual([0, 0])
  await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
  await grid.getByRole('button', { name: '本月预算选项', exact: true }).click()
  await page.getByRole('region', { name: '本月预算选项菜单', exact: true }).getByLabel('本月预算尺寸', { exact: true }).selectOption('large')
  await page.getByRole('button', { name: '添加小组件', exact: true }).click()
  const gallery = page.getByRole('dialog', { name: '组件画廊' })
  await gallery.getByRole('button', { name: '预览指定账户', exact: true }).click()
  await gallery.getByRole('button', { name: '中', exact: true }).click()
  await selectWidgetAccount(gallery, account.id)
  await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
  await page.keyboard.press('Escape')
  await page.getByRole('button', { name: '完成编辑', exact: true }).click()
  await expect(grid.getByRole('article', { name: '本月预算', exact: true })).toContainText('合成餐饮预算')
  await expect(grid.getByRole('article', { name: '指定账户', exact: true })).toContainText('321.09')
  expect([budgetReads, accountReads]).toEqual([1, 1])
  await page.getByRole('button', { name: '隐藏首页金额', exact: true }).click()
  await expect(grid.getByText('1,234.56 / 2,000.00', { exact: true })).toHaveCount(0)
  await expect(grid.getByRole('article', { name: '指定账户', exact: true })).not.toContainText('321.09')
})

test('reminder and account outages never masquerade as empty or deleted resources', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 }); await mockHome(page); await login(page)
  await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
  await page.getByRole('button', { name: '添加小组件', exact: true }).click()
  const gallery = page.getByRole('dialog', { name: '组件画廊' })
  await gallery.getByRole('button', { name: '预览指定账户', exact: true }).click()
  await selectWidgetAccount(gallery, account.id)
  await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
  await page.keyboard.press('Escape')
  await page.getByRole('button', { name: '完成编辑', exact: true }).click()
  await page.route('**/api/v1/debt/summary', route => route.fulfill({ status: 503, json: { code: 500, message: 'synthetic outage' } }))
  await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ status: 503, json: { code: 500, message: 'synthetic outage' } }))
  await page.getByRole('button', { name: '刷新首页数据', exact: true }).click()
  const grid = page.getByRole('region', { name: '首页小组件' })
  await expect(grid.getByRole('article', { name: '还款提醒', exact: true })).toContainText('还款提醒加载失败')
  const selectedAccount = grid.getByRole('article', { name: '指定账户', exact: true })
  await expect(selectedAccount).toContainText('账户资产加载失败')
  await expect(selectedAccount).not.toContainText('账户不可用')
  await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
    list: [], total_assets: 0, total_liabilities: 0, net_assets: 0,
  } } }))
  await page.getByRole('button', { name: '刷新首页数据', exact: true }).click()
  await expect(selectedAccount).toContainText('账户不可用')
})
