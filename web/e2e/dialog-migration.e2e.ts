import { expect, test, type Page, type Locator, type APIRequestContext } from '@playwright/test'
const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.beforeAll(async ({ request }) => {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED).toBe('1')
  const status = await request.get('/api/v1/auth/status')
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})
test.beforeEach(async ({ page }) => {
  page.on('pageerror', error => { throw error })
})

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}
async function fixture(request: APIRequestContext, name: string) {
  const auth = await request.post('/api/v1/auth/login', { data: { password } })
  const headers = { Authorization: `Bearer ${(await auth.json()).data.access_token}` }
  async function create(path: string, data: unknown) {
    const result = await request.post(`/api/v1/${path}`, { headers, data })
    expect(result.ok(), `${path}: ${result.status()}`).toBeTruthy()
    return (await result.json()).data
  }
  const account = await create('accounts', { name, type: 'cash', initial_balance: 1000 })
  const category = await create('categories', { name, type: 'expense' })
  await create('tags', { name })
  await create('templates', { name, type: 'expense', amount: 20, account_id: account.id, category_id: category.id })
  await create('lendings', { type: 'lend_out', contact_name: name, principal: 200, lend_date: new Date().toISOString(), create_transaction: false })
  await create('reminders', { name, loan_type: 'other', payment_day: 20, advance_days: 3, principal: 200, current_balance: 200 })
}
async function checkDialog(page: Page, trigger: Locator, title: string, shot: string) {
  await trigger.click()
  const dialog = page.getByRole('dialog', { name: title, exact: true })
  await expect(dialog).toBeVisible()
  await expect(dialog.getByRole('heading', { name: title, exact: true })).toBeFocused()
  expect(await page.locator('#app').evaluate(el => (el as HTMLElement).inert)).toBe(true)
  const controls = dialog.locator('button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea:not(:disabled),a[href]').filter({ visible: true })
  await controls.last().focus()
  await page.keyboard.press('Tab')
  await expect(dialog.getByRole('button', { name: `关闭${title}`, exact: true })).toBeFocused()
  await page.keyboard.press('Shift+Tab')
  await expect(controls.last()).toBeFocused()
  expect(await dialog.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  expect(await dialog.locator('.finance-dialog-body').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  await expect.poll(async () => {
    const footer = (await dialog.locator('footer').boundingBox())!
    return footer.y + footer.height
  }).toBeLessThanOrEqual(page.viewportSize()!.height + 1)
  await page.screenshot({ path: test.info().outputPath(`${shot}.png`), animations: 'disabled' })
  await page.keyboard.press('Escape')
  await expect(dialog).toHaveCount(0)
  await expect(trigger).toBeFocused()
  expect(await page.locator('#app').evaluate(el => (el as HTMLElement).inert)).toBe(false)
}
for (const width of [320, 390, 1440]) {
  test(`all migrated dialogs focus and fit at ${width}`, async ({ page, request }) => {
    test.setTimeout(120_000)
    await page.setViewportSize({ width, height: 844 })
    await page.emulateMedia({ reducedMotion: 'reduce' })
    const name = `隔离弹窗${width}-${test.info().project.name}-${Date.now()}`
    await fixture(request, name)
    await login(page)
    await page.goto('/#/appearance')
    await page.getByRole('button', { name: width === 390 ? '深色' : '浅色', exact: true }).click()
    await page.goto('/#/categories')
    await checkDialog(page, page.getByRole('button', { name: '添加分类', exact: true }), '添加分类', 'category-create')
    await checkDialog(page, page.getByRole('button', { name: `编辑分类 ${name}`, exact: true }), '编辑分类', 'category-edit')
    await checkDialog(page, page.getByRole('button', { name: `删除分类 ${name}`, exact: true }), '确认删除', 'category-delete')
    await page.goto('/#/tags')
    await checkDialog(page, page.getByRole('button', { name: '添加标签', exact: true }), '创建标签', 'tag-create')
    await checkDialog(page, page.getByRole('button', { name: `编辑标签 ${name}`, exact: true }), '编辑标签', 'tag-edit')
    await checkDialog(page, page.getByRole('button', { name: `删除标签 ${name}`, exact: true }), `删除「${name}」？`, 'tag-delete')
    await page.goto('/#/templates')
    await checkDialog(page, page.getByRole('button', { name: '添加模板', exact: true }), '创建快捷模板', 'template-create')
    await checkDialog(page, page.locator('article').filter({ hasText: name }).getByRole('button', { name: '使用模板' }), `使用「${name}」`, 'template-apply')
    await checkDialog(page, page.getByRole('button', { name: `删除模板 ${name}`, exact: true }), `删除「${name}」？`, 'template-delete')
    await page.goto('/#/lendings')
    await checkDialog(page, page.getByRole('button', { name: '记一笔借出', exact: true }), '记一笔借出', 'lending-create')
    await checkDialog(page, page.getByRole('button', { name: `编辑借款 ${name}`, exact: true }), '编辑记录', 'lending-edit')
    await checkDialog(page, page.locator('.group').filter({ hasText: name }).first().getByRole('button', { name: '还款', exact: true }), '记录还款', 'lending-repay')
    await checkDialog(page, page.getByRole('button', { name: `删除借款 ${name}`, exact: true }), '确认删除', 'lending-delete')
    await page.goto('/#/reminders?view=reminders')
    await checkDialog(page, page.getByRole('button', { name: '添加提醒', exact: true }), '添加提醒', 'reminder-create')
    await checkDialog(page, page.getByRole('button', { name: `编辑提醒 ${name}`, exact: true }), '编辑提醒', 'reminder-edit')
    await checkDialog(page, page.locator('.group').filter({ hasText: name }).first().getByRole('button', { name: '+ 记录还款', exact: true }), '记录还款', 'reminder-pay')
    await checkDialog(page, page.getByRole('button', { name: `删除提醒 ${name}`, exact: true }), '确认删除', 'reminder-delete')
  })
}

for (const kind of ['categories', 'tags', 'templates', 'lendings', 'reminders']) {
  test(`${kind} pending request locks dismissal and failure retains draft`, async ({ page, request }) => {
    await page.setViewportSize({ width: 390, height: 844 })
    if (kind === 'templates') await fixture(request, `模板失败测试${Date.now()}`)
    await login(page)
    await page.goto(`/#/${kind}${kind === 'reminders' ? '?view=reminders' : ''}`)
    const setup: Record<string, [string, string, string, string]> = {
      categories: ['添加分类', '添加分类', '分类名称', '保存'],
      tags: ['添加标签', '创建标签', '名称', '保存标签'],
      templates: ['添加模板', '创建快捷模板', '模板名称', '保存模板'],
      lendings: ['记一笔借出', '记一笔借出', '联系人姓名', '确认'],
      reminders: ['添加提醒', '添加提醒', '提醒名称', '保存'],
    }
    const [opener, title, field, submit] = setup[kind]!
    await page.getByRole('button', { name: opener, exact: true }).click()
    const dialog = page.getByRole('dialog', { name: title, exact: true })
    await dialog.getByLabel(field, { exact: true }).fill('保留失败草稿')
    if (kind === 'lendings') await dialog.getByLabel('借贷本金', { exact: true }).fill('100')
    let attempts = 0
    let release!: () => void
    const gate = new Promise<void>(resolve => { release = resolve })
    await page.route(`**/api/v1/${kind}`, async route => {
      if (route.request().method() !== 'POST') return route.continue()
      attempts++
      await gate
      await route.fulfill({ status: 400, json: { code: 400, message: '隔离测试：暂时无法保存' } })
    })
    await dialog.getByRole('button', { name: submit, exact: true }).click()
    await expect.poll(() => attempts).toBe(1)
    await expect(dialog).toHaveAttribute('aria-busy', 'true')
    await expect(dialog.getByRole('button', { name: `关闭${title}`, exact: true })).toBeDisabled()
    await page.keyboard.press('Escape')
    await expect(dialog).toBeVisible()
    await expect(dialog.getByLabel(field, { exact: true })).toBeDisabled()
    release()
    await expect(dialog).toHaveAttribute('aria-busy', 'false')
    await expect(dialog.getByLabel(field, { exact: true })).toHaveValue('保留失败草稿')
    await expect(dialog.getByRole('button', { name: submit, exact: true })).toBeEnabled()
    expect(attempts).toBe(1)
    await page.keyboard.press('Escape')
    await expect(dialog).toHaveCount(0)
  })
}

for (const width of [390, 1440]) {
  test(`nested attachment preview restores the parent dialog at ${width}`, async ({ page, request }) => {
    await page.setViewportSize({ width, height: 844 })
    const name = `附件焦点${width}-${Date.now()}`
    await fixture(request, name)
    await login(page)
    const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7N8AAAAASUVORK5CYII=', 'base64')
    await page.route('**/api/v1/upload', route => route.fulfill({ json: { code: 0, data: { path: 'lendings/mock/proof.png', filename: 'proof.png', size: png.length } } }))
    await page.route('**/api/v1/upload/download?*', route => route.fulfill({ contentType: 'image/png', body: png }))
    await page.goto('/#/lendings')
    const edit = page.getByRole('button', { name: `编辑借款 ${name}`, exact: true })
    await edit.click()
    const parent = page.getByRole('dialog', { name: '编辑记录', exact: true })
    await parent.locator('input[type=file]').setInputFiles({ name: 'proof.png', mimeType: 'image/png', buffer: png })
    const preview = parent.getByRole('button', { name: '预览附件 proof.png', exact: true })
    await preview.click()
    const child = page.getByRole('dialog', { name: '附件预览', exact: true })
    await expect(child.getByRole('heading', { name: '附件预览', exact: true })).toBeFocused()
    await page.keyboard.press('Tab')
    await expect(child.getByRole('button', { name: '关闭附件预览', exact: true })).toBeFocused()
    await page.keyboard.press('Escape')
    await expect(child).toHaveCount(0)
    await expect(parent).toBeVisible()
    await expect(preview).toBeFocused()
    expect(await page.locator('#app').evaluate(el => (el as HTMLElement).inert)).toBe(true)
    await expect(parent.getByLabel('联系人姓名', { exact: true })).toHaveValue(name)
    await page.keyboard.press('Escape')
    await expect(parent).toHaveCount(0)
    await expect(edit).toBeFocused()
    expect(await page.locator('#app').evaluate(el => (el as HTMLElement).inert)).toBe(false)
  })
}
