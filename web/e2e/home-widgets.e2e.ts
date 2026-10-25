import { selectWidgetAccount } from './widgetGallery'
import { expect, test, type Page } from '@playwright/test'
import dayjs from 'dayjs'
import { createDefaultHomeLayout, type HomeLayout } from '../src/components/home/model'

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

async function mockHome(page: Page, accounts = [account]) {
  const totalAssets = accounts.reduce((sum, item) => sum + item.current_balance, 0)
  await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({ json: { code: 0, data: {
    list: accounts, total_assets: totalAssets, total_liabilities: 0, net_assets: totalAssets,
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


for (const width of [390, 1440]) {
  test(`widget drafts save, cancel and undo at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 }); await mockHome(page); await login(page)
    const grid = page.getByRole('region', { name: '首页小组件' })
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await removeBudget(page)
    await expect(grid.getByRole('heading', { name: '本月预算', exact: true })).toHaveCount(0)
    await page.getByRole('button', { name: '撤销布局操作' }).click()
    await expect(grid.getByRole('heading', { name: '本月预算', exact: true })).toBeVisible()
    await (await widgetOptions(page)).getByRole('button', { name: '本月预算：下移' }).click()
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    await removeBudget(page)
    await page.getByRole('button', { name: '完成编辑', exact: true }).click()
    await page.reload()
    await expect(grid.getByRole('heading', { name: '本月预算', exact: true })).toHaveCount(0)
  })
}

test('gallery has every approved widget and adds to draft only without finance writes', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 }); await mockHome(page); await login(page)
  const writes: string[] = []
  page.on('request', r => { if (/\/api\/v1\//.test(r.url()) && r.method() !== 'GET') writes.push(r.url()) })
  await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
  await page.getByRole('button', { name: '添加小组件', exact: true }).click()
  const gallery = page.getByRole('dialog', { name: '组件画廊' })
  await expect(gallery).toBeVisible()
  for (const title of ['净资产','本月收支','本月预算','还款提醒','最近交易','我的账户','指定账户','收支日历','借贷往来','家庭支出','AI 分析']) {
    await gallery.getByRole('button', { name: `预览${title}`, exact: true }).click()
    await expect(gallery.getByRole('region', { name: '组件尺寸预览' })).toBeVisible()
  }
  await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
  await page.keyboard.press('Escape')
  await expect(gallery).toHaveCount(0)
  await expect(page.getByRole('button', { name: '添加小组件', exact: true })).toBeFocused()
  await expect(page.getByRole('region', { name: '首页小组件' }).getByRole('heading', { name: 'AI 分析' })).toBeVisible()
  await page.getByRole('button', { name: '取消编辑', exact: true }).click()
  expect(writes).toEqual([])
})

async function removeBudget(page: Page) {
  const direct = gridOf(page).getByRole('button', { name: '移除本月预算（两端）', exact: true })
  if (await direct.isVisible()) await direct.click()
  else {
    const menu = await widgetOptions(page)
    await menu.getByRole('button', { name: '移除本月预算（两端）', exact: true }).click()
  }
}

const gridOf = (page: Page) => page.getByRole('region', { name: '首页小组件' })
const ids = (page: Page) => gridOf(page).locator('[data-widget-id]').evaluateAll(els => els.map(el => el.getAttribute('data-widget-id')))
async function edit(page: Page, width = 1440, accounts = [account]) { await page.setViewportSize({ width, height: 900 }); await mockHome(page, accounts); await login(page); await page.getByRole('button', { name: '编辑小组件', exact: true }).click() }
async function widgetOptions(page: Page, label = '本月预算') {
  const menu = page.getByRole('region', { name: `${label}选项菜单`, exact: true })
  const trigger = gridOf(page).getByRole('button', { name: `${label}选项`, exact: true })
  if ((await trigger.getAttribute('aria-expanded')) !== 'true') await trigger.click()
  await expect(menu).toBeVisible()
  return menu
}

for (const width of [390, 1440]) {
  test(`editing preserves card geometry and exposes controls on demand at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 }); await mockHome(page); await login(page)
    const grid = gridOf(page)
    const geometry = () => grid.locator('[data-widget-id]').evaluateAll(elements => elements.map(element => {
      const rect = element.getBoundingClientRect()
      return { id: element.getAttribute('data-widget-id'), width: rect.width, height: rect.height }
    }))
    const before = await geometry()
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    expect(await geometry()).toEqual(before)
    await expect(grid.getByRole('button', { name: '本月预算：下移' })).toBeHidden()
    const trigger = grid.getByRole('button', { name: '本月预算选项', exact: true })
    await trigger.click()
    const menu = page.getByRole('region', { name: '本月预算选项菜单', exact: true })
    await expect(menu).toBeVisible()
    const bounds = (await menu.boundingBox())!
    expect(bounds.x).toBeGreaterThanOrEqual(0)
    expect(bounds.x + bounds.width).toBeLessThanOrEqual(width)
    await menu.getByLabel('本月预算尺寸', { exact: true }).selectOption('large')
    await page.keyboard.press('Escape')
    await expect(menu).toHaveCount(0)
    await expect(trigger).toBeFocused()
    await trigger.click()
    await menu.getByRole('button', { name: '本月预算：下移' }).click()
    await expect(menu).toHaveCount(0)
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
    expect(await geometry()).toEqual(before)
  })
}

test('gallery filtering never offers an unrelated component and identifies added widgets', async ({ page }) => {
  await edit(page)
  await page.getByRole('button', { name: '添加小组件', exact: true }).click()
  const gallery = page.getByRole('dialog', { name: '组件画廊' })
  await gallery.getByLabel('搜索小组件', { exact: true }).fill('日历')
  await expect(gallery.locator('.gallery-preview-heading').getByRole('heading', { name: '收支日历', exact: true })).toBeVisible()
  await gallery.getByLabel('搜索小组件', { exact: true }).fill('不存在的组件')
  await expect(gallery.getByRole('button', { name: '添加到首页', exact: true })).toHaveCount(0)
  await expect(gallery.getByRole('button', { name: '定位已有组件', exact: true })).toHaveCount(0)
  await gallery.getByLabel('搜索小组件', { exact: true }).fill('预算')
  await expect(gallery.getByRole('button', { name: '预览本月预算', exact: true })).toContainText('已添加')
})

test('dark editor surfaces keep local theme styles without recoloring the document', async ({ page }) => {
  await edit(page)
  await page.getByRole('button', { name: '切换到深色模式', exact: true }).click()
  const rootColor = await page.locator('html').evaluate(element => getComputedStyle(element).backgroundColor)
  const handle = gridOf(page).getByRole('button', { name: '拖动净资产', exact: true })
  const luminance = (color: string) => {
    const rgb = color.match(/[\d.]+/g)!.slice(0, 3).map(Number)
    return rgb.reduce((sum, value) => sum + value, 0) / (3 * 255)
  }
  expect(luminance(await handle.evaluate(element => getComputedStyle(element, '::before').backgroundColor))).toBeLessThan(0.3)
  const menu = await widgetOptions(page)
  expect(luminance(await menu.evaluate(element => getComputedStyle(element).backgroundColor))).toBeLessThan(0.3)
  await page.keyboard.press('Escape')
  await page.getByRole('button', { name: '添加小组件', exact: true }).click()
  const gallery = page.getByRole('dialog', { name: '组件画廊' })
  expect(luminance(await gallery.evaluate(element => getComputedStyle(element).backgroundColor))).toBeLessThan(0.3)
  await expect(page.locator('html')).toHaveCSS('background-color', rootColor)
})

test('dragging feedback follows the pointer and Escape restores the card without reordering', async ({ page }) => {
  await edit(page)
  const original = await ids(page)
  const cell = gridOf(page).locator('[data-widget-id="net-assets"]')
  const renderer = cell.locator('.widget-renderer')
  const before = (await renderer.boundingBox())!
  const handle = (await cell.getByRole('button', { name: '拖动净资产', exact: true }).boundingBox())!
  await page.mouse.move(handle.x + 22, handle.y + 22)
  await page.mouse.down()
  await page.mouse.move(handle.x + 102, handle.y + 72, { steps: 5 })
  const ghost = page.locator('.widget-drag-preview')
  await expect.poll(async () => (await ghost.boundingBox())!.x - before.x).toBeGreaterThan(50)
  await expect.poll(async () => (await ghost.boundingBox())!.y - before.y).toBeGreaterThan(30)
  expect((await renderer.boundingBox())!.x).toBe(before.x)
  expect(await ids(page)).toEqual(original)
  await page.keyboard.press('Escape')
  await page.mouse.up()
  await expect(ghost).toHaveCount(0)
  await expect(renderer).toHaveCSS('transform', 'none')
  expect(await ids(page)).toEqual(original)
})

test('edge dragging never grows the underlying scroll extent', async ({ page }) => {
  await edit(page)
  await page.setViewportSize({ width: 1440, height: 600 })
  const main = page.getByRole('main')
  expect(await main.evaluate(element => element.scrollHeight - element.clientHeight)).toBeGreaterThan(40)
  const originalHeight = await main.evaluate(element => element.scrollHeight)
  const handle = (await gridOf(page).getByRole('button', { name: '拖动净资产', exact: true }).boundingBox())!
  const bounds = (await main.boundingBox())!
  await page.mouse.move(handle.x + 22, handle.y + 22); await page.mouse.down()
  await page.mouse.move(bounds.x + bounds.width / 2, bounds.y + bounds.height - 8)
  await expect.poll(() => main.evaluate(element => element.scrollTop)).toBeGreaterThan(20)
  const height = await main.evaluate(element => element.scrollHeight)
  expect(height).toBe(originalHeight)
  await page.keyboard.press('Escape'); await page.mouse.up()
  await expect(page.locator('.widget-drag-preview')).toHaveCount(0)
})

for (const width of [320, 390]) {
  test(`mobile editing menus and added badges remain usable at ${width}px`, async ({ page }) => {
    await edit(page, width)
    await page.locator('.widget-editor-toolbar summary').click()
    const reset = page.getByRole('button', { name: '恢复桌面与手机默认布局', exact: true })
    const bounds = (await reset.boundingBox())!
    expect(bounds.x).toBeGreaterThanOrEqual(0)
    expect(bounds.x + bounds.width).toBeLessThanOrEqual(width)
    await page.locator('.widget-editor-toolbar summary').click()
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    await expect(gallery.getByRole('button', { name: '预览本月预算', exact: true }).getByText('已添加')).toBeVisible()
    await gallery.getByRole('button', { name: '定位已有组件', exact: true }).click()
    await expect(gridOf(page).getByRole('button', { name: '拖动本月预算', exact: true })).toBeFocused()
  })
}

test('desktop and mobile orders and sizes are independent and a valid empty home persists', async ({ page }) => {
  await edit(page)
  await (await widgetOptions(page)).getByLabel('本月预算尺寸', { exact: true }).selectOption('large')
  await (await widgetOptions(page)).getByRole('button', { name: '本月预算：下移' }).click()
  const desktopOrder = await ids(page)
  await page.setViewportSize({ width: 390, height: 900 })
  await expect(gridOf(page).locator('[data-widget-id="budget"]')).toHaveAttribute('data-widget-size', 'small')
  await expect((await widgetOptions(page)).getByLabel('本月预算尺寸', { exact: true })).toHaveValue('small')
  expect(await ids(page)).toEqual(['net-assets','accounts','monthly-flow','budget','reminders','transactions'])
  await page.setViewportSize({ width: 1440, height: 900 })
  await expect.poll(() => ids(page)).toEqual(desktopOrder)
  while (await gridOf(page).getByRole('button', { name: /^移除/ }).count()) await gridOf(page).getByRole('button', { name: /^移除/ }).last().click()
  await page.getByRole('button', { name: '完成编辑', exact: true }).click(); await page.reload()
  await expect(gridOf(page).locator('[data-widget-id]')).toHaveCount(0)
  await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
  await page.locator('.widget-editor-toolbar summary').click()
  await page.getByRole('button', { name: '恢复桌面与手机默认布局' }).click()
  await expect(gridOf(page).locator('[data-widget-id]')).toHaveCount(6)
  await page.getByRole('button', { name: '撤销布局操作' }).click()
  await expect(gridOf(page).locator('[data-widget-id]')).toHaveCount(0)
})

test('pointer release reorders while Escape, blur, pointercancel and resize preserve order', async ({ page }) => {
  await edit(page)
  const original = await ids(page)
  const handle = gridOf(page).getByRole('button', { name: '拖动净资产', exact: true })
  async function start() { await handle.scrollIntoViewIfNeeded(); const a = (await handle.boundingBox())!; await page.mouse.move(a.x + 20, a.y + 20); await page.mouse.down() }
  await start()
  const target = (await gridOf(page).locator('[data-widget-id="accounts"]').boundingBox())!
  await page.mouse.move(target.x + 50, target.y + 30, { steps: 5 })
  await expect(gridOf(page).locator('.widget-drag-target')).toHaveAttribute('data-widget-id', 'accounts')
  await page.mouse.up()
  expect((await ids(page)).slice(0,2)).toEqual(['accounts','net-assets'])
  await page.getByRole('button', { name: '撤销布局操作' }).click()
  for (const reason of ['escape','blur','pointercancel','resize']) {
    await start()
    if (reason === 'escape') await page.keyboard.press('Escape')
    if (reason === 'blur') await page.evaluate(() => window.dispatchEvent(new Event('blur')))
    if (reason === 'pointercancel') await gridOf(page).dispatchEvent('pointercancel', { pointerId: 1 })
    if (reason === 'resize') await page.setViewportSize({ width: 390, height: 900 })
    await expect(gridOf(page).locator('.widget-drag-source')).toHaveCount(0)
    await page.mouse.up(); expect(await ids(page)).toEqual(original)
    await expect(page.getByRole('button', { name: '完成编辑' })).toBeVisible()
    await page.setViewportSize({ width: 1440, height: 900 })
  }
})

test('account widgets require a choice, reject duplicate content and show the selected account', async ({ page }) => {
  await edit(page)
  await page.getByRole('button', { name: '添加小组件', exact: true }).click()
  let gallery = page.getByRole('dialog', { name: '组件画廊' })
  await gallery.getByRole('button', { name: '预览指定账户' }).click()
  await expect(gallery.getByRole('button', { name: '添加到首页' })).toBeDisabled()
  await selectWidgetAccount(gallery, account.id)
  await gallery.getByRole('button', { name: '添加到首页' }).click()
  await expect(gallery.getByRole('button', { name: '定位已有组件' })).toBeVisible()
  await gallery.getByRole('button', { name: '定位已有组件' }).click()
  await expect(gridOf(page).locator(`[data-widget-id="account-${account.id}"]`)).toHaveCount(1)
  await page.getByRole('button', { name: '完成编辑' }).click()
  await expect(gridOf(page).getByRole('article', { name: '指定账户', exact: true }).getByText('现金 · 合成现金', { exact: true })).toBeVisible()
})

test('gallery modal focus, background lock and 320px layout survive reopening', async ({ page }, info) => {
  await edit(page, 320)
  const trigger = page.getByRole('button', { name: '添加小组件', exact: true })
  for (let i=0;i<2;i++) {
    await trigger.click(); const dialog = page.getByRole('dialog', { name: '组件画廊' })
    await expect(page.locator('dialog:modal')).toHaveCount(1)
    await expect(page.getByRole('main')).toHaveCSS('overflow-y','hidden')
    await expect(dialog.getByRole('button', { name: '关闭组件画廊' })).toBeFocused()
    const last = dialog.getByRole('button').last();await last.focus();await page.keyboard.press('Tab')
    await expect(dialog.getByRole('button',{name:'关闭组件画廊'})).toBeFocused()
    await page.keyboard.press('Shift+Tab');await expect(last).toBeFocused()
    const box = (await dialog.boundingBox())!; expect(box.x).toBeGreaterThanOrEqual(0); expect(box.x+box.width).toBeLessThanOrEqual(320)
    await page.screenshot({ path: info.outputPath('widget-gallery-mobile.png') })
    await page.keyboard.press('Escape'); await expect(dialog).toHaveCount(0); await expect(trigger).toBeFocused()
  }
  await expect(page.getByRole('main')).toHaveCSS('overflow-y','auto')
})

test('storage failure keeps the active draft', async ({ page }) => {
  await edit(page)
  await (await widgetOptions(page)).getByRole('button', { name: '本月预算：下移' }).click()
  await page.evaluate(() => { const set = Storage.prototype.setItem; Storage.prototype.setItem = function(k,v) { if(k.endsWith(':home')) throw Error('fixture quota'); return set.call(this,k,v) } })
  await page.getByRole('button', { name: '完成编辑' }).click()
  await expect(page.getByText('布局保存失败，草稿已保留，请重试。')).toBeVisible()
  await expect(page.getByRole('button', { name: '完成编辑' })).toBeVisible()
})

test('another tab cannot replace an active draft until explicit reload, and navigation changes preserve it', async ({ page, context }) => {
  await edit(page)
  await (await widgetOptions(page)).getByRole('button', { name: '本月预算：下移' }).click()
  const draft = await ids(page)
  await page.getByRole('button', { name: '切换到侧栏导航' }).click()
  expect(await ids(page)).toEqual(draft)
  const other = await context.newPage(); await mockHome(other); await other.goto('/#/')
  await other.getByRole('button', { name: '编辑小组件', exact: true }).click()
  await gridOf(other).getByRole('button', { name: '移除还款提醒（两端）' }).click()
  await other.getByRole('button', { name: '完成编辑' }).click()
  await page.getByRole('button', { name: '完成编辑' }).click()
  await expect(page.getByText('布局已在其他标签更新或版本不兼容，草稿已保留。')).toBeVisible()
  expect(await ids(page)).toEqual(draft)
  await page.getByRole('button', { name: '载入最新布局（放弃当前草稿）' }).click()
  await expect(gridOf(page).getByRole('heading', { name: '还款提醒' })).toHaveCount(0)
  await page.getByRole('button', { name: '完成编辑' }).click()
  await expect(page.getByRole('button', { name: '编辑小组件', exact: true })).toBeVisible()
})

test('keyboard ordering and pointer edge scrolling use the existing scroll container', async ({ page }, info) => {
  await edit(page)
  await page.setViewportSize({ width: 1440, height: 600 })
  const down = (await widgetOptions(page)).getByRole('button', { name: '本月预算：下移' })
  await down.focus(); await down.press('Enter')
  expect((await ids(page)).slice(3,5)).toEqual(['reminders','budget'])
  await page.getByRole('button', { name: '撤销布局操作' }).click()
  const main = page.getByRole('main')
  expect(await main.evaluate(element => element.scrollHeight - element.clientHeight)).toBeGreaterThan(40)
  await main.evaluate(el => { el.scrollTop=0 })
  const handle = gridOf(page).getByRole('button', { name: '拖动净资产', exact: true })
  const a=(await handle.boundingBox())!; const bounds=(await main.boundingBox())!
  await page.mouse.move(a.x+20,a.y+20);await page.mouse.down()
  await page.mouse.move(a.x+20,bounds.y+bounds.height-10)
  await expect.poll(() => main.evaluate(el => el.scrollTop)).toBeGreaterThan(20)
  await page.mouse.move(a.x+20,bounds.y-8)
  const samples = await main.evaluate(el => new Promise<number[]>(resolve => { const result:number[]=[]; function sample(){result.push(el.scrollTop);if(result.length===4)resolve(result);else requestAnimationFrame(sample)};requestAnimationFrame(sample) }))
  expect(Math.max(...samples)-Math.min(...samples)).toBe(0)
  await page.keyboard.press('Escape');await page.mouse.up()
  expect(await page.evaluate(() => document.documentElement.scrollTop)).toBe(0)
  await page.screenshot({ path: info.outputPath('widget-editor-desktop.png') })
})

const secondAccount = { ...account, id: 'widget-bank', name: '合成银行卡', type: 'bank_card', current_balance: 2000 }
const thirdAccount = { ...account, id: 'widget-third', name: '合成零钱', current_balance: 3000 }

async function expectAccountCard(page: Page, item: typeof account) {
  const card = gridOf(page).locator(`[data-widget-id="account-${item.id}"]`)
  await expect(card).toHaveCount(1)
  await expect(card.locator('.widget-meta')).toContainText(item.name)
  await expect(card.getByText(item.current_balance.toLocaleString('en-US', { minimumFractionDigits: 2 }), { exact: true })).toBeVisible()
}

for (const width of [390, 1440]) {
  test(`multiple configured account cards remain distinct after saving and reloading at ${width}px`, async ({ page }) => {
    await edit(page, width, [account, secondAccount])
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    await gallery.getByRole('button', { name: '预览指定账户' }).click()
    for (const item of [account, secondAccount]) {
      await selectWidgetAccount(gallery, item.id)
      await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
      await expect(gallery.getByRole('button', { name: '定位已有组件', exact: true })).toBeVisible()
    }
    await page.keyboard.press('Escape')
    await page.getByRole('button', { name: '完成编辑' }).click()
    await expect(page.getByRole('button', { name: '编辑小组件', exact: true })).toBeVisible()
    await page.reload()
    await expectAccountCard(page, account)
    await expectAccountCard(page, secondAccount)
    await expect(gridOf(page).locator('[data-widget-id^="account-"]')).toHaveCount(2)
  })

  test(`saved account card can be reconfigured with one undo without affecting its neighbor at ${width}px`, async ({ page }) => {
    // This journey starts from a saved layout; adding and persisting it is verified separately above.
    // Keep the default widgets and let the application read the normal preference contract.
    const layout = createDefaultHomeLayout()
    const widgets: HomeLayout['widgets'] = [account, secondAccount].map(item => ({
      id: `account-${item.id}`, kind: 'account', config: { accountId: item.id },
      sizes: { desktop: 'small', mobile: 'small' },
    }))
    layout.widgets.push(...widgets)
    for (const viewport of ['desktop', 'mobile'] as const) layout.orders[viewport].push(...widgets.map(widget => widget.id))
    const key = 'personal-ledger:workspace:%2Fapi%2Fv1:501:home'
    await page.route('**/api/v1/auth/profile', route => route.fulfill({ json: { code: 0, data: { id: 501 } } }))
    await page.addInitScript(({ key, layout }) => {
      if (!localStorage.getItem(key)) localStorage.setItem(key, JSON.stringify({ version: 1, revision: 'saved-accounts-fixture', value: layout }))
    }, { key, layout })
    await edit(page, width, [account, secondAccount, thirdAccount])
    const snapshot = () => gridOf(page).locator('[data-widget-id]').evaluateAll(elements => elements.map(element => ({
      id: element.getAttribute('data-widget-id'), size: element.getAttribute('data-widget-size'),
    })))
    const before = await snapshot()
    await expectAccountCard(page, account)
    await expectAccountCard(page, secondAccount)
    await (await widgetOptions(page, '指定账户 · 合成现金')).getByRole('button', { name: '配置指定账户 · 合成现金', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    await selectWidgetAccount(gallery, thirdAccount.id)
    await gallery.getByRole('button', { name: '更新账户组件', exact: true }).click()
    await expect(gallery).toHaveCount(0)
    await expect.poll(snapshot).toEqual(before.map(item => item.id === 'account-widget-cash' ? { ...item, id: 'account-widget-third' } : item))
    await expect(gridOf(page).locator('[data-widget-id="account-widget-cash"]')).toHaveCount(0)
    await expectAccountCard(page, thirdAccount)
    await expectAccountCard(page, secondAccount)
    await expect(gridOf(page).locator('[data-widget-id^="account-"]')).toHaveCount(2)
    await page.getByRole('button', { name: '撤销布局操作' }).click()
    await expect.poll(snapshot).toEqual(before)
    await expect(gridOf(page).locator('[data-widget-id="account-widget-third"]')).toHaveCount(0)
    await expectAccountCard(page, account)
    await expectAccountCard(page, secondAccount)
    await expect(page.getByRole('button', { name: '撤销布局操作' })).toBeDisabled()
  })
}

test('native touch outside a handle scrolls on Chromium; other engines use wheel scrolling', async ({ page, browserName }) => {
  await edit(page, 390)
  const main = page.getByRole('main')
  if (browserName !== 'chromium') {
    await main.hover()
    await page.mouse.wheel(0, 200)
  } else {
    const cdp = await page.context().newCDPSession(page)
    await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: true })
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 300, y: 730 }] })
    for (let y = 700; y >= 350; y -= 35) {
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 300, y }] })
    }
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
    await cdp.detach()
  }
  await expect.poll(() => main.evaluate(el => el.scrollTop)).toBeGreaterThan(20)
  expect(await page.evaluate(() => document.documentElement.scrollTop)).toBe(0)
})

