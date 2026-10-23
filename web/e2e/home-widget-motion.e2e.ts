import { expect, test } from '@playwright/test'

for (const reducedMotion of ['no-preference', 'reduce'] as const) {
  test(`widget rearrangement respects ${reducedMotion} motion preference`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion })
    await page.setViewportSize({ width: 1440, height: 900 })
    const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'widget-motion-isolated-demo'
    const status = await page.request.get('/api/v1/auth/status')
    if (!(await status.json()).data?.initialized) {
      expect((await page.request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
    }
    await page.goto('/#/login')
    await page.getByLabel('密码', { exact: true }).fill(password)
    await page.getByRole('button', { name: '解锁', exact: true }).click()
    await expect(page).toHaveURL(/\/#\/$/)
    await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
    const grid = page.getByRole('region', { name: '首页小组件' })
    const cell = grid.locator('[data-widget-id="net-assets"]')
    // Sample rendered browser animations; do not mock the animation API.
    await cell.evaluate(element => {
      const probe = { running: false, finished: false }
      ;(window as unknown as { widgetMotionProbe: typeof probe }).widgetMotionProbe = probe
      const started = performance.now()
      function sample() {
        probe.running ||= element.getAnimations().some(animation => animation.playState === 'running')
        if (performance.now() - started < 600) requestAnimationFrame(sample)
        else probe.finished = true
      }
      requestAnimationFrame(sample)
    })
    await grid.getByRole('button', { name: '拖动净资产', exact: true }).press('ArrowDown')
    await expect.poll(() => page.evaluate(() => (window as unknown as { widgetMotionProbe: { finished: boolean } }).widgetMotionProbe.finished)).toBe(true)
    const animated = await page.evaluate(() => (window as unknown as { widgetMotionProbe: { running: boolean } }).widgetMotionProbe.running)
    expect(animated).toBe(reducedMotion === 'no-preference')
    await expect(grid.locator('[data-widget-id]').first()).toHaveAttribute('data-widget-id', 'accounts')
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
    await expect(grid.locator('[data-widget-id]').first()).toHaveAttribute('data-widget-id', 'net-assets')
  })
}
