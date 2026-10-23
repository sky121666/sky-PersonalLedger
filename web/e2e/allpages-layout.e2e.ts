import { expect, test, type Locator } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.beforeAll(async ({ request }) => {
  const status = await request.get('/api/v1/auth/status')
  expect(status.ok()).toBeTruthy()
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

test.beforeEach(async ({ page }) => {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
})

async function fitsPhoneDialog(dialog: Locator) {
  await expect(dialog).toBeVisible()
  await expect.poll(async () => {
    const box = (await dialog.boundingBox())!
    return box.y >= 12 && box.y + box.height <= 568.5 && box.x >= 0 && box.x + box.width <= 320.5
  }).toBe(true)
  const footer = dialog.locator('footer')
  if (await footer.count()) {
    const box = (await footer.boundingBox())!
    expect(box.y).toBeGreaterThanOrEqual(0)
    expect(box.y + box.height).toBeLessThanOrEqual(568.5)
  }
}

test('settings counts all transactions rather than the current month', async ({ page }) => {
  await page.route('**/api/v1/statistics/overview*', route => route.fulfill({
    json: { code: 0, data: { transaction_count: 42 } },
  }))
  await page.route(/\/api\/v1\/transactions(?:\?|$)/, route => route.fulfill({
    json: { code: 0, data: { list: [], total: 176, page: 1, page_size: 1 } },
  }))
  await page.goto('/#/settings')
  await expect(page.getByText('累计记账', { exact: true }).locator('..')).toContainText('176')
})

for (const route of ['family', 'ai']) {
  test(`${route} refresh remains a single reachable line on narrow phones`, async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 568 })
    if (route === 'ai') {
      await page.route('**/api/v1/ai/reports*', r => r.fulfill({ json: { code: 0, data: [{
        id: 'layout-report', report_type: 'monthly', status: 'completed', period_start: '2026-10-01', period_end: '2026-10-20',
        content_json: JSON.stringify({ title: '隔离报告', summary: '仅用于布局验证' }), snapshot_json: '{}',
      }] } }))
    }
    await page.goto(`/#/${route}`)
    if (route === 'ai') await page.getByRole('button', { name: '报告操作', exact: true }).click()
    const refresh = page.getByRole(route === 'family' ? 'button' : 'menuitem', { name: route === 'family' ? '刷新家庭数据' : '刷新报告', exact: true })
    await expect(refresh).toBeVisible()
    const box = (await refresh.boundingBox())!
    expect(box.height).toBeLessThanOrEqual(48)
    expect(box.width).toBeGreaterThanOrEqual(route === 'family' ? 44 : 80)
    expect(box.x + box.width).toBeLessThanOrEqual(320)
    await refresh.click()
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
  })
}