test('native handle touch reorders on Chromium; other engines use the move menu', async ({ page, browserName }) => {
  // Use a fresh page: a compositor fling at a scroll boundary survives a programmatic scrollTop reset.
  await edit(page, 390)
  if (browserName !== 'chromium') {
    await (await widgetOptions(page)).getByRole('button', { name: '本月预算：下移' }).click()
    expect((await ids(page)).slice(3, 5)).toEqual(['reminders', 'budget'])
    return
  }
  const cdp = await page.context().newCDPSession(page)
  await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: true })
  const handle = (await gridOf(page).getByRole('button', { name: '拖动净资产', exact: true }).boundingBox())!
  const target = (await gridOf(page).locator('[data-widget-id="accounts"]').boundingBox())!
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: handle.x + 20, y: handle.y + 20 }] })
  await expect(gridOf(page).locator('.widget-drag-source')).toHaveCount(1)
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: target.x + 50, y: target.y + 30 }] })
  await expect(gridOf(page).locator('.widget-drag-target')).toHaveAttribute('data-widget-id', 'accounts')
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
  expect((await ids(page)).slice(0, 2)).toEqual(['accounts', 'net-assets'])
  await cdp.detach()
})

test('every approved renderer can be added, saved and read back without paid or ledger writes', async ({ page }) => {
  await edit(page)
  const prohibited:string[]=[]
  page.on('request',r=>{if(r.method()!=='GET' && /\/api\/v1\/(?:transactions|accounts|budgets|reminders|lendings|ai)/.test(r.url()))prohibited.push(r.url())})
  for(const title of ['指定账户','收支日历','借贷往来','家庭支出','AI 分析']){
    await page.getByRole('button',{name:'添加小组件',exact:true}).click()
    const gallery=page.getByRole('dialog',{name:'组件画廊'});await gallery.getByRole('button',{name:`预览${title}`,exact:true}).click()
    if(title==='指定账户')await selectWidgetAccount(gallery, account.id)
    if(title==='收支日历'){
      await page.route(/\/api\/v1\/statistics\/trend(?:\?|$)/,r=>r.fulfill({json:{code:0,data:{items:[],total_income:0,total_expense:0}}}))
      await expect(gallery.locator('.calendar-day')).toHaveCount(42)
    }
    await gallery.getByRole('button',{name:'添加到首页',exact:true}).click();await page.keyboard.press('Escape')
  }
  await expect(gridOf(page).locator('[data-widget-id]')).toHaveCount(11)
  await page.getByRole('button',{name:'完成编辑',exact:true}).click();await page.reload()
  await expect(gridOf(page).locator('[data-widget-id]')).toHaveCount(11)
  await expect(page.getByRole('button',{name:/天气|气温|降雨/})).toHaveCount(0)
  expect(prohibited).toEqual([])
})

