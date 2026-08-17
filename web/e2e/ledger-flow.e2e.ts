import { expect, test } from '@playwright/test'

const e2ePassword = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'

test.describe.configure({ mode: 'serial' })

test.beforeAll(async ({ request }) => {
  const statusResponse = await request.get('/api/v1/auth/status')
  expect(statusResponse.ok()).toBeTruthy()
  const status = await statusResponse.json()

  if (!status.data?.initialized) {
    const initResponse = await request.post('/api/v1/auth/init', {
      data: { password: e2ePassword }
    })
    expect(initResponse.ok()).toBeTruthy()
  }
})

test('desktop completes login and transaction CRUD against the real backend', async ({ page }) => {
  const remark = `Web E2E 午餐 ${Date.now()}`
  const editedRemark = `${remark} 已修改`

  await page.goto('/#/login')
  await expect(page.getByRole('heading', { name: '欢迎回来' })).toBeVisible()

  await page.getByLabel('密码', { exact: true }).fill('wrong-password')
  await page.getByRole('button', { name: '解锁' }).click()
  await expect(page.getByText('密码错误，请重试', { exact: true })).toBeVisible()

  await page.getByLabel('密码', { exact: true }).fill(e2ePassword)
  await page.getByRole('button', { name: '解锁' }).click()
  await expect(page).toHaveURL(/\/#\/$/)
  await expect(page.getByRole('button', { name: '记一笔' })).toBeVisible()

  const quickEntryButton = page.getByRole('button', { name: '记一笔' })
  await quickEntryButton.click()
  let createDialog = page.getByRole('dialog', { name: '新增交易' })
  await expect(createDialog).toBeVisible()
  await expect(createDialog.getByLabel('金额')).toBeFocused()
  await page.keyboard.press('Escape')
  await expect(createDialog).toHaveCount(0)
  await expect(quickEntryButton).toBeFocused()

  await quickEntryButton.click()
  createDialog = page.getByRole('dialog', { name: '新增交易' })
  await expect(createDialog).toBeVisible()
  await createDialog.getByLabel('金额').fill('18.50')
  await createDialog.getByRole('button', { name: '选择餐饮分类' }).click()
  await expect(createDialog.getByLabel('账户')).not.toHaveValue('')
  await createDialog.getByLabel('备注').fill(remark)
  await createDialog.getByRole('button', { name: '保存记录' }).click()
  await expect(page.getByText('记账成功', { exact: true })).toBeVisible()

  await page.getByRole('button', { name: '明细' }).click()
  await expect(page).toHaveURL(/\/#\/transactions$/)
  await expect(page.getByRole('heading', { name: '账单明细' })).toBeVisible()
  await expect(page.getByText(remark, { exact: true })).toBeVisible()
  await expect(page.getByText('-18.50', { exact: true })).toBeVisible()

  await page.getByText(remark, { exact: true }).click()
  const editDialog = page.getByRole('dialog', { name: '编辑交易' })
  await expect(editDialog).toBeVisible()
  await editDialog.getByLabel('金额').fill('19.75')
  await editDialog.getByLabel('备注').fill(editedRemark)
  await editDialog.getByRole('button', { name: '保存记录' }).click()
  await expect(page.getByText('修改成功', { exact: true })).toBeVisible()
  await expect(page.getByText(editedRemark, { exact: true })).toBeVisible()
  await expect(page.getByText('-19.75', { exact: true })).toBeVisible()

  const deleteButton = page.getByRole('button', {
    name: `删除交易 ${editedRemark}`
  })
  await deleteButton.hover()
  await deleteButton.click()
  await expect(page.getByRole('heading', { name: '确认删除' })).toBeVisible()
  await page.getByRole('button', { name: '删除', exact: true }).click()
  await expect(page.getByText('删除成功', { exact: true })).toBeVisible()
  await expect(page.getByText(editedRemark, { exact: true })).toHaveCount(0)
})

test.describe('mobile shell', () => {
  test.use({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true
  })

  test('keeps primary navigation and quick entry reachable', async ({ page }) => {
    await page.goto('/#/login')
    await page.getByLabel('密码', { exact: true }).fill(e2ePassword)
    await page.getByRole('button', { name: '解锁' }).click()
    await expect(page).toHaveURL(/\/#\/$/)

    for (const label of ['首页', '明细', '统计', '我的']) {
      await expect(page.getByRole('button', { name: label, exact: true })).toBeVisible()
    }

    await page.getByRole('button', { name: '记一笔' }).click()
    const dialog = page.getByRole('dialog', { name: '新增交易' })
    await expect(dialog).toBeVisible()
    await expect(dialog.getByLabel('金额')).toBeVisible()
    await expect(dialog.getByLabel('账户')).toBeVisible()
    await dialog.getByRole('button', { name: '关闭交易表单' }).click()
    await expect(dialog).toHaveCount(0)
  })
})
