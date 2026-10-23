import { expect, test, type Page, type Locator } from '@playwright/test'
const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
test.beforeAll(async ({ request }) => {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED).toBe('1')
  const status = await request.get('/api/v1/auth/status')
  if (!(await status.json()).data.initialized) expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
})
async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}
async function checkDialog(page: Page, trigger: Locator, title: string) {
  await trigger.click()
  const dialog = page.getByRole('dialog', { name: title, exact: true })
  await expect(dialog).toBeVisible()
  await expect.poll(() => dialog.evaluate(el => el.contains(document.activeElement))).toBe(true)
  expect(await page.locator('#app').evaluate(el => (el as HTMLElement).inert)).toBe(true)
  const close = dialog.getByRole('button', { name: title === '新增交易' ? '关闭交易表单' : `关闭${title}`, exact: true })
  await expect(close).toBeEnabled()
  if (title === '交易导入') await expect(dialog.locator('footer').getByRole('button', { name: /^(取消|关闭)$/ })).toBeEnabled()
  const buttons = dialog.locator('button:not(:disabled),input:not(:disabled),textarea:not(:disabled),select:not(:disabled),a[href]').filter({ visible: true })
  await buttons.last().focus()
  await page.keyboard.press('Tab')
  await expect(close).toBeFocused()
  await page.keyboard.press('Shift+Tab')
  await expect(buttons.last()).toBeFocused()
  expect(await dialog.locator('.finance-dialog-body').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  if (await dialog.locator('footer').count()) await expect.poll(async () => { const b = (await dialog.locator('footer').boundingBox())!; return b.y + b.height }).toBeLessThanOrEqual(page.viewportSize()!.height + 1)
  await page.screenshot({ path: test.info().outputPath(`${title}.png`), animations: 'disabled' })
  await page.keyboard.press('Escape')
  await expect(dialog).toHaveCount(0)
  await expect(trigger).toBeFocused()
  expect(await page.locator('#app').evaluate(el => (el as HTMLElement).inert)).toBe(false)
}
for (const width of [320, 390, 1440]) {
  test(`remaining settings dialogs trap and restore focus at ${width}`, async ({ page }) => {
    test.setTimeout(90_000)
    await page.setViewportSize({ width, height: 844 })
    const errors: string[] = []
    page.on('pageerror', error => errors.push(error.message))
    await login(page)
    await page.goto('/#/appearance')
    await page.getByRole('button', { name: width === 390 ? '深色' : '浅色', exact: true }).click()
    await page.goto('/#/settings')
    for (const [opener, title] of [
      ['编辑个人信息', '编辑个人信息'], ['修改密码', '修改密码'], ['通知设置', '通知设置'],
      ['安全入口', '安全入口'], ['API Token', 'API Token 管理'], ['交易导入', '交易导入'],
      ['恢复备份', '恢复备份'], ['自动备份', '自动备份设置'], ['关于应用', '关于应用'], ['退出登录', '确认退出'],
    ]) await checkDialog(page, page.getByRole('button', { name: opener, exact: true }), title!)
    expect(errors).toEqual([])
  })
  test(`transaction editor uses modal isolation at ${width}`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    await login(page)
    await checkDialog(page, page.getByRole('button', { name: '记一笔', exact: true }), '新增交易')
  })
}