for(const version of ['invalid','future']){
  test(`${version} home recovery is explicit and future data remains untouched`,async({page})=>{
    const key='personal-ledger:workspace:%2Fapi%2Fv1:501:home';const raw=version==='invalid'?'{broken':'{"version":99,"revision":"future","value":{}}'
    await page.route('**/api/v1/auth/profile',route=>route.fulfill({json:{code:0,data:{id:501}}}))
    await page.addInitScript(({key,raw})=>{if(!localStorage.getItem(key))localStorage.setItem(key,raw)},{key,raw})
    await edit(page)
    await page.locator('.widget-editor-toolbar summary').click();await page.getByRole('button',{name:'恢复桌面与手机默认布局'}).click()
    expect(await page.evaluate(key=>localStorage.getItem(key),key)).toBe(raw)
    await page.getByRole('button',{name:'完成编辑'}).click()
    if(version==='invalid'){
      await expect(page.getByRole('button',{name:'编辑小组件',exact:true})).toBeVisible()
      expect(await page.evaluate(key=>JSON.parse(localStorage.getItem(key)!).version,key)).toBe(1)
    }else{
      await expect(page.getByText('首页布局来自更高版本，原配置已保留，当前草稿不能保存。')).toBeVisible()
      expect(await page.evaluate(key=>localStorage.getItem(key),key)).toBe(raw)
    }
  })
}

