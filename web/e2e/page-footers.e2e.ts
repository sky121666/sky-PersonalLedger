import { expect, test, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.beforeAll(async ({ request }) => {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED, 'footer tests require the temporary database runner').toBe('1')
  const status = await request.get('/api/v1/auth/status')
  expect(status.ok()).toBeTruthy()
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
  const login = await request.post('/api/v1/auth/login', { data: { password } })
  expect(login.ok()).toBeTruthy()
  const headers = { Authorization: `Bearer ${(await login.json()).data.access_token}` }
  expect((await request.post('/api/v1/accounts', {
    headers, data: { name: `页脚隔离钱包-${crypto.randomUUID()}`, type: 'cash', initial_balance: 0 },
  })).ok()).toBeTruthy()
})

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

async function footerFits(page: Page, selector: string) {
  const footer = page.locator(selector).last()
  await footer.scrollIntoViewIfNeeded()
  const bounds = (await footer.boundingBox())!
  expect(bounds.y).toBeGreaterThanOrEqual(0)
  expect(bounds.y + bounds.height).toBeLessThanOrEqual(page.viewportSize()!.height + 1)
  expect(bounds.x).toBeGreaterThanOrEqual(0)
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(page.viewportSize()!.width + 1)
  expect(await footer.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  const nav = page.locator('.workspace-mobile-nav')
  if (await nav.isVisible() && !selector.includes('action')) {
    expect(bounds.y + bounds.height).toBeLessThanOrEqual((await nav.boundingBox())!.y)
  }
  for (const button of await footer.getByRole('button').all()) {
    const box = (await button.boundingBox())!
    expect(box.height).toBeGreaterThanOrEqual(44)
    expect(box.width).toBeGreaterThanOrEqual(44)
    expect(box.x).toBeGreaterThanOrEqual(bounds.x - 1)
    expect(box.x + box.width).toBeLessThanOrEqual(bounds.x + bounds.width + 1)
    expect(await button.evaluate(el => {
      const b = el.getBoundingClientRect()
      const hit = document.elementFromPoint(b.x + b.width / 2, b.y + b.height / 2)
      return hit === el || el.contains(hit)
    })).toBe(true)
  }
}

for (const width of [320, 390, 768, 1440]) {
  for (const theme of ['light', 'dark'] as const) {
    test(`list footers preserve pagination, busy, retry and honest empty states at ${width}px ${theme}`, async ({ page }) => {
      await page.setViewportSize({ width, height: 844 })
      await page.emulateMedia({ reducedMotion: 'reduce' })
      await login(page)
      await page.goto('/#/appearance')
      await page.getByRole('button', { name: theme === 'dark' ? '深色' : '浅色', exact: true }).click()
      await page.getByRole('button', { name: '侧栏', exact: true }).click()
      for (const kind of ['transactions', 'account-logs']) {
        let failMore = true
        let empty = false
        let release: (() => void) | undefined
        const requestPages: number[] = []
        await page.route(new RegExp(`/api/v1/${kind}(?:\\?|$)`), async route => {
          const n = Number(new URL(route.request().url()).searchParams.get('page') || 1)
          requestPages.push(n)
          if (n > 1 && failMore) {
            await new Promise<void>(resolve => { release = resolve })
            await route.fulfill({ status: 503, json: { code: 500, message: 'isolated pagination outage' } })
            return
          }
          const row = kind === 'transactions'
            ? { id: `t-${n}`, type: 'expense', amount: 12, account_id: 'fixture', remark: `页脚模拟交易${n}`,
                transaction_date: '2026-10-20T12:00:00+08:00', source: 'manual', account: { name: '模拟钱包' } }
            : { id: `l-${n}`, type: 'expense', amount: 12, balance_before: 100, balance_after: 88,
                account_id: 'fixture', remark: `页脚模拟流水${n}`, created_at: '2026-10-20T12:00:00+08:00' }
          await route.fulfill({ json: { code: 0, data: { list: empty ? [] : [row], total: empty ? 0 : 2, page: n } } })
        })
        await page.goto(`/#/${kind}`)
        const footer = page.locator('.finance-list-footer')
        await expect(footer).toContainText('已加载 1 条记录')
        await footerFits(page, '.finance-list-footer')
        const more = footer.getByRole('button')
        await more.click()
        await expect(footer).toHaveAttribute('aria-busy', 'true')
        await expect(more).toBeDisabled()
        await expect(footer).toContainText('正在加载')
        await expect(footer.locator('.finance-list-spinner')).toHaveCSS('animation-name', 'none')
        release!()
        await expect(footer.getByRole('alert')).toContainText('已加载的')
        await expect(footer).toContainText('已加载 1 条记录')
        await footerFits(page, '.finance-list-footer')
        await page.screenshot({ path: test.info().outputPath(`${kind}-retry-${width}-${theme}.png`), animations: 'disabled' })
        failMore = false
        await footer.getByRole('button').click()
        await expect(footer).toContainText('已加载 2 条记录')
        await expect(footer.getByRole('button')).toHaveCount(0)
        await expect(footer.getByRole('alert')).toHaveCount(0)
        expect(requestPages).toEqual([1, 2, 2])
        await footerFits(page, '.finance-list-footer')
        empty = true
        await page.reload()
        await expect(page.getByText(kind === 'transactions' ? '暂无交易记录' : '暂无流水记录', { exact: true })).toBeVisible()
        await expect(footer).toHaveCount(0)
        await page.unroute(new RegExp(`/api/v1/${kind}(?:\\?|$)`))
      }
    })
  }
}

for (const width of [390, 1440]) {
  test(`only task-based footers appear across Web; modal actions fit at ${width}px`, async ({ page }) => {
    test.setTimeout(90_000)
    await page.setViewportSize({ width, height: 700 })
    await page.emulateMedia({ reducedMotion: 'reduce' })
    await login(page)
    const errors: string[] = []
    page.on('pageerror', error => errors.push(error.message))
    for (const theme of ['light', 'dark']) {
      await page.goto('/#/appearance')
      await page.getByRole('button', { name: theme === 'dark' ? '深色' : '浅色', exact: true }).click()
      for (const route of ['', 'statistics', 'report', 'appearance', 'family', 'accounts', 'budgets',
        'categories', 'tags', 'templates', 'lendings', 'reminders', 'ai', 'settings']) {
        await page.goto(`/#/${route}`)
        await expect(page.locator('main h1').first()).toBeVisible()
        if (route === 'reminders') {
          await expect(page.locator('main .finance-list-footer:not([aria-label="分期凭证列表加载"])')).toHaveCount(0)
        } else {
          await expect(page.locator('main .finance-list-footer')).toHaveCount(0)
        }
      }
      for (const item of [
        { path: 'transactions', trigger: '全部类型', action: '应用筛选' },
        { path: 'family', trigger: '管理成员', action: '关闭' },
        { path: 'accounts', trigger: '添加新账户', action: '保存卡片' },
        { path: 'categories', trigger: '添加分类', action: '保存' },
        { path: 'tags', trigger: '添加标签', action: '保存标签' },
        { path: 'templates', trigger: '添加模板', action: '保存模板' },
        { path: 'settings', trigger: '退出登录', action: '取消' },
      ]) {
        await test.step(`${theme}/${item.path}/${item.action}`, async () => {
          await page.goto(`/#/${item.path}`)
          await page.getByRole('button', { name: item.trigger, exact: true }).click()
          const footer = page.locator('.finance-action-footer:visible').last()
          await expect(footer.getByRole('button', { name: item.action, exact: true })).toBeVisible()
          await footerFits(page, '.finance-action-footer:visible')
          await expect(footer.getByRole('button', { name: item.action, exact: true })).toHaveCSS('font-size', '13px')
          await page.screenshot({ path: test.info().outputPath(`${item.path}-actions-${width}-${theme}.png`), animations: 'disabled' })
          if (width < 768) {
            await page.setViewportSize({ width, height: 420 })
            await footerFits(page, '.finance-action-footer:visible')
            await page.setViewportSize({ width, height: 700 })
          }
          // Close by route change, never save or delete a financial object.
        })
      }
    }
    expect(errors).toEqual([])
  })
}