for (const width of [390, 1440]) {
  test(`nested copy and revoke confirmations keep parent focus at ${width}`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    await page.addInitScript(() => Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async () => { throw new Error('isolated clipboard unavailable') } } }))
    await login(page)
    let created = false
    const token = { id: 8123, name: '隔离复制验证', token_prefix: 'demo', scopes: ['ledger:read'], last_used_at: null, expires_at: null, created_at: '2026-10-23T12:00:00Z' }
    await page.route('**/api/v1/api-tokens', async route => {
      if (route.request().method() === 'POST') {
        created = true
        await route.fulfill({ json: { code: 0, data: { ...token, token: 'demo-only-not-a-real-token' } } })
      } else await route.fulfill({ json: { code: 0, data: { list: created ? [token] : [] } } })
    })
    await page.goto('/#/settings')
    await page.getByRole('button', { name: 'API Token', exact: true }).click()
    const parent = page.getByRole('dialog', { name: 'API Token 管理', exact: true })
    await parent.getByPlaceholder('例如：我的手机').fill(token.name)
    await parent.getByRole('button', { name: '创建令牌', exact: true }).click()
    const copy = parent.getByRole('button', { name: '复制新令牌', exact: true })
    await copy.click()
    const manual = page.getByRole('dialog', { name: '手动复制', exact: true })
    await expect(manual.getByLabel('待复制内容')).toHaveValue('demo-only-not-a-real-token')
    await expect(manual.getByRole('heading', { name: '手动复制', exact: true })).toBeFocused()
    await page.keyboard.press('Escape')
    await expect(manual).toHaveCount(0)
    await expect(copy).toBeFocused()
    expect(await page.locator('#app').evaluate(el => (el as HTMLElement).inert)).toBe(true)
    const revoke = parent.getByRole('button', { name: `撤销令牌 ${token.name}`, exact: true })
    await revoke.click()
    const confirm = page.getByRole('dialog', { name: '撤销令牌', exact: true })
    await confirm.getByRole('button', { name: '取消', exact: true }).click()
    await expect(revoke).toBeFocused()
    await revoke.click()
    let release!: () => void, calls = 0
    const gate = new Promise<void>(resolve => { release = resolve })
    await page.route('**/api/v1/api-tokens/8123', async route => { calls++; await gate; await route.fulfill({ status: 400, json: { code: 400, message: '隔离验证：撤销失败' } }) })
    await confirm.getByRole('button', { name: '确认撤销', exact: true }).click()
    await expect.poll(() => calls).toBe(1)
    await expect(confirm).toHaveAttribute('aria-busy', 'true')
    await page.keyboard.press('Escape')
    await expect(confirm).toBeVisible()
    release()
    await expect(confirm).toHaveAttribute('aria-busy', 'false')
    await expect(confirm).toContainText(token.name)
    await page.keyboard.press('Escape')
    await expect(revoke).toBeFocused()
    await page.unroute('**/api/v1/api-tokens/8123')
    await page.route('**/api/v1/api-tokens/8123', async route => { created = false; await route.fulfill({ json: { code: 0, data: null } }) })
    await revoke.click()
    await confirm.getByRole('button', { name: '确认撤销', exact: true }).click()
    await expect(confirm).toHaveCount(0)
    await expect(revoke).toHaveCount(0)
    await expect.poll(() => parent.evaluate(el => el.contains(document.activeElement))).toBe(true)
    await page.keyboard.press('Escape')
    await expect(parent).toHaveCount(0)
    expect(await page.locator('#app').evaluate(el => (el as HTMLElement).inert)).toBe(false)
  })

  test(`password failure keeps draft and blocks dismissal while submitting at ${width}`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    await login(page)
    await page.goto('/#/settings')
    await page.getByRole('button', { name: '修改密码', exact: true }).click()
    const dialog = page.getByRole('dialog', { name: '修改密码', exact: true })
    await dialog.getByLabel('当前密码', { exact: true }).fill('demo-old-password')
    await dialog.getByLabel('新密码', { exact: true }).fill('Demo-new-password-123')
    await dialog.getByLabel('确认新密码', { exact: true }).fill('Demo-new-password-123')
    let release!: () => void, calls = 0
    const gate = new Promise<void>(resolve => { release = resolve })
    await page.route('**/api/v1/auth/change-password', async route => { calls++; await gate; await route.fulfill({ status: 400, json: { code: 400, message: '隔离验证：修改失败' } }) })
    await dialog.getByRole('button', { name: '确认修改', exact: true }).click()
    await expect.poll(() => calls).toBe(1)
    await expect(dialog.getByRole('button', { name: '关闭修改密码', exact: true })).toBeDisabled()
    await page.keyboard.press('Escape')
    await expect(dialog).toBeVisible()
    release()
    await expect(dialog.getByRole('button', { name: '确认修改', exact: true })).toBeEnabled()
    await expect(dialog.getByLabel('新密码', { exact: true })).toHaveValue('Demo-new-password-123')
    await expect(dialog).toContainText('隔离验证：修改失败')
    expect(calls).toBe(1)
    await page.keyboard.press('Escape')
    await expect(dialog).toHaveCount(0)
  })
}

test('browser back releases modal isolation when parent and confirmation unmount together', async ({ page }) => {
  await login(page)
  await page.route('**/api/v1/api-tokens', route => route.fulfill({ json: { code: 0, data: { list: [{ id: 991, name: '隔离导航令牌', token_prefix: 'demo', scopes: ['ledger:read'], created_at: '2026-10-23T12:00:00Z' }] } } }))
  await page.goto('/#/settings')
  await page.getByRole('button', { name: 'API Token', exact: true }).click()
  await page.getByRole('button', { name: '撤销令牌 隔离导航令牌', exact: true }).click()
  await expect(page.getByRole('dialog', { name: '撤销令牌', exact: true })).toBeVisible()
  await page.goBack()
  await expect(page).toHaveURL(/\/#\/$/)
  await expect(page.getByRole('dialog')).toHaveCount(0)
  expect(await page.locator('#app').evaluate(el => (el as HTMLElement).inert)).toBe(false)
  expect(await page.locator('body').evaluate(el => el.style.overflow)).not.toBe('hidden')
  await page.getByRole('button', { name: '记一笔', exact: true }).click()
  await expect(page.getByRole('dialog', { name: '新增交易', exact: true })).toBeVisible()
})

for (const width of [390, 1440]) {
  test(`composition Escape preserves dialog draft at ${width}`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    await login(page)
    await page.goto('/#/settings')
    await page.getByRole('button', { name: '编辑个人信息', exact: true }).click()
    const dialog = page.getByRole('dialog', { name: '编辑个人信息', exact: true })
    const nickname = dialog.getByLabel('昵称', { exact: true })
    await nickname.fill('隔离草稿')
    await nickname.dispatchEvent('keydown', { key: 'Escape', code: 'Escape', isComposing: true, bubbles: true })
    await expect(dialog).toBeVisible()
    await expect(nickname).toHaveValue('隔离草稿')
    await page.keyboard.press('Escape')
    await expect(dialog).toHaveCount(0)
  })
}