test('amount privacy also hides optional AI report text',async({page})=>{
  await edit(page)
  const month = new Date().toISOString().slice(0,7)
  await page.route(/\/api\/v1\/ai\/reports(?:\?|$)/,route=>route.fulfill({json:{code:0,data:[{id:'privacy-report',status:'completed',content_json:'合成报告金额 9999.99',period_start:`${month}-01`,period_end:`${month}-28`,provider_name:'合成提供商'}]}}))
  await page.getByRole('button',{name:'添加小组件',exact:true}).click()
  const gallery=page.getByRole('dialog',{name:'组件画廊'});await gallery.getByRole('button',{name:'预览AI 分析',exact:true}).click();await gallery.getByRole('button',{name:'添加到首页',exact:true}).click();await page.keyboard.press('Escape')
  await page.getByRole('button',{name:'完成编辑',exact:true}).click()
  await page.getByRole('button',{name:'刷新首页数据'}).click()
  await expect(gridOf(page).getByText('合成报告金额 9999.99',{exact:true})).toBeVisible()
  await page.getByRole('button',{name:'隐藏首页金额'}).click()
  await expect(gridOf(page).getByText('合成报告金额 9999.99',{exact:true})).toHaveCount(0)
  await expect(gridOf(page).getByText('摘要已隐藏',{exact:true})).toBeVisible()
})