for (const width of [320, 390, 768, 820, 900, 1440]) {
  test(`account names and actions remain readable at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    const name = '日常现金（模拟）'
    await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({
      json: { code: 0, data: {
        list: [{ id: 'layout-cash', name, type: 'cash', icon: 'wallet', color: '#34C759',
          initial_balance: 1800, current_balance: 1800, is_archived: false }],
        total_assets: 1800, total_liabilities: 0, net_assets: 1800,
      } },
    }))
    await page.goto('/#/accounts')
    const label = page.getByText(name, { exact: true })
    await expect(label).toBeVisible()
    expect(await label.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
    const archive = page.getByRole('button', { name: `归档账户 ${name}`, exact: true })
    // Firefox can report 44px as 43.999969px after card transforms.
    expect(Number((await archive.boundingBox())!.height.toFixed(2))).toBeGreaterThanOrEqual(44)
    await expect(archive.locator('..')).toHaveCSS('opacity', '1')
    const card = label.locator('xpath=ancestor::div[contains(@class, "card-premium")]')
    const bounds = (await card.boundingBox())!
    for (const action of await card.getByRole('button').all()) {
      const box = (await action.boundingBox())!
      expect(box.x).toBeGreaterThanOrEqual(bounds.x)
      expect(box.x + box.width).toBeLessThanOrEqual(bounds.x + bounds.width)
    }
    expect(await page.locator('main').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  })
}

for (const width of [390, 1440]) {
  test(`accounts without a configured color retain a card background at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    await page.emulateMedia({ colorScheme: 'light', reducedMotion: 'reduce' })
    await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({
      json: { code: 0, data: {
        list: [
          { id: 'no-color', name: '未配置颜色的账户', type: 'bank_card', color: '',
            initial_balance: 100, current_balance: 100, is_archived: false },
          { id: 'configured-color', name: '已配置颜色的账户', type: 'cash', color: '#34C759',
            initial_balance: 100, current_balance: 100, is_archived: false },
        ],
        total_assets: 200, total_liabilities: 0, net_assets: 200,
      } },
    }))
    await page.goto('/#/accounts')
    const missing = page.locator('.card-premium').filter({ hasText: '未配置颜色的账户' })
    const configured = page.locator('.card-premium').filter({ hasText: '已配置颜色的账户' })
    for (const theme of ['浅色', '深色']) {
      await page.goto('/#/appearance')
      await page.getByRole('button', { name: theme, exact: true }).click()
      await page.goto('/#/accounts')
      await expect(missing).toBeVisible()
      await expect(missing).not.toHaveCSS('background-image', 'none')
      await expect(configured).not.toHaveCSS('background-image', 'none')
      expect(await missing.evaluate(el => getComputedStyle(el).backgroundImage))
        .not.toBe(await configured.evaluate(el => getComputedStyle(el).backgroundImage))
      await page.screenshot({ path: test.info().outputPath(`account-colors-${width}-${theme}.png`), animations: 'disabled' })
    }
  })
}

test('category editor and expanded icons fit a small phone with reachable save', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 })
  await page.goto('/#/categories')
  await page.getByRole('button', { name: '添加分类', exact: true }).click()
  const dialog = page.getByRole('dialog', { name: '添加分类', exact: true })
  const name = page.getByPlaceholder('例如：餐饮、交通', { exact: true })
  await expect(name).toBeVisible()
  const bounds = (await dialog.boundingBox())!
  const input = (await name.boundingBox())!
  expect(input.x + input.width).toBeLessThanOrEqual(bounds.x + bounds.width - 16)
  await name.locator('..').getByRole('button').click()
  await fitsPhoneDialog(dialog)
  await dialog.getByRole('button', { name: '保存', exact: true }).scrollIntoViewIfNeeded()
  const save = (await dialog.getByRole('button', { name: '保存', exact: true }).boundingBox())!
  expect(save.y + save.height).toBeLessThanOrEqual(568)
  expect(await dialog.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
})

test('custom category actions are visible without hover on a phone', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 })
  await page.route(/\/api\/v1\/categories(?:\?|$)/, route => route.fulfill({
    json: { code: 0, data: { list: [
      { id: 'layout-category', name: '出行模拟', type: 'expense', icon: 'car', color: '#007AFF', is_system: false },
    ] } },
  }))
  await page.goto('/#/categories')
  const card = page.getByText('出行模拟', { exact: true }).locator('..')
  const edit = card.getByRole('button').first()
  await expect(edit.locator('..')).toHaveCSS('opacity', '1')
  expect((await edit.boundingBox())!.height).toBeGreaterThanOrEqual(44)
  await edit.click()
  await expect(page.getByRole('heading', { name: '编辑分类', exact: true })).toBeVisible()
})

test('debt type choices do not collapse into vertical text on a phone', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 })
  await page.goto('/#/reminders?view=reminders')
  await page.getByRole('button', { name: '添加提醒', exact: true }).click()
  const choice = page.getByRole('button', { name: '信用卡', exact: true })
  await expect(choice).toBeVisible()
  expect((await choice.locator('span').boundingBox())!.height).toBeLessThanOrEqual(20)
  expect((await choice.boundingBox())!.width).toBeGreaterThanOrEqual(64)
})

