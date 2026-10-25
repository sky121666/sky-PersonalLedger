import { expect, test } from '@playwright/test'

const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'LedgerWebE2ePass123!'
const routes = [
  'transactions', 'statistics', 'report', 'appearance', 'reminders', 'family',
  'accounts', 'budgets', 'categories', 'tags', 'templates', 'lendings',
  'account-logs', 'ai', 'settings',
]

test.beforeAll(async ({ request }) => {
  expect(process.env.LEDGER_WEB_E2E_ISOLATED).toBe('1')
  const status = await request.get('/api/v1/auth/status')
  expect(status.ok()).toBeTruthy()
  if (!(await status.json()).data.initialized) {
    expect((await request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
})

for (const width of [390, 1440]) {
  for (const theme of ['light', 'dark'] as const) {
    test(`all business headers share hierarchy and reachable actions at ${width}px ${theme}`, async ({ page }) => {
      test.setTimeout(90_000)
      await page.setViewportSize({ width, height: 844 })
      await page.emulateMedia({ reducedMotion: 'reduce' })
      await page.goto('/#/login')
      await page.getByLabel('密码', { exact: true }).fill(password)
      await page.getByRole('button', { name: '解锁', exact: true }).click()
      await expect(page).toHaveURL(/\/#\/$/)
      const errors: string[] = []
      page.on('pageerror', error => errors.push(error.message))
      for (const mode of ['顶部', '侧栏']) {
        await page.goto('/#/appearance')
        await page.getByRole('button', { name: theme === 'dark' ? '深色' : '浅色', exact: true }).click()
        await page.getByRole('button', { name: mode, exact: true }).click()
        for (const route of routes) {
          await test.step(`${mode}/${route}`, async () => {
            await page.goto(`/#/${route}`)
            const header = page.locator('main .finance-page-head')
            await expect(header).toHaveCount(1)
            await expect(header.getByRole('heading', { level: 1 })).toBeVisible()
            await expect(header.getByRole('heading', { level: 1 })).toHaveCSS('font-size', width < 768 ? '20px' : '22px')
            await expect(header).toHaveCSS('position', 'static')
            const geometry = await header.evaluate(el => {
              const bounds = el.getBoundingClientRect()
              const content = el.closest('.finance-frame')!.querySelector('.finance-content')!.getBoundingClientRect()
              return { x: bounds.x, right: bounds.right, width: bounds.width, contentWidth: content.width, overflow: el.scrollWidth - el.clientWidth }
            })
            expect(geometry.x).toBeGreaterThanOrEqual(0)
            expect(geometry.right).toBeLessThanOrEqual(width + 1)
            expect(geometry.overflow).toBeLessThanOrEqual(1)
            expect(Math.abs(geometry.width - geometry.contentWidth)).toBeLessThanOrEqual(1)
            for (const button of await header.getByRole('button').all()) {
              const bounds = (await button.boundingBox())!
              expect(bounds.height).toBeGreaterThanOrEqual(43.99)
              expect(bounds.width).toBeGreaterThanOrEqual(43.99)
              expect(bounds.x).toBeGreaterThanOrEqual(geometry.x - 1)
              expect(bounds.x + bounds.width).toBeLessThanOrEqual(geometry.right + 1)
              expect(await button.evaluate(el => Boolean(el.getAttribute('aria-label') || el.textContent?.trim()))).toBe(true)
            }
            if ((width === 1440 && theme === 'light' && mode === '侧栏')
              || (width === 390 && theme === 'dark' && mode === '顶部')) {
              await page.screenshot({ path: test.info().outputPath(`${route}-${width}-${theme}.png`), animations: 'disabled' })
            }
          })
        }
      }
      expect(errors).toEqual([])
    })
  }
}