for (const width of [320,390,1440]) {
  test(`gallery preview matches actual home cell width at ${width}px`,async({page})=>{
    await edit(page,width)
    const expected=(await gridOf(page).locator('[data-widget-id="budget"]').boundingBox())!.width
    await page.getByRole('button',{name:'添加小组件',exact:true}).click()
    const gallery=page.getByRole('dialog',{name:'组件画廊'})
    await expect(gallery).toHaveCSS('transform', 'none')
    await expect.poll(async () => Math.abs((await gallery.locator('.widget-preview-surface').boundingBox())!.width - expected)).toBeLessThanOrEqual(1)
  })
}

test('home refresh reloads the enabled calendar month without business writes',async({page})=>{
  await page.setViewportSize({width:1280,height:900});await mockHome(page)
  let calls=0
  await page.route(/\/api\/v1\/statistics\/trend(?:\?|$)/,r=>{calls++;return r.fulfill({json:{code:0,data:{month,items:[]}}})})
  await login(page)
  await page.getByRole('button',{name:'编辑小组件',exact:true}).click()
  await page.getByRole('button',{name:'添加小组件',exact:true}).click()
  const gallery=page.getByRole('dialog',{name:'组件画廊'});await gallery.getByRole('button',{name:'预览收支日历'}).click();await gallery.getByRole('button',{name:'添加到首页',exact:true}).click();await page.keyboard.press('Escape')
  await page.getByRole('button',{name:'完成编辑',exact:true}).click();await expect.poll(()=>calls).toBe(1)
  await page.getByRole('button',{name:'刷新首页数据'}).click();await expect.poll(()=>calls).toBe(2)
})
