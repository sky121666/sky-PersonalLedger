import { expect, test, type APIRequestContext, type Page, type TestInfo } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
type Call = (path: string, method?: string, data?: unknown) => Promise<any>

test.beforeAll(async ({ request }) => {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED, 'debt write tests require the isolated ledger runner').toBe('1')
  const status = await request.get('/api/v1/auth/status')
  expect(status.ok()).toBeTruthy()
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

async function api(request: APIRequestContext): Promise<Call> {
  const login = await request.post('/api/v1/auth/login', { data: { password } })
  expect(login.ok()).toBeTruthy()
  const headers = { Authorization: `Bearer ${(await login.json()).data.access_token}` }
  return async (path, method = 'GET', data) => {
    const response = await request.fetch(`/api/v1${path}`, { method, headers, data })
    expect(response.ok(), `${method} ${path}: ${response.status()}`).toBeTruthy()
    return (await response.json()).data
  }
}

async function login(page: Page) {
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
}

function dialog(page: Page, title: string) { return page.getByRole('dialog', { name: title, exact: true }) }
function name(info: TestInfo) { return `模拟${info.project.name}-${info.title.slice(0, 7)}-${Date.now()}` }
async function fit(page: Page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width)
  await expect.poll(() => page.locator('main').first().evaluate(element => element.scrollWidth - element.clientWidth)).toBeLessThanOrEqual(1)
  const modal = page.getByRole('dialog')
  if (await modal.count()) {
    await expect.poll(async () => { const bounds = (await modal.boundingBox())!; return bounds.y + bounds.height }).toBeLessThanOrEqual(page.viewportSize()!.height + 1)
    const bounds = await modal.boundingBox()
    expect(bounds!.x).toBeGreaterThanOrEqual(0)
    expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(page.viewportSize()!.width + 1)
    expect(bounds!.y + bounds!.height).toBeLessThanOrEqual(page.viewportSize()!.height + 1)
  }
}
async function capture(page: Page, info: TestInfo, file: string) {
  await fit(page)
  await page.screenshot({ path: info.outputPath(file), animations: 'disabled' })
}
async function newPlan(page: Page, label: string, amount: string) {
  await page.getByRole('button', { name: '新建计划', exact: true }).click()
  const form = dialog(page, '新建分期计划')
  await form.getByLabel('计划名称', { exact: true }).fill(label)
  await form.getByLabel('原始本金', { exact: true }).fill(amount)
  await form.getByLabel('开始追踪时本金', { exact: true }).fill(amount)
  await form.getByRole('button', { name: '保存计划', exact: true }).click()
  await expect(form).toHaveCount(0)
  await expect(page.getByRole('article', { name: `分期 ${label}`, exact: true })).toBeVisible()
}
async function openReceipt(page: Page, call: Call, id: string) {
  const detail = await call(`/debt/operations/${id}`)
  const label: Record<string, string> = { payment: '登记付款', plan_open: '建立计划', interest_charge: '利息入账', allocation: '付款分配', transfer_payment: '转账待分配' }
  await page.getByRole('button', { name: `查看凭证 ${label[detail.operation.kind]} ${id}`, exact: true }).click()
  await expect(dialog(page, '分期操作凭证').getByText(`凭证号 ${id}`, { exact: true })).toBeVisible()
}
async function reverse(page: Page, call: Call, id: string) {
  await openReceipt(page, call, id)
  await dialog(page, '分期操作凭证').getByRole('button', { name: '撤销此操作', exact: true }).click()
  const form = dialog(page, '撤销分期操作')
  await form.getByRole('button', { name: '确认撤销', exact: true }).click()
  await expect(form).toHaveCount(0)
}
async function fixture(call: Call, label: string, balance = 1000, cashAmount = 5000) {
  const cash = await call('/accounts', 'POST', { name: `${label}资金`, type: 'cash', initial_balance: cashAmount })
  const card = await call('/accounts', 'POST', { name: `${label}信用`, type: 'credit', initial_balance: balance, debt_tracking_mode: 'managed' })
  return { cash, card }
}
async function createPlan(call: Call, account: string, label: string, amount: number) {
  return call('/debt/plans', 'POST', { name: label, scope: 'account', account_id: account,
    original_principal: amount, opening_principal: amount, idempotency_key: crypto.randomUUID() })
}

