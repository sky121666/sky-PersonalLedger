import { readFile } from 'node:fs/promises'
import { expect, test, type APIRequestContext, type Page } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.beforeAll(async ({ request }) => {
  const response = await request.get('/api/v1/auth/status')
  expect(response.ok()).toBeTruthy()
  if (!(await response.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

async function api(request: APIRequestContext) {
  const response = await request.post('/api/v1/auth/login', { data: { password } })
  expect(response.ok()).toBeTruthy()
  const headers = { Authorization: `Bearer ${(await response.json()).data.access_token}` }
  return async (path: string, method = 'GET', data?: unknown) => {
    const result = await request.fetch(`/api/v1${path}`, { method, headers, data })
    expect(result.ok(), `${method} ${path}: ${result.status()}`).toBeTruthy()
    return (await result.json()).data
  }
}

function modal(page: Page) {
  return page.locator('.finance-layer .finance-dialog-panel, body > .fixed > .relative').last()
}

async function closeModal(page: Page) {
  await modal(page).locator('button').filter({ has: page.locator('svg.lucide-x') }).click()
  await expect(page.locator('.finance-layer, body > .fixed > .relative')).toHaveCount(0)
}

async function fits(page: Page) {
  await expect.poll(() => page.locator('main').first().evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width)
}

for (const width of [390, 1440]) {
  test.describe(`${width}px real isolated management workflows`, () => {
    test.use({ viewport: { width, height: 844 } })
    test.beforeEach(async ({ page }) => {
      page.setDefaultTimeout(10_000)
      await login(page)
    })

    test('creates, edits, archives and removes unused accounts, categories and tags', async ({ page }) => {
      test.setTimeout(90_000)
      const name = `界面走查${Date.now()}`
      await page.goto('/#/accounts')
      await page.getByRole('button', { name: '添加新账户', exact: true }).click()
      await page.getByPlaceholder('例如：招商银行', { exact: true }).fill(name)
      await modal(page).getByRole('button', { name: '保存卡片', exact: true }).click()
      await expect(page.getByText(name, { exact: true })).toBeVisible()
      await page.getByRole('button', { name: `编辑账户 ${name}`, exact: true }).click()
      await page.getByPlaceholder('例如：招商银行', { exact: true }).fill(`${name}改`)
      await modal(page).getByRole('button', { name: '保存卡片', exact: true }).click()
      await page.getByRole('button', { name: `归档账户 ${name}改`, exact: true }).click()
      await expect(page.getByText(`${name}改`, { exact: true })).toHaveCount(0)
      if (width < 768) {
        const action = (await page.getByRole('button', { name: '查看归档账户', exact: true }).boundingBox())!
        for (const close of await page.getByRole('button', { name: /^关闭提示：/ }).all()) {
          const box = await close.boundingBox()
          if (box) expect(box.x + box.width <= action.x || box.x >= action.x + action.width || box.y + box.height <= action.y || box.y >= action.y + action.height).toBe(true)
        }
      }
      await page.getByRole('button', { name: '查看归档账户', exact: true }).click()
      await page.getByRole('button', { name: `恢复账户 ${name}改`, exact: true }).click()
      await page.getByRole('button', { name: '查看在用账户', exact: true }).click()
      await page.getByRole('button', { name: `删除账户 ${name}改`, exact: true }).click()
      await modal(page).getByRole('button', { name: '销户', exact: true }).click()
      await expect(page.getByText(`${name}改`, { exact: true })).toHaveCount(0)

      await page.goto('/#/categories')
      await page.getByRole('button', { name: '添加分类', exact: true }).click()
      await page.getByPlaceholder('例如：餐饮、交通', { exact: true }).fill(name)
      await modal(page).getByRole('button', { name: '保存', exact: true }).click()
      await page.getByRole('button', { name: `编辑分类 ${name}`, exact: true }).click()
      await page.getByPlaceholder('例如：餐饮、交通', { exact: true }).fill(`${name}改`)
      await modal(page).getByRole('button', { name: '保存', exact: true }).click()
      await page.getByRole('button', { name: `删除分类 ${name}改`, exact: true }).click()
      await modal(page).getByRole('button', { name: '确认删除', exact: true }).click()
      await expect(page.getByText(`${name}改`, { exact: true })).toHaveCount(0)
      await page.getByRole('button', { name: '收入', exact: true }).click()
      await expect(page.getByText('工资', { exact: true })).toBeVisible()

      await page.goto('/#/tags')
      await page.getByRole('button', { name: '添加标签', exact: true }).click()
      await page.getByLabel('名称', { exact: true }).fill(name)
      await page.getByRole('button', { name: '保存标签', exact: true }).click()
      let tag = page.locator('article').filter({ hasText: name })
      await tag.getByRole('button').first().click()
      await page.getByLabel('名称', { exact: true }).fill(`${name}改`)
      await page.getByRole('button', { name: '保存标签', exact: true }).click()
      tag = page.locator('article').filter({ hasText: `${name}改` })
      await tag.getByRole('button').last().click()
      await modal(page).getByRole('button', { name: '删除', exact: true }).click()
      await expect(tag).toHaveCount(0)
      await fits(page)
    })

    test('applies a template and verifies transfers, filters, account logs and CSV export', async ({ page, request }) => {
      test.setTimeout(90_000)
      const call = await api(request)
      const name = `模板走查${Date.now()}`
      const source = await call('/accounts', 'POST', { name: `${name}甲`, type: 'cash', initial_balance: 500 })
      const target = await call('/accounts', 'POST', { name: `${name}乙`, type: 'cash', initial_balance: 100 })
      const categories = (await call('/categories')).list
      const food = categories.find((c: { name: string }) => c.name === '餐饮')
      await page.goto('/#/templates')
      await page.getByRole('main').locator('header button').filter({ has: page.locator('svg.lucide-plus') }).click()
      await page.getByLabel('模板名称', { exact: true }).fill(name)
      await page.getByLabel('默认金额', { exact: true }).fill('20')
      await page.getByRole('combobox', { name: '账户', exact: true }).selectOption(source.id)
      await page.getByRole('combobox', { name: '分类', exact: true }).selectOption(food.id)
      await page.getByLabel('备注', { exact: true }).fill(name)
      await page.getByRole('button', { name: '保存模板', exact: true }).click()
      const template = page.locator('article').filter({ hasText: name })
      await template.getByRole('button', { name: '使用模板', exact: true }).click()
      await page.getByLabel('金额', { exact: true }).fill('25')
      await page.getByRole('button', { name: '确认记账', exact: true }).click()
      await expect(template).toContainText('使用 1 次')
      expect((await call(`/accounts/${source.id}`)).current_balance).toBe(475)
      await template.getByRole('button').last().click()
      await modal(page).getByRole('button', { name: '删除', exact: true }).click()

      await page.getByRole('button', { name: '记一笔', exact: true }).click()
      const entry = page.getByRole('dialog', { name: '新增交易', exact: true })
      await entry.getByRole('button', { name: '转账', exact: true }).click()
      await entry.getByLabel('金额', { exact: true }).fill('30')
      await entry.getByLabel('转出账户', { exact: true }).selectOption(source.id)
      await entry.getByLabel('转入账户', { exact: true }).selectOption(target.id)
      await entry.getByLabel('备注', { exact: true }).fill(`${name}转账`)
      await entry.getByRole('button', { name: '保存记录', exact: true }).click()
      await expect(entry).toHaveCount(0)
      expect((await call(`/accounts/${source.id}`)).current_balance).toBe(445)
      expect((await call(`/accounts/${target.id}`)).current_balance).toBe(130)
      await page.goto('/#/transactions')
      await page.getByPlaceholder('搜索', { exact: true }).fill(name)
      await expect(page.getByText(`${name}转账`, { exact: true })).toBeVisible()
      await fits(page)
      await page.goto(`/#/account-logs/${source.id}`)
      await expect(page.getByRole('heading', { level: 1 })).toContainText('流水')
      await expect(page.getByText('转出', { exact: true }).first()).toBeVisible()
      await fits(page)
      await page.goto('/#/report')
      await expect(page.getByText('年度财务总结', { exact: true })).toBeVisible()
      const downloading = page.waitForEvent('download')
      await page.locator('button').filter({ has: page.locator('svg.lucide-download') }).click()
      const download = await downloading
      const csv = await readFile((await download.path())!, 'utf8')
      expect(csv).toContain(name)
      expect(csv).toContain('30')
    })

    test('edits family members and total, category and member budgets', async ({ page, request }) => {
      test.setTimeout(90_000)
      const call = await api(request)
      const name = `家庭走查${Date.now()}`
      const category = await call('/categories', 'POST', { name: `${name}分类`, type: 'expense' })
      await page.goto('/#/family')
      await page.getByRole('button', { name: '管理成员', exact: true }).click()
      await page.getByRole('dialog', { name: '管理成员', exact: true }).getByRole('button', { name: '新增成员', exact: true }).click()
      await page.getByPlaceholder('成员名称', { exact: true }).fill(name)
      await page.getByPlaceholder('关系，例如 家人 / 子女', { exact: true }).fill('合成成员')
      await page.getByRole('button', { name: '保存', exact: true }).click()
      await expect(page.getByText(name, { exact: true })).toBeVisible()
      await page.getByRole('button', { name: '管理成员', exact: true }).click()
      await page.getByRole('button', { name: `编辑成员 ${name}`, exact: true }).click()
      await page.getByPlaceholder('关系，例如 家人 / 子女', { exact: true }).fill('已修改关系')
      await page.getByRole('button', { name: '保存', exact: true }).click()
      await expect(page.getByText('成员已更新', { exact: true })).toBeVisible()
      const member = (await call('/family/members')).find((m: { name: string }) => m.name === name)
      expect(member.relationship).toBe('已修改关系')
      await page.goto('/#/budgets')
      await page.getByRole('button', { name: /^(修改|立即设置)$/ }).first().click()
      await modal(page).getByRole('spinbutton').fill('10000')
      await modal(page).getByRole('button', { name: '保存', exact: true }).click()
      await expect(page.getByText('¥10,000', { exact: true }).first()).toBeVisible()
      await page.getByRole('button', { name: '添加成员预算', exact: true }).click()
      await modal(page).getByRole('combobox').first().selectOption(member.id)
      await modal(page).getByRole('spinbutton').fill('1200')
      await modal(page).getByRole('button', { name: '保存', exact: true }).click()
      await page.getByRole('button', { name: `编辑${name}的总预算`, exact: true }).click()
      await modal(page).getByRole('spinbutton').fill('1500')
      await modal(page).getByRole('button', { name: '保存', exact: true }).click()
      await expect(page.locator('.finance-layer')).toHaveCount(0)
      await page.getByRole('button', { name: `编辑${name}的总预算`, exact: true }).click()
      await expect(modal(page).getByRole('spinbutton')).toHaveValue('1500')
      await page.getByRole('button', { name: '关闭编辑成员预算', exact: true }).click()
      await page.getByRole('button', { name: '添加分类预算', exact: true }).first().click()
      await modal(page).getByRole('combobox').selectOption(category.id)
      await modal(page).getByRole('spinbutton').fill('500')
      await modal(page).getByRole('button', { name: '保存', exact: true }).click()
      await page.getByRole('button', { name: `编辑${category.name}预算`, exact: true }).click()
      await modal(page).getByRole('spinbutton').fill('650')
      await modal(page).getByRole('button', { name: '保存', exact: true }).click()
      await expect(page.locator('.finance-layer')).toHaveCount(0)
      await page.getByRole('button', { name: `编辑${category.name}预算`, exact: true }).click()
      await expect(modal(page).getByRole('spinbutton')).toHaveValue('650')
      await page.getByRole('button', { name: '关闭编辑分类预算', exact: true }).click()
      await fits(page)
      await page.goto('/#/family')
      await page.getByRole('button', { name: '管理成员', exact: true }).click()
      await page.getByRole('button', { name: `停用成员 ${name}`, exact: true }).click()
      await page.getByRole('button', { name: '确认停用', exact: true }).click()
      await expect(page.getByText('成员已停用', { exact: true })).toBeVisible()
      await expect(page.getByRole('dialog', { name: '停用成员', exact: true })).toHaveCount(0)
      await expect.poll(() => page.getByRole('dialog', { name: '管理成员', exact: true }).evaluate(el => el.contains(document.activeElement))).toBe(true)
      expect((await call('/family/members')).find((m: { id: string }) => m.id === member.id).is_enabled).toBe(false)
    })

    test('creates and repays debts and lending with real balance updates', async ({ page, request }) => {
      test.setTimeout(90_000)
      const call = await api(request)
      const name = `还款走查${Date.now()}`
      const account = await call('/accounts', 'POST', { name, type: 'cash', initial_balance: 1000 })
      await page.goto('/#/reminders?view=reminders')
      await page.getByRole('button', { name: '添加提醒', exact: true }).click()
      await page.getByRole('button', { name: '其他', exact: true }).click()
      await page.getByPlaceholder('例如：房贷、花呗', { exact: true }).fill(name)
      await page.getByPlaceholder('1-31', { exact: true }).fill('20')
      await page.getByPlaceholder('本金/额度', { exact: true }).fill('200')
      await page.getByPlaceholder('待还金额', { exact: true }).fill('200')
      await modal(page).getByRole('button', { name: '保存', exact: true }).click()
      const debt = page.locator('.group').filter({ hasText: name }).first()
      await debt.getByRole('button', { name: '+ 记录还款', exact: true }).click()
      await modal(page).getByRole('spinbutton').nth(0).fill('55')
      await modal(page).getByRole('spinbutton').nth(1).fill('50')
      await modal(page).getByRole('spinbutton').nth(2).fill('5')
      await modal(page).getByRole('combobox').selectOption(account.id)
      await modal(page).getByRole('button', { name: '确认还款', exact: true }).click()
      await expect(page.getByText('还款记录成功，已同步到明细', { exact: true })).toBeVisible()
      expect((await call(`/accounts/${account.id}`)).current_balance).toBe(945)
      await page.getByRole('button', { name: `暂停提醒 ${name}`, exact: true }).click()
      await page.getByRole('button', { name: `启用提醒 ${name}`, exact: true }).click()
      await page.getByRole('button', { name: `编辑提醒 ${name}`, exact: true }).click()
      await page.getByPlaceholder('例如：房贷、花呗', { exact: true }).fill(`${name}改`)
      await modal(page).getByRole('button', { name: '保存', exact: true }).click()
      await expect(page.locator('.finance-layer .finance-dialog-panel, body > .fixed > .relative')).toHaveCount(0)
      expect((await call('/reminders')).some((item: { name: string }) => item.name === `${name}改`)).toBe(true)

      await page.goto('/#/lendings')
      await page.getByRole('button', { name: '记一笔借出', exact: true }).click()
      await page.getByPlaceholder('对方姓名', { exact: true }).fill(name)
      await page.getByPlaceholder('0.00', { exact: true }).fill('100')
      const dueDate = '2026-11-15T18:30'
      await modal(page).locator('input[type=datetime-local]').nth(1).fill(dueDate)
      await modal(page).getByRole('combobox').selectOption(account.id)
      await modal(page).getByRole('button', { name: '确认', exact: true }).click()
      await expect(page.locator('.finance-layer .finance-dialog-panel, body > .fixed > .relative')).toHaveCount(0)
      const createdLending = (await call('/lendings')).find((item: { contact_name: string }) => item.contact_name === name)
      expect(Date.parse(createdLending.due_date)).toBe(Date.parse(`${dueDate}:00+08:00`))
      const lending = page.locator('.group').filter({ hasText: name }).first()
      await lending.getByRole('button', { name: '还款', exact: true }).click()
      await modal(page).getByRole('spinbutton').fill('100')
      await modal(page).getByRole('combobox').selectOption(account.id)
      await expect(modal(page).getByRole('checkbox')).toBeChecked()
      await modal(page).getByRole('button', { name: /确认还款/ }).click()
      await expect(page.locator('.finance-layer .finance-dialog-panel, body > .fixed > .relative')).toHaveCount(0)
      await page.getByRole('button', { name: '已结清', exact: true }).click()
      await expect(page.getByText(name, { exact: true })).toBeVisible()
      expect((await call(`/accounts/${account.id}`)).current_balance).toBe(945)
      await page.getByRole('button', { name: `编辑借款 ${name}`, exact: true }).click()
      await page.getByPlaceholder('对方姓名', { exact: true }).fill(`${name}改`)
      await modal(page).getByRole('button', { name: '保存', exact: true }).click()
      await expect(page.locator('.finance-layer .finance-dialog-panel, body > .fixed > .relative')).toHaveCount(0)
      const edited = (await call('/lendings?include_settled=true')).find((item: { contact_name: string }) => item.contact_name === `${name}改`)
      expect(edited).toBeTruthy()
      expect(Date.parse(edited.due_date)).toBe(Date.parse(createdLending.due_date))
      await page.getByRole('button', { name: `编辑借款 ${name}改`, exact: true }).click()
      await modal(page).locator('input[type=datetime-local]').last().fill('')
      await modal(page).getByRole('button', { name: '保存', exact: true }).click()
      await expect(page.locator('.finance-layer .finance-dialog-panel, body > .fixed > .relative')).toHaveCount(0)
      expect((await call(`/lendings/${createdLending.id}`)).due_date).toBeFalsy()
      await fits(page)
    })

    test('recovers an old minute precision repayment without a duplicate account debit', async ({ page, request }) => {
      const call = await api(request)
      const name = `旧版还款恢复${Date.now()}`
      const account = await call('/accounts', 'POST', { name, type: 'cash', initial_balance: 500 })
      const lending = await call('/lendings', 'POST', {
        type: 'borrow_in', contact_name: name, principal: 100,
        lend_date: '2026-10-14T08:30:00+08:00', create_transaction: false,
      })
      const key = '11111111-1111-4111-8111-111111111111'
      const payload = { amount: 100, record_date: '2026-10-15T08:30', account_id: account.id, create_transaction: true }
      // Represent a pre-upgrade request that was committed but lost its response.
      await call(`/lendings/${lending.id}/repay`, 'POST', { ...payload, idempotency_key: key })
      await page.evaluate(({ id, key, payload }) => {
        sessionStorage.setItem(`personal-ledger:pending-repayment:v1:lending:${id}`, JSON.stringify({
          version: 1, kind: 'lending', targetId: id, key, payload, attempt: 1,
        }))
      }, { id: lending.id, key, payload })
      await page.goto('/#/lendings')
      await page.getByRole('button', { name: '确认上次还款结果', exact: true }).click()
      const date = modal(page).locator('input[type=datetime-local]')
      await expect(date).toHaveValue(payload.record_date)
      await expect(date).toBeDisabled()
      const sending = page.waitForRequest(req => req.url().endsWith(`/lendings/${lending.id}/repay`) && req.method() === 'POST')
      await modal(page).getByRole('button', { name: '确认上次还款结果', exact: true }).click()
      expect((await sending).postDataJSON()).toEqual({ ...payload, idempotency_key: key })
      await expect(page.locator('.finance-layer .finance-dialog-panel, body > .fixed > .relative')).toHaveCount(0)
      await expect(page.getByRole('button', { name: '确认上次还款结果', exact: true })).toHaveCount(0)
      expect((await call(`/accounts/${account.id}`)).current_balance).toBe(400)
      expect((await call(`/lendings/${lending.id}/records`)).length).toBe(1)
      await page.reload()
      await expect(page.getByRole('button', { name: '确认上次还款结果', exact: true })).toHaveCount(0)
    })

    test('keeps a new import file selected after an older real preview returns', async ({ page, request }) => {
      const call = await api(request)
      const name = `导入切换${Date.now()}`
      const account = await call('/accounts', 'POST', { name, type: 'cash', initial_balance: 500 })
      const category = (await call('/categories')).list.find((c: { name: string }) => c.name === '餐饮')
      await page.goto('/#/settings')
      await page.getByRole('button', { name: '交易导入', exact: true }).click()
      await expect(modal(page).getByRole('button', { name: '取消', exact: true }).or(modal(page).getByRole('button', { name: '关闭', exact: true }))).toBeEnabled()
      const file = (suffix: string) => ({
        name: `${name}-${suffix}.json`, mimeType: 'application/json',
        buffer: Buffer.from(JSON.stringify([{
          type: 'expense', amount: suffix === 'a' ? 10 : 20, account_id: account.id, category_id: category.id,
          transaction_date: '2026-10-15T12:00:00+08:00', remark: `${name}-${suffix}`,
        }])),
      })
      await modal(page).locator('input[type=file]').setInputFiles(file('a'))
      let release!: () => void
      const held = new Promise<void>(resolve => { release = resolve })
      let seen!: () => void
      const received = new Promise<void>(resolve => { seen = resolve })
      await page.route('**/api/v1/imports/transactions/preview', async route => {
        const response = await route.fetch()
        seen()
        await held
        await route.fulfill({ response })
      }, { times: 1 })
      await page.getByRole('button', { name: '生成预览', exact: true }).click()
      await received
      await modal(page).locator('input[type=file]').setInputFiles(file('b'))
      const staleResponse = page.waitForResponse(res => res.url().endsWith('/imports/transactions/preview'))
      release()
      await staleResponse
      await expect(modal(page).getByText(`${name}-b.json`, { exact: true })).toBeVisible()
      await expect(page.getByRole('button', { name: /确认导入/ })).toHaveCount(0)
      await page.getByRole('button', { name: '生成预览', exact: true }).click()
      await expect(modal(page).getByText('支出 · 20.00', { exact: true })).toBeVisible()
      await expect(modal(page).getByText('支出 · 10.00', { exact: true })).toHaveCount(0)
      expect((await call(`/accounts/${account.id}`)).current_balance).toBe(500)
      await fits(page)
    })

    test('previews, imports and rolls back transactions then restores a downloaded backup', async ({ page, request }) => {
      test.setTimeout(90_000)
      const call = await api(request)
      const name = `导入走查${Date.now()}`
      const account = await call('/accounts', 'POST', { name, type: 'cash', initial_balance: 500 })
      const category = (await call('/categories')).list.find((c: { name: string }) => c.name === '餐饮')
      await page.goto('/#/settings')
      await page.getByRole('button', { name: '交易导入', exact: true }).click()
      await modal(page).locator('input[type=file]').setInputFiles({
        name: 'synthetic-import.json', mimeType: 'application/json',
        buffer: Buffer.from(JSON.stringify([{
          type: 'expense', amount: 12.5, account_id: account.id, category_id: category.id,
          transaction_date: '2026-10-15T12:00:00+08:00', remark: name,
        }])),
      })
      await page.getByRole('button', { name: '生成预览', exact: true }).click()
      await expect(page.getByText('可导入', { exact: true })).toBeVisible()
      await page.getByRole('button', { name: '确认导入 1 条', exact: true }).click()
      await expect(page.getByText('已导入 1 条；会话到期前可原子撤销。', { exact: true })).toBeVisible()
      expect((await call(`/accounts/${account.id}`)).current_balance).toBe(487.5)
      await page.getByRole('button', { name: '撤销本次导入', exact: true }).click()
      await expect(page.getByText('已撤销 1 条，本次导入未再影响账本。', { exact: true })).toBeVisible()
      expect((await call(`/accounts/${account.id}`)).current_balance).toBe(500)
      await page.getByRole('button', { name: '关闭交易导入', exact: true }).click()
      const downloading = page.waitForEvent('download')
      await page.getByRole('button', { name: '数据备份', exact: true }).click()
      const file = (await (await downloading).path())!
      const backup = JSON.parse(await readFile(file, 'utf8'))
      expect(JSON.stringify(backup)).toContain(name)
      await call(`/accounts/${account.id}`, 'PATCH', { name: `${name}恢复前` })
      await page.getByRole('button', { name: '恢复备份', exact: true }).click()
      await modal(page).locator('input[type=file]').setInputFiles(file)
      await page.getByRole('button', { name: '开始恢复', exact: true }).click()
      await expect(page.getByText('恢复成功', { exact: true })).toBeVisible()
      // Restore changes auth revision, so use a newly authenticated API session.
      const restored = await api(request)
      expect((await restored(`/accounts/${account.id}`)).name).toBe(name)
    })

    test('keeps modal close reachable through stacked toast content', async ({ page }) => {
      await page.goto('/#/settings')
      await page.getByRole('button', { name: '安全入口', exact: true }).click()
      const generate = modal(page).getByTitle('生成随机路径', { exact: true })
      const notices = page.getByRole('button', { name: '关闭提示：已生成随机路径，保存后生效', exact: true })
      for (let count = 1; count <= 2; count++) {
        await generate.click()
        await expect(notices).toHaveCount(count)
      }
      await expect.poll(() => notices.evaluateAll(buttons => buttons.some(button =>
        button.parentElement!.getAnimations().some(animation => animation.playState === 'running'),
      ))).toBe(false)
      await expect(notices).toHaveCount(2)
      const close = modal(page).locator('button').filter({ has: page.locator('svg.lucide-x') })
      // Check hit testing while both notices remain visible, without letting
      // locator retries hide an interception by waiting for toast expiry.
      const target = await close.evaluate(button => {
        const box = button.getBoundingClientRect()
        const x = box.x + box.width / 2
        const y = box.y + box.height / 2
        return { x, y, reachable: button.contains(document.elementFromPoint(x, y)) }
      })
      expect(target.reachable).toBe(true)
      await page.mouse.click(target.x, target.y)
      await expect(page.locator('.finance-layer .finance-dialog-panel, body > .fixed > .relative')).toHaveCount(0)
      await expect(notices).toHaveCount(2)
      await notices.first().click()
      await expect(notices).toHaveCount(1)
    })

    test('opens every management setting and persists local profile and theme changes', async ({ page }) => {
      test.setTimeout(90_000)
      await page.goto('/#/settings')
      await page.getByRole('button', { name: '编辑个人信息', exact: true }).click()
      await page.getByPlaceholder('输入昵称', { exact: true }).fill('界面验证用户')
      await modal(page).getByRole('button', { name: /保存/ }).click()
      await expect(page.getByRole('heading', { name: '界面验证用户', exact: true })).toBeVisible()
      await page.getByRole('button', { name: '外观设置', exact: true }).click()
      await page.getByRole('button', { name: '深色', exact: true }).click()
      await expect(page.locator('html')).toHaveClass(/dark/)
      await page.reload()
      await expect(page.locator('html')).toHaveClass(/dark/)
      await page.getByRole('button', { name: '浅色', exact: true }).click()
      await page.getByRole('button', { name: '返回设置', exact: true }).click()
      await expect(page.locator('html')).not.toHaveClass(/dark/)
      for (const title of ['通知设置', '修改密码', '安全入口', 'API Token', '自动备份']) {
        await page.getByRole('button', { name: title, exact: true }).click()
        await expect(modal(page)).toBeVisible()
        const box = (await modal(page).boundingBox())!
        expect(box.x).toBeGreaterThanOrEqual(0)
        expect(box.x + box.width).toBeLessThanOrEqual(width)
        if (title === '通知设置') {
          for (const channel of ['企业微信', '钉钉', '邮箱', 'Webhook']) {
            await modal(page).getByRole('button', { name: channel, exact: true }).click()
          }
          await modal(page).getByRole('button', { name: '保存设置', exact: true }).click()
          await expect(page.locator('.finance-layer .finance-dialog-panel, body > .fixed > .relative')).toHaveCount(0)
          continue
        }
        if (title === '安全入口') {
          await modal(page).getByTitle('生成随机路径', { exact: true }).click()
          await expect(page.getByPlaceholder('/your-secret-path', { exact: true })).toHaveValue(/^\//)
          await expect(page.getByText('当前路径尚未保存，保存后生效。', { exact: true })).toBeVisible()
        }
        if (title === 'API Token') {
          const tokenName = `界面验证令牌${Date.now()}`
          await page.getByPlaceholder('例如：我的手机', { exact: true }).fill(tokenName)
          await page.getByRole('button', { name: '创建令牌', exact: true }).click()
          await expect(page.getByText('令牌创建成功！', { exact: true })).toBeVisible()
          const revoke = page.getByRole('button', { name: `撤销令牌 ${tokenName}`, exact: true })
          await revoke.click()
          await page.getByRole('button', { name: '确认撤销', exact: true }).click()
          await expect(revoke).toHaveCount(0)
        }
        if (title === '自动备份') {
          await modal(page).getByRole('button', { name: '立即备份', exact: true }).click()
          await expect(page.getByText('备份已触发', { exact: true })).toBeVisible()
          await modal(page).getByRole('button', { name: '保存设置', exact: true }).click()
          await expect(page.locator('.finance-layer .finance-dialog-panel, body > .fixed > .relative')).toHaveCount(0)
          continue
        }
        await closeModal(page)
      }
      await page.getByRole('button', { name: '关于应用', exact: true }).click()
      await expect(page.getByText('MIT License', { exact: true })).toBeVisible()
      await page.getByRole('button', { name: '知道了', exact: true }).click()
      await page.getByRole('button', { name: '退出登录', exact: true }).click()
      await page.getByRole('dialog', { name: '确认退出', exact: true }).getByRole('button', { name: '退出', exact: true }).click()
      await expect(page).toHaveURL(/\/#\/login$/)
      await expect(page.getByRole('heading', { name: '欢迎回来', exact: true })).toBeVisible()
    })
  })
}