test('debt and lending actions stay visible and repayments fit a short screen', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 })
  await page.route('**/api/v1/reminders', route => route.fulfill({
    json: { code: 0, data: [{
      id: 'layout-debt', name: '模拟分期', loan_type: 'other', payment_day: 15,
      principal: 1000, current_balance: 900, total_paid: 100, is_enabled: true,
    }] },
  }))
  await page.goto('/#/reminders?view=reminders')
  const debt = page.locator('.group').filter({ hasText: '模拟分期' }).first()
  // The action row is independent from the always-visible repayment button.
  const actions = debt.locator('button[title="禁用提醒"]').locator('..')
  await expect(actions).toHaveCSS('opacity', '1')
  await debt.getByRole('button', { name: '+ 记录还款', exact: true }).click()
  const repayment = page.getByRole('dialog', { name: '记录还款', exact: true })
  await fitsPhoneDialog(repayment)
  await repayment.getByRole('button', { name: '取消', exact: true }).click()

  await page.route(/\/api\/v1\/lendings(?:\?|$)/, route => route.fulfill({
    json: { code: 0, data: [{
      id: 'layout-lending', contact_name: '模拟借款人', type: 'lend_out', principal: 100,
      current_balance: 90, total_repaid: 10, lend_date: '2026-10-01', is_settled: false,
    }] },
  }))
  await page.goto('/#/lendings')
  const lending = page.locator('.group').filter({ hasText: '模拟借款人' }).first()
  await expect(lending.getByRole('button', { name: '还款', exact: true }).locator('..')).toHaveCSS('opacity', '1')
  await lending.getByRole('button', { name: '还款', exact: true }).click()
  await fitsPhoneDialog(page.getByRole('dialog', { name: '记录还款', exact: true }))
})

test('account log pages belong to accounts in the common navigation directory', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('/#/account-logs')
  await expect(page.getByRole('heading', { name: '账户流水', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: '我的', exact: true })).not.toHaveAttribute('aria-current', 'page')
  await page.getByRole('button', { name: '更多导航', exact: true }).click()
  await expect(page.getByRole('region', { name: '更多功能' }).getByRole('link', { name: '账户', exact: true })).toHaveAttribute('aria-current', 'page')
})

test('account hover effects respect reduced motion and do not expand the scroll area', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto('/#/accounts')
  const card = page.locator('.card-premium').first()
  await expect(card).toBeVisible()
  const bounds = (await card.boundingBox())!
  await page.mouse.move(bounds.x + 5, bounds.y + 5)
  await expect(card.locator('..')).toHaveCSS('transform', 'none')
  expect(await page.locator('main').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
})

test('profile and security drafts stay within a short phone viewport', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 })
  await page.goto('/#/settings')
  await page.getByRole('button', { name: '编辑个人信息', exact: true }).click()
  let panel = page.getByRole('dialog', { name: '编辑个人信息', exact: true })
  await expect(page.getByPlaceholder('输入昵称', { exact: true })).toBeVisible()
  await fitsPhoneDialog(panel)
  await panel.getByRole('button', { name: '保存', exact: true }).scrollIntoViewIfNeeded()
  await panel.getByRole('button', { name: '关闭编辑个人信息', exact: true }).click()
  await page.getByRole('button', { name: '安全入口', exact: true }).click()
  panel = page.getByRole('dialog', { name: '安全入口', exact: true })
  await page.getByTitle('生成随机路径', { exact: true }).click()
  await expect(page.getByText('当前路径尚未保存，保存后生效。', { exact: true })).toBeVisible()
  await fitsPhoneDialog(panel)
  const save = panel.getByRole('button', { name: '保存设置', exact: true })
  await save.scrollIntoViewIfNeeded()
  const saveBox = (await save.boundingBox())!
  expect(saveBox.y + saveBox.height).toBeLessThanOrEqual(568.5)
})

for (const width of [390, 1440]) {
  test(`active header search keeps its clear action reachable at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    await page.goto('/#/transactions')
    const search = page.getByRole('searchbox', { name: '搜索', exact: true })
    await search.fill('页头搜索验证')
    const clear = page.getByRole('button', { name: '清除搜索', exact: true })
    await expect(clear).toBeVisible()
    const box = (await clear.boundingBox())!
    expect(box.height).toBeGreaterThanOrEqual(43.99)
    expect(box.width).toBeGreaterThanOrEqual(43.99)
    expect(box.x + box.width).toBeLessThanOrEqual(width)
    await clear.click()
    await expect(search).toHaveValue('')
    expect(await page.getByRole('main').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  })
}
