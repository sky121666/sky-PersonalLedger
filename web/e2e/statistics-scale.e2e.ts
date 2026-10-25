import { expect, test } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
test.beforeAll(async ({ request }) => {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED).toBe('1')
  const status = await request.get('/api/v1/auth/status')
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

for (const width of [390, 1440]) {
  test(`1280 category sectors keep statistics usable at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    const errors: string[] = []
    page.on('pageerror', error => errors.push(error.message))
    const categories = Array.from({ length: 1280 }, (_, index) => ({
      category_id: `scale-${index}`, category_name: `模拟分类${index + 1}`, icon: 'wallet',
      color: index < 640 ? '#007AFF' : '#34C759', percentage: 0.078125, amount: 1, count: 1,
    }))
    await page.route('**/api/v1/statistics/categories*', route => route.fulfill({
      json: { code: 0, data: { total: 1280, items: categories } },
    }))
    await page.goto('/#/login')
    await page.getByLabel('密码', { exact: true }).fill(password)
    await page.getByRole('button', { name: '解锁', exact: true }).click()
    await expect(page).toHaveURL(/\/#\/$/)
    await page.goto('/#/statistics')
    await expect(page.getByRole('heading', { name: '统计分析', exact: true })).toBeVisible()
    await expect(page.getByText('模拟分类1280', { exact: true })).toHaveCount(1)
    await page.locator('.statistics-ring-details summary').click()
    await expect(page.getByText('¥1,280.00', { exact: true })).toBeVisible()
    const ring = page.locator('[style*="conic-gradient"]').first()
    expect(await ring.evaluate(element => (element as HTMLElement).style.background.length)).toBeLessThan(256)
    await ring.scrollIntoViewIfNeeded()
    await page.screenshot({ path: test.info().outputPath(`category-scale-${width}.png`), animations: 'disabled' })
    const heading = page.locator('main .finance-page-head')
    const initialMonth = await heading.textContent()
    await page.getByRole('button', { name: '上个月', exact: true }).click()
    await expect(heading).not.toHaveText(initialMonth!)
    await page.getByRole('button', { name: '收入', exact: true }).click()
    await expect(page.getByText('模拟分类1280', { exact: true })).toHaveCount(1)
    expect(errors).toEqual([])
  })
}