for (const width of [390, 1440]) {
  test.describe(`${width}px isolated multi-installment`, () => {
    test.use({ viewport: { width, height: 844 } })
    test.beforeEach(async ({ page }) => {
      page.setDefaultTimeout(10_000)
      await page.emulateMedia({ reducedMotion: 'reduce' })
      await login(page)
    })

    test('uses one debt entry for account plans and legacy reminders while keeping old receipt links', async ({ page, request }, info) => {
      const call = await api(request)
      const label = name(info)
      const { card } = await fixture(call, label)
      const legacy = await call('/accounts', 'POST', { name: `${label}旧信用卡`, type: 'credit', initial_balance: 300 })
      const first = await createPlan(call, card.id, `${label}家电`, 600)
      const second = await createPlan(call, card.id, `${label}旅行`, 300)
      const reminder = await call('/reminders', 'POST', {
        name: `${label}旧提醒`, account_id: legacy.id, loan_type: 'credit_card', payment_day: 15, advance_days: 3,
      })
      await page.goto('/#/accounts')
      await page.getByRole('link', { name: /^负债管理/ }).click()
      await expect(page).toHaveURL(/\/#\/reminders$/)
      await expect(page.getByRole('heading', { name: '负债管理', exact: true })).toBeVisible()
      await expect(page.getByRole('link', { name: /^多分期管理/ })).toHaveCount(0)
      await page.getByRole('button', { name: '分期账户范围', exact: true }).click()
      await page.locator(`[role="option"][value="${card.id}"]`).click()
      await expect(page.getByRole('article', { name: `分期 ${first.name}`, exact: true })).toBeVisible()
      await expect(page.getByRole('article', { name: `分期 ${second.name}`, exact: true })).toBeVisible()
      await capture(page, info, 'unified-account-plans.png')

      await page.getByRole('button', { name: '还款提醒', exact: true }).click()
      await expect(page.getByText(reminder.name, { exact: true })).toBeVisible()
      await page.getByRole('button', { name: '添加提醒', exact: true }).click()
      const form = dialog(page, '添加提醒')
      const choices = await form.getByLabel('提醒关联账户', { exact: true }).locator('option').evaluateAll(options => options.map(option => (option as HTMLOptionElement).value))
      expect(choices).toContain(legacy.id)
      expect(choices).not.toContain(card.id)
      await capture(page, info, 'unified-legacy-reminder.png')
      await form.getByRole('button', { name: '关闭添加提醒', exact: true }).click()
      await page.getByRole('button', { name: '账户与分期', exact: true }).click()
      await expect(page.getByRole('button', { name: '分期账户范围', exact: true })).toHaveAttribute('data-value', card.id)
      expect((await call(`/accounts/${legacy.id}`)).debt_tracking_mode).toBe('legacy')
      expect((await call(`/accounts/${card.id}`)).current_balance).toBe(1000)

      const operation = (await call(`/debt/operations?account_id=${card.id}`)).find((item: any) => item.kind === 'plan_open')
      await page.goto(`/#/debt?account_id=${card.id}&operation_id=${operation.id}`)
      await expect(page).toHaveURL(new RegExp(`/reminders\\?account_id=${card.id}&operation_id=${operation.id}$`))
      await expect(dialog(page, '分期操作凭证')).toContainText(`凭证号 ${operation.id}`)
      await dialog(page, '分期操作凭证').getByRole('button', { name: '关闭', exact: true }).click()
      await page.goto('/#/settings')
      await expect(page.getByRole('button', { name: '负债管理', exact: true })).toHaveCount(0)
      await page.getByRole('button', { name: width < 768 ? '更多导航' : '打开更多导航', exact: true }).click()
      await page.getByRole('region', { name: '更多功能', exact: true }).getByRole('link', { name: '负债', exact: true }).click()
      await expect(page).toHaveURL(/\/#\/reminders$/)
    })

    test('dismisses teleported dialogs when browser history changes the debt section', async ({ page, request }, info) => {
      const call = await api(request)
      const label = name(info)
      const legacy = await call('/accounts', 'POST', { name: `${label}旧卡`, type: 'credit', initial_balance: 300 })
      const reminder = await call('/reminders', 'POST', {
        name: `${label}提醒`, account_id: legacy.id, loan_type: 'credit_card', payment_day: 15,
        advance_days: 3, principal: 300, current_balance: 300,
      })
      await page.goto(`/#/reminders?account_id=${legacy.id}`)
      for (const [action, title] of [
        [`编辑提醒 ${reminder.name}`, '编辑提醒'],
        ['+ 记录还款', '记录还款'],
        [`删除提醒 ${reminder.name}`, '确认删除'],
      ]) {
        await page.getByRole('link', { name: '查看还款提醒', exact: true }).click()
        await expect(page.getByRole('heading', { name: '还款提醒', exact: true })).toBeVisible()
        await page.locator('.group').filter({ hasText: reminder.name }).first().getByRole('button', { name: action, exact: true }).click()
        await expect(page.getByRole('heading', { name: title, exact: true })).toBeVisible()
        await page.goBack()
        await expect(page.getByRole('heading', { name: '账户与分期', exact: true })).toBeVisible()
        await expect(page.getByRole('heading', { name: title, exact: true })).toHaveCount(0)
        await expect(page.getByRole('button', { name: '分期账户范围', exact: true })).toHaveAttribute('data-value', legacy.id)
      }
      expect((await call(`/accounts/${legacy.id}`)).current_balance).toBe(300)
      expect((await call('/reminders')).some((item: any) => item.id === reminder.id)).toBe(true)

      const { card } = await fixture(call, `${label}新卡`)
      await page.goto('/#/reminders?view=reminders')
      await expect(page.getByRole('heading', { name: '还款提醒', exact: true })).toBeVisible()
      await page.goto(`/#/reminders?account_id=${card.id}`)
      await page.getByRole('button', { name: '新建计划', exact: true }).click()
      await expect(dialog(page, '新建分期计划')).toBeVisible()
      await page.goBack()
      await expect(page.getByRole('heading', { name: '还款提醒', exact: true })).toBeVisible()
      await expect(dialog(page, '新建分期计划')).toHaveCount(0)
    })

    test('creates managed account, pays, reallocates and reverses without overwriting later cash', async ({ page, request }, info) => {
      test.setTimeout(120_000)
      const call = await api(request)
      const label = name(info)
      const cash = await call('/accounts', 'POST', { name: `${label}资金`, type: 'cash', initial_balance: 5000 })
      await page.goto('/#/accounts')
      await page.getByRole('button', { name: '添加新账户', exact: true }).click()
      const accountForm = dialog(page, '添加新卡')
      await accountForm.getByPlaceholder('例如：招商银行', { exact: true }).fill(label)
      await accountForm.getByLabel('账户类型', { exact: true }).selectOption('credit')
      await accountForm.getByLabel('负债管理方式', { exact: true }).selectOption('managed')
      await accountForm.getByPlaceholder('0.00', { exact: true }).fill('1000')
      await accountForm.getByRole('button', { name: '保存卡片', exact: true }).click()
      await expect(page.getByRole('heading', { name: '负债管理', exact: true })).toBeVisible()
      const card = (await call('/accounts')).list.find((item: any) => item.name === label)
      expect(card.debt_tracking_mode).toBe('managed')
      const a = `${label}家电`, b = `${label}旅行`
      await newPlan(page, a, '600')
      await newPlan(page, b, '300')
      expect((await call(`/accounts/${card.id}`)).current_balance).toBe(1000)
      const plans = await call('/debt/plans')
      const pa = plans.find((item: any) => item.name === a), pb = plans.find((item: any) => item.name === b)
      await page.getByRole('button', { name: '登记付款', exact: true }).click()
      const pay = dialog(page, '登记付款')
      await pay.getByLabel('本次付款金额', { exact: true }).fill('120')
      await pay.getByLabel('付款账户', { exact: true }).selectOption(cash.id)
      await pay.getByLabel(`${a} 本金`, { exact: true }).fill('60')
      await pay.getByLabel(`${a} 当次利息`, { exact: true }).fill('10')
      await pay.getByLabel(`${b} 本金`, { exact: true }).fill('40')
      await pay.getByLabel('暂不分配金额', { exact: true }).fill('10')
      await capture(page, info, 'payment-parts.png')
      await pay.getByRole('button', { name: '确认付款', exact: true }).click()
      await expect(pay).toHaveCount(0)
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(4880)
      expect((await call(`/accounts/${card.id}`)).current_balance).toBe(890)
      const payment = (await call(`/debt/operations?account_id=${card.id}`)).find((item: any) => item.kind === 'payment')
      await openReceipt(page, call, payment.id)
      await expect(dialog(page, '分期操作凭证')).toContainText('¥10.00')
      await dialog(page, '分期操作凭证').getByRole('button', { name: '分配付款', exact: true }).click()
      const allocation = dialog(page, '分配付款')
      await allocation.getByLabel(`${b} 本金`, { exact: true }).fill('10')
      await allocation.getByRole('button', { name: '确认分配', exact: true }).click()
      await expect(allocation).toHaveCount(0)
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(4880)
      expect((await call(`/debt/plans/${pb.id}`)).principal_balance).toBe(250)
      await openReceipt(page, call, payment.id)
      await dialog(page, '分期操作凭证').getByRole('button', { name: '重新分配', exact: true }).click()
      const replacement = dialog(page, '重新分配')
      await replacement.getByLabel(`${b} 本金`, { exact: true }).fill('0')
      await replacement.getByLabel(`${a} 本金`, { exact: true }).fill('10')
      await replacement.getByRole('button', { name: '确认分配', exact: true }).click()
      await expect(replacement).toHaveCount(0)
      expect((await call(`/debt/plans/${pa.id}`)).principal_balance).toBe(530)
      expect((await call(`/debt/plans/${pb.id}`)).principal_balance).toBe(260)
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(4880)
      const transactions = (await call(`/transactions?account_id=${cash.id}&page_size=100`)).list
      expect(transactions.filter((item: any) => item.source === 'debt_interest').reduce((sum: number, item: any) => sum + item.amount, 0)).toBe(10)
      await call('/transactions', 'POST', { type: 'expense', account_id: cash.id, amount: 7, transaction_date: new Date().toISOString() })
      await reverse(page, call, payment.id)
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(4993)
      expect((await call(`/accounts/${card.id}`)).current_balance).toBe(1000)
      expect((await call(`/debt/plans/${pa.id}`)).principal_balance).toBe(600)
      expect((await call(`/debt/plans/${pb.id}`)).principal_balance).toBe(300)
      await capture(page, info, 'reversed-plans.png')
    })

    test('confirms a committed payment after a lost response and a rate-limited confirmation using the original key', async ({ page, request }) => {
      const call = await api(request)
      const { cash, card } = await fixture(call, `丢响应${width}-${Date.now()}`, 100, 200)
      const plan = await createPlan(call, card.id, '丢响应模拟计划', 100)
      await page.goto(`/#/debt?account_id=${card.id}`)
      await expect(page.getByRole('article', { name: `分期 ${plan.name}`, exact: true })).toBeVisible()
      let dropped = false
      const bodies: any[] = []
      await page.route('**/api/v1/debt/payments', async route => {
        bodies.push(route.request().postDataJSON())
        if (!dropped) {
          dropped = true
          const response = await route.fetch()
          expect(response.ok()).toBeTruthy()
          await route.abort('failed')
        } else if (bodies.length === 2) {
          await route.fulfill({ status: 429, json: { code: 429, message: 'too many requests' } })
        } else await route.continue()
      })
      await page.getByRole('button', { name: '登记付款', exact: true }).click()
      const form = dialog(page, '登记付款')
      await form.getByLabel('本次付款金额', { exact: true }).fill('10')
      await form.getByLabel('付款账户', { exact: true }).selectOption(cash.id)
      await form.getByLabel(`${plan.name} 本金`, { exact: true }).fill('10')
      await form.getByRole('button', { name: '确认付款', exact: true }).click()
      await expect(form.getByRole('status')).toContainText('尚未确认')
      await form.getByRole('button', { name: '关闭并保留待确认请求', exact: true }).click()
      await expect(page.getByRole('heading', { name: '账户与分期', exact: true })).toBeFocused()
      await page.getByRole('button', { name: '还款提醒', exact: true }).click()
      await expect(page.getByRole('button', { name: '添加提醒', exact: true })).toBeVisible()
      await page.getByRole('button', { name: '账户与分期', exact: true }).click()
      await expect(page.getByRole('button', { name: '新建计划', exact: true })).toBeDisabled()
      await expect(page.getByText('上次操作结果尚未确认', { exact: true })).toBeVisible()
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(190)
      await page.reload()
      await page.getByRole('button', { name: '确认上次操作结果', exact: true }).click()
      await expect(page.getByText('上次操作结果尚未确认', { exact: true })).toBeVisible()
      await expect(page.getByRole('button', { name: '新建计划', exact: true })).toBeDisabled()
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(190)
      await page.reload()
      await page.getByRole('button', { name: '确认上次操作结果', exact: true }).click()
      await expect(page.getByText('上次操作结果尚未确认', { exact: true })).toHaveCount(0)
      expect(bodies).toHaveLength(3)
      expect(bodies[1]).toEqual(bodies[0])
      expect(bodies[2]).toEqual(bodies[0])
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(190)
      expect((await call(`/accounts/${card.id}`)).current_balance).toBe(90)
    })

    test('books and pays interest once, reverses it, then cancels an unused plan', async ({ page, request }) => {
      const call = await api(request)
      const { cash, card } = await fixture(call, `纯利息${width}-${Date.now()}`, 100, 200)
      const plan = await createPlan(call, card.id, '纯利息模拟计划', 100)
      await page.goto(`/#/debt?account_id=${card.id}`)
      await page.getByRole('article', { name: `分期 ${plan.name}`, exact: true }).getByRole('button', { name: '利息入账', exact: true }).click()
      const charge = dialog(page, '登记已入账利息')
      await charge.getByLabel('本次入账利息', { exact: true }).fill('5')
      await charge.getByRole('button', { name: '确认入账', exact: true }).click()
      await expect(charge).toHaveCount(0)
      expect((await call(`/accounts/${card.id}`)).current_balance).toBe(105)
      await page.getByRole('button', { name: '登记付款', exact: true }).click()
      const pay = dialog(page, '登记付款')
      await pay.getByLabel('本次付款金额', { exact: true }).fill('5')
      await pay.getByLabel('付款来源', { exact: true }).selectOption('external')
      await pay.getByLabel(`${plan.name} 当次利息`, { exact: true }).fill('5')
      await pay.getByRole('button', { name: '确认付款', exact: true }).click()
      await expect(pay.getByRole('alert')).toContainText('外部来源')
      await pay.getByLabel(`${plan.name} 当次利息`, { exact: true }).fill('0')
      await pay.getByLabel(`${plan.name} 已入账利息`, { exact: true }).fill('5')
      await pay.getByLabel('付款来源', { exact: true }).selectOption('account')
      await pay.getByLabel('付款账户', { exact: true }).selectOption(cash.id)
      await pay.getByRole('button', { name: '确认付款', exact: true }).click()
      await expect(pay).toHaveCount(0)
      expect((await call(`/debt/plans/${plan.id}`)).principal_balance).toBe(100)
      const rows = (await call(`/transactions?account_id=${card.id}&page_size=100`)).list
      expect(rows.filter((row: any) => row.source === 'debt_interest').reduce((sum: number, row: any) => sum + row.amount, 0)).toBe(5)
      const ops = await call(`/debt/operations?account_id=${card.id}`)
      await reverse(page, call, ops.find((op: any) => op.kind === 'payment').id)
      expect((await call(`/accounts/${card.id}`)).current_balance).toBe(105)
      expect((await call(`/debt/plans/${plan.id}`)).principal_balance).toBe(100)
      await reverse(page, call, ops.find((op: any) => op.kind === 'interest_charge').id)
      await reverse(page, call, ops.find((op: any) => op.kind === 'plan_open').id)
      expect((await call(`/debt/plans/${plan.id}`)).status).toBe('cancelled')
      expect((await call(`/accounts/${card.id}`)).unplanned_debt).toBe(100)
    })

    test('links an ordinary transfer to deferred allocation through the transaction receipt', async ({ page, request }) => {
      test.setTimeout(120_000)
      const call = await api(request)
      const { cash, card } = await fixture(call, `转账${width}-${Date.now()}`, 100, 200)
      const plan = await createPlan(call, card.id, '转账模拟计划', 100)
      const remark = `普通转入模拟${Date.now()}`
      const transfer = await call('/transactions', 'POST', { type: 'transfer', account_id: cash.id, to_account_id: card.id, amount: 10, transaction_date: new Date().toISOString(), remark })
      await page.goto('/#/transactions')
      await page.getByPlaceholder('搜索', { exact: true }).fill(remark)
      await page.getByRole('button', { name: `查看分期凭证 ${remark}`, exact: true }).click()
      await expect(dialog(page, '分期操作凭证')).toBeVisible()
      await expect(page.getByRole('dialog', { name: '编辑交易', exact: true })).toHaveCount(0)
      await dialog(page, '分期操作凭证').getByRole('button', { name: '分配付款', exact: true }).click()
      const allocation = dialog(page, '分配付款')
      await allocation.getByLabel(`${plan.name} 本金`, { exact: true }).fill('10')
      await allocation.getByRole('button', { name: '确认分配', exact: true }).click()
      await expect(allocation).toHaveCount(0)
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(190)
      expect((await call(`/accounts/${card.id}`)).current_balance).toBe(90)
      expect((await call(`/debt/plans/${plan.id}`)).principal_balance).toBe(90)
      for (let i = 0; i < 101; i++) {
        await call(`/debt/plans/${plan.id}/interest`, 'POST', { amount: 0.01, idempotency_key: crypto.randomUUID() })
      }
      expect((await call(`/debt/operations?account_id=${card.id}`)).some((op: any) => op.id === transfer.debt_operation_id)).toBe(false)
      const sourceLog = (await call(`/account-logs/account/${cash.id}`)).list.find((item: any) => item.debt_operation_id === transfer.debt_operation_id)
      await page.goto(`/#/account-logs/${cash.id}`)
      await page.getByRole('link', { name: `查看分期凭证 ${sourceLog.id}`, exact: true }).click()
      await expect(dialog(page, '分期操作凭证').getByText(`凭证号 ${transfer.debt_operation_id}`, { exact: true })).toBeVisible()
      await dialog(page, '分期操作凭证').getByRole('button', { name: '撤销此操作', exact: true }).click()
      await dialog(page, '撤销分期操作').getByRole('button', { name: '确认撤销', exact: true }).click()
      await expect(dialog(page, '撤销分期操作')).toHaveCount(0)
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(200)
      expect((await call(`/debt/plans/${plan.id}`)).principal_balance).toBe(100)
      expect((await call(`/debt/plans/${plan.id}`)).interest_balance).toBe(1.01)
    })

    test('handles an independent plan without inventing a debt account', async ({ page, request }) => {
      const call = await api(request)
      const label = `独立${width}-${Date.now()}`
      const cash = await call('/accounts', 'POST', { name: `${label}资金`, type: 'cash', initial_balance: 100 })
      const count = (await call('/accounts')).list.length
      await page.goto('/#/debt?account_id=standalone')
      await newPlan(page, label, '70')
      const plan = (await call('/debt/plans')).find((item: any) => item.name === label)
      expect(plan.account_id).toBeNull()
      expect((await call('/accounts')).list).toHaveLength(count)
      await page.getByRole('article', { name: `分期 ${label}`, exact: true }).getByRole('button', { name: '登记付款', exact: true }).click()
      const pay = dialog(page, '登记付款')
      await pay.getByLabel('本次付款金额', { exact: true }).fill('12')
      await pay.getByLabel('付款账户', { exact: true }).selectOption(cash.id)
      await pay.getByLabel(`${label} 本金`, { exact: true }).fill('10')
      await pay.getByLabel(`${label} 当次利息`, { exact: true }).fill('2')
      await pay.getByRole('button', { name: '确认付款', exact: true }).click()
      await expect(pay).toHaveCount(0)
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(88)
      const op = (await call('/debt/operations')).find((item: any) => item.kind === 'payment' && item.standalone_plan_id === plan.id)
      await reverse(page, call, op.id)
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(100)
      expect((await call(`/debt/plans/${plan.id}`)).principal_balance).toBe(70)
    })

    test('keeps legacy account creation compatible when the old backend has no debt capability', async ({ page, request }) => {
      const call = await api(request)
      const label = `旧模式${width}-${Date.now()}`
      await page.route('**/api/v1/debt/capabilities', route => route.fulfill({ status: 404, json: { code: 404, message: 'not found' } }))
      let body: any
      await page.route('**/api/v1/accounts', async route => {
        if (route.request().method() === 'POST') body = route.request().postDataJSON()
        await route.continue()
      })
      await page.goto('/#/accounts')
      await expect(page.getByRole('link', { name: /^负债管理/ })).toBeVisible()
      await page.getByRole('button', { name: '添加新账户', exact: true }).click()
      const form = dialog(page, '添加新卡')
      await form.getByPlaceholder('例如：招商银行', { exact: true }).fill(label)
      await form.getByLabel('账户类型', { exact: true }).selectOption('credit')
      await expect(form.getByLabel('负债管理方式', { exact: true })).toHaveCount(0)
      await form.getByRole('button', { name: '保存卡片', exact: true }).click()
      await expect(form).toHaveCount(0)
      expect(body).not.toHaveProperty('debt_tracking_mode')
      expect((await call('/accounts')).list.find((item: any) => item.name === label).debt_tracking_mode).toBe('legacy')
      await page.goto('/#/debt')
      await expect(page.getByRole('heading', { name: '当前后端尚未开放多分期管理', exact: true })).toBeVisible()
      await fit(page)
    })

    test('finds and reverses old external standalone receipts through scoped history and pagination', async ({ page, request }, info) => {
      test.setTimeout(120_000)
      const call = await api(request)
      const label = `独立历史${width}-${Date.now()}`
      const plan = await call('/debt/plans', 'POST', { name: label, scope: 'standalone',
        original_principal: 100, opening_principal: 100, idempotency_key: crypto.randomUUID() })
      const payment = await call('/debt/payments', 'POST', { standalone_plan_id: plan.id, source_kind: 'external',
        amount: 10, allocations: [{ plan_id: plan.id, principal: 10 }], idempotency_key: crypto.randomUUID() })
      const interest = await call(`/debt/plans/${plan.id}/interest`, 'POST', { amount: 5, idempotency_key: crypto.randomUUID() })
      for (let i = 0; i < 101; i++) {
        await call(`/debt/plans/${plan.id}/interest`, 'POST', { amount: 0.01, idempotency_key: crypto.randomUUID() })
      }
      const { cash, card } = await fixture(call, `${label}其他`, 100, 200)
      const unrelated = await createPlan(call, card.id, `${label}其他计划`, 100)
      for (let i = 0; i < 100; i++) {
        await call(`/debt/plans/${unrelated.id}/interest`, 'POST', { amount: 0.01, idempotency_key: crypto.randomUUID() })
      }
      expect((await call('/debt/operations')).some((op: any) => op.id === payment.id)).toBe(false)
      await page.goto('/#/debt')
      await page.getByRole('article', { name: `分期 ${label}`, exact: true }).getByRole('button', { name: '操作凭证', exact: true }).click()
      await expect(page.getByLabel('分期凭证范围', { exact: true })).toHaveValue(plan.id)
      await page.getByRole('button', { name: '加载更早凭证', exact: true }).click()
      await expect(page.getByRole('button', { name: `查看凭证 登记付款 ${payment.id}`, exact: true })).toBeVisible()
      await capture(page, info, 'older-standalone-receipts.png')
      await reverse(page, call, payment.id)
      expect((await call(`/debt/plans/${plan.id}`)).principal_balance).toBe(100)
      await page.getByRole('button', { name: '加载更早凭证', exact: true }).click()
      await reverse(page, call, interest.id)
      expect((await call(`/debt/plans/${plan.id}`)).interest_balance).toBe(1.01)
      expect((await call(`/accounts/${cash.id}`)).current_balance).toBe(200)
      await fit(page)
    })

    test('renders long content and keyboard dialogs in light and dark themes', async ({ page, request }, info) => {
      const errors: string[] = []
      page.on('pageerror', error => errors.push(error.message))
      const call = await api(request)
      const { card } = await fixture(call, `主题${width}-${Date.now()}`, 100, 200)
      const label = '较长名称用于检查手机上的换行与金额输入'.repeat(4)
      await createPlan(call, card.id, label, 100)
      for (const theme of ['light', 'dark']) {
        await page.evaluate(value => localStorage.setItem('theme', value), theme)
        // One document navigation applies the theme without aborting an
        // in-flight authentication request with a second immediate reload.
        await page.goto(`/?e2e_theme=${theme}#/debt?account_id=${card.id}`)
        await expect(page.getByRole('article', { name: `分期 ${label}`, exact: true })).toBeVisible()
        const panel = page.getByRole('region', { name: '分期余额概览', exact: true })
        await expect(panel).toHaveCSS('background-color', theme === 'dark' ? 'rgba(28, 28, 30, 0.92)' : 'rgba(255, 255, 255, 0.84)')
        await capture(page, info, `plans-${theme}.png`)
        const trigger = page.getByRole('button', { name: '新建计划', exact: true })
        await trigger.click()
        const modal = dialog(page, '新建分期计划')
        await modal.getByLabel('计划名称', { exact: true }).focus()
        await capture(page, info, `plan-dialog-${theme}.png`)
        await page.keyboard.press('Escape')
        await expect(modal).toHaveCount(0)
        await expect(trigger).toBeFocused()
      }
      expect(errors).toEqual([])
    })
  })
}
