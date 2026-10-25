import { expect, test, type Page, type TestInfo } from '@playwright/test'
import { readFile } from 'node:fs/promises'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.beforeAll(async ({ request }) => {
  const status = await request.get('/api/v1/auth/status')
  expect(status.ok()).toBeTruthy()
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

async function capture(page: Page, info: TestInfo, name: string) {
  await page.screenshot({ path: info.outputPath(`${name}.png`), animations: 'disabled' })
  if (process.env.LEDGER_WEB_VISUAL_BASELINE_DIR) {
    await expect(page).toHaveScreenshot(`${name}.png`, {
      animations: 'disabled',
      maxDiffPixelRatio: 0.01,
    })
  }
}

for (const width of [390, 1280]) {
  for (const theme of ['light', 'dark'] as const) {
    test(`preserves form layout and explicit ${theme} theme at ${width}px`, async ({ page }, info) => {
      await page.setViewportSize({ width, height: 844 })
      await page.clock.setFixedTime(new Date('2026-10-15T04:00:00Z'))
      await page.emulateMedia({ colorScheme: theme === 'dark' ? 'light' : 'dark', reducedMotion: 'reduce' })
      await page.addInitScript(value => localStorage.setItem('theme', value), theme)
      await page.goto('/#/login')
      const heading = page.getByRole('heading', { name: '欢迎回来', exact: true })
      await expect(heading).toBeVisible()
      await expect(page.locator('html')).toHaveClass(theme === 'dark' ? /dark/ : /^(?!.*\bdark\b)/)
      await expect(heading.locator('../..')).toHaveCSS('padding-top', '32px')
      await expect(page.getByLabel('密码', { exact: true })).toHaveCSS('padding-left', '44px')
      await expect(page.getByLabel('密码', { exact: true })).toHaveCSS('border-radius', '16px')
      await expect(page.getByRole('button', { name: '解锁', exact: true })).toHaveCSS('background-color', 'rgb(0, 122, 255)')
      await capture(page, info, `login-${width}-${theme}`)

      await page.getByLabel('密码', { exact: true }).fill(password)
      await page.getByRole('button', { name: '解锁', exact: true }).click()
      await expect(page).toHaveURL(/\/#\/$/)
      // Keep visual data deterministic while using the real router, store,
      // authentication transport and compiled Vue components.
      await page.route(/\/api\/v1\/transactions(?:\?|$)/, route => route.fulfill({
        json: { code: 0, data: { list: [], total: 0, page: 1, page_size: 20 } },
      }))
      await page.route(/\/api\/v1\/accounts(?:\?|$)/, route => route.fulfill({
        json: { code: 0, data: {
          list: [{ id: 'visual-account', name: '合成现金账户', type: 'cash', icon: 'wallet', color: '#007AFF',
            initial_balance: 100, current_balance: 100, total_paid: 0, is_archived: false, sort_order: 0 }],
          total_assets: 100, total_liabilities: 0, net_assets: 100,
        } },
      }))
      await page.route(/\/api\/v1\/categories(?:\?|$)/, route => route.fulfill({
        json: { code: 0, data: { list: [
          { id: 'visual-food', name: '餐饮', type: 'expense', icon: 'wallet', color: '#FF9500', is_system: true, sort_order: 0 },
        ] } },
      }))
      for (const endpoint of ['family/members', 'tags']) {
        await page.route(`**/api/v1/${endpoint}`, route => route.fulfill({ json: { code: 0, data: [] } }))
      }
      await page.goto('/#/transactions')
      await expect(page.getByRole('heading', { name: '账单明细', exact: true })).toBeVisible()
      const trigger = page.getByRole('button', { name: '记一笔', exact: true })
      await trigger.focus()
      await trigger.press('Enter')
      const dialog = page.getByRole('dialog', { name: '新增交易', exact: true })
      await expect(dialog).toBeVisible()
      await expect(dialog.getByLabel('金额', { exact: true })).toBeFocused()
      await expect(dialog.locator('fieldset')).toHaveCSS('padding-left', '0px')
      await expect(dialog.locator('.finance-dialog-body')).toHaveCSS('padding-left', width < 768 ? '18px' : '24px')
      await expect(dialog.getByLabel('金额', { exact: true })).toHaveCSS('padding-left', '40px')
      await expect(dialog.getByLabel('账户', { exact: true })).toHaveValue('visual-account')
      await expect(dialog.getByRole('button', { name: '选择餐饮分类', exact: true }).locator('svg')).toHaveCount(1)
      await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)
      await capture(page, info, `dialog-${width}-${theme}`)
      await page.keyboard.press('Escape')
      await expect(dialog).toHaveCount(0)
      await expect(trigger).toBeFocused()
    })
  }
}

test('preserves compiled shadow, gradient, outline and disabled cursor semantics', async ({ page, browserName }) => {
  await page.goto('/#/login')
  await expect(page.getByRole('heading', { name: '欢迎回来', exact: true })).toBeVisible()
  const styles = await page.evaluate(() => {
    // Exercise classes already used by account cards and forms against the
    // browser CSS parser; invalid multi-shadow variables otherwise fail silently.
    const probe = document.createElement('button')
    probe.className = 'drop-shadow-md bg-gradient-to-r from-blue-500 to-cyan-400 outline-hidden'
    probe.disabled = true
    document.body.append(probe)
    const style = getComputedStyle(probe)
    const result = {
      filter: style.filter,
      gradient: style.backgroundImage,
      outline: style.outlineStyle,
      cursor: style.cursor,
    }
    probe.remove()
    return result
  })
  expect(styles.filter.match(/drop-shadow\(/g)).toHaveLength(2)
  expect(styles.gradient).toContain('linear-gradient(')
  expect(styles.gradient).not.toContain('oklab')
  // v4 hides the outline normally and restores it in forced-colors mode.
  expect(styles.outline).toBe('none')
  expect(styles.cursor).toBe('default')

  if (browserName !== 'webkit') {
    await page.emulateMedia({ forcedColors: 'active' })
  }
  const states = await page.evaluate(() => {
    const group = document.createElement('div')
    group.className = 'space-y-2'
    const label = document.createElement('label')
    label.className = 'flex items-center gap-3 text-xs'
    const input = document.createElement('input')
    input.className = 'peer focus:outline-hidden'
    const peer = document.createElement('span')
    peer.className = 'peer-focus:outline-hidden'
    const plain = document.createElement('span')
    plain.className = 'outline-hidden'
    label.append(input, peer, plain)
    group.append(label)
    document.body.append(group)
    input.focus()
    const result = {
      labelDisplay: getComputedStyle(label).display,
      focusedOutline: getComputedStyle(input).outlineStyle,
      focusedWidth: getComputedStyle(input).outlineWidth,
      peerOutline: getComputedStyle(peer).outlineStyle,
      peerWidth: getComputedStyle(peer).outlineWidth,
      plainOutline: getComputedStyle(plain).outlineStyle,
      plainWidth: getComputedStyle(plain).outlineWidth,
    }
    group.remove()
    return result
  })
  const outline = browserName === 'webkit' ? 'none' : 'solid'
  expect(states).toMatchObject({
    labelDisplay: 'flex',
    focusedOutline: outline,
    peerOutline: outline,
    plainOutline: outline,
  })
  if (browserName !== 'webkit') {
    expect([states.focusedWidth, states.peerWidth, states.plainWidth]).toEqual(['2px', '2px', '2px'])
  }
})

test('restores a real Cookie session and transfers multipart and Blob attachments', async ({ page }) => {
  await login(page)
  const refreshed = page.waitForResponse(response => new URL(response.url()).pathname === '/api/v1/auth/refresh')
  await page.reload()
  expect((await refreshed).ok()).toBeTruthy()
  await expect(page.getByRole('button', { name: '记一笔', exact: true })).toBeVisible()
  await page.getByRole('button', { name: '记一笔', exact: true }).click()
  const createDialog = page.getByRole('dialog', { name: '新增交易', exact: true })
  const remark = `升级附件验证 ${Date.now()}`
  await createDialog.getByLabel('金额', { exact: true }).fill('1')
  await createDialog.getByRole('button', { name: '选择餐饮分类', exact: true }).click()
  await createDialog.getByLabel('备注', { exact: true }).fill(remark)
  await createDialog.getByRole('button', { name: '保存记录', exact: true }).click()
  await expect(createDialog).toHaveCount(0)
  await page.getByRole('button', { name: '明细', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/transactions$/)
  await expect(page.getByRole('heading', { name: '账单明细', exact: true })).toBeVisible()
  await page.getByText(remark, { exact: true }).click()
  const dialog = page.getByRole('dialog', { name: '编辑交易', exact: true })
  await expect(dialog).toBeVisible()
  const content = 'ledger upgrade transport\n'
  const uploaded = page.waitForResponse(response =>
    new URL(response.url()).pathname === '/api/v1/upload' && response.request().method() === 'POST')
  await dialog.locator('input[type="file"]').setInputFiles({
    name: 'upgrade-proof.txt', mimeType: 'text/plain', buffer: Buffer.from(content),
  })
  const response = await uploaded
  expect(response.ok()).toBeTruthy()
  expect(await response.request().headerValue('content-type')).toMatch(/^multipart\/form-data;\s*boundary=/)
  expect(await response.request().headerValue('x-csrf-token')).toBeTruthy()
  const downloadEvent = page.waitForEvent('download')
  await dialog.locator('button').filter({ has: page.locator('svg.lucide-download, svg.lucide-download-icon') }).click()
  const download = await downloadEvent
  const path = await download.path()
  expect(path).not.toBeNull()
  expect(await readFile(path!, 'utf8')).toBe(content)
})
