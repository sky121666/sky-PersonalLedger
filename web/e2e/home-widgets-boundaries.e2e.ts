import { expect, test, type Page } from '@playwright/test'

async function openEditor(page: Page, width = 1440) {
  await page.setViewportSize({ width, height: 900 })
  await page.emulateMedia({ reducedMotion: 'no-preference' })
  const password = process.env.LEDGER_WEB_E2E_PASSWORD || 'widget-boundaries-isolated-demo'
  const status = await page.request.get('/api/v1/auth/status')
  if (!(await status.json()).data?.initialized) {
    expect((await page.request.post('/api/v1/auth/init', { data: { password } })).ok()).toBeTruthy()
  }
  await page.goto('/#/login')
  await page.getByLabel('密码', { exact: true }).fill(password)
  await page.getByRole('button', { name: '解锁', exact: true }).click()
  await expect(page).toHaveURL(/\/#\/$/)
  await expect(page.getByRole('article', { name: '净资产', exact: true }).locator('.widget-hero')).toBeVisible()
  await expect(page.getByRole('button', { name: '刷新首页数据', exact: true })).toBeEnabled()
  await page.getByRole('button', { name: '编辑小组件', exact: true }).click()
}
const grid = (page: Page) => page.getByRole('region', { name: '首页小组件' })
const order = (page: Page) => grid(page).locator('[data-widget-id]').evaluateAll(elements => elements.map(element => element.getAttribute('data-widget-id')))

test('grabbing a moving card preserves its painted position and a stationary release does not reorder', async ({ page }) => {
  await openEditor(page)
  const cell = grid(page).locator('[data-widget-id="net-assets"]')
  const handle = cell.getByRole('button', { name: '拖动净资产', exact: true })
  await handle.press('ArrowDown')
  await expect.poll(() => cell.evaluate(element => element.getAnimations().length)).toBeGreaterThan(0)
  await grid(page).evaluate(async element => {
    for (const cell of element.querySelectorAll('[data-widget-id]')) {
      for (const animation of cell.getAnimations()) {
        animation.pause()
        await animation.ready
        animation.currentTime = 100
      }
    }
  })
  const beforeOrder = await order(page)
  const before = (await cell.locator('.widget-renderer').boundingBox())!
  const handleRect = (await handle.boundingBox())!
  await page.mouse.move(handleRect.x + handleRect.width / 2, handleRect.y + handleRect.height / 2)
  await page.mouse.down()
  const ghost = (await page.locator('.widget-drag-preview').boundingBox())!
  expect(Math.abs(ghost.x + ghost.width / 2 - before.x - before.width / 2)).toBeLessThan(2)
  expect(Math.abs(ghost.y + ghost.height / 2 - before.y - before.height / 2)).toBeLessThan(2)
  await page.mouse.up()
  expect(await order(page)).toEqual(beforeOrder)
  await expect(page.locator('.widget-drag-preview')).toHaveCount(0)
})

test('a closing widget menu is inert and cannot duplicate a reopened accessible menu', async ({ page }) => {
  await openEditor(page, 390)
  const trigger = grid(page).getByRole('button', { name: '本月预算选项', exact: true })
  await trigger.click()
  await expect(page.getByRole('region', { name: '本月预算选项菜单', exact: true })).toBeVisible()
  await page.keyboard.press('Escape')
  await trigger.click()
  await expect(page.getByRole('region', { name: '本月预算选项菜单', exact: true })).toHaveCount(1)
  await expect(page.locator('[id="widget-options-budget"]')).toHaveCount(1)
})

test('Escape then Enter during gallery exit cannot add a component', async ({ page }) => {
  await openEditor(page)
  const original = await order(page)
  await page.getByRole('button', { name: '添加小组件', exact: true }).click()
  const gallery = page.getByRole('dialog', { name: '组件画廊' })
  await gallery.getByRole('button', { name: '预览AI 分析', exact: true }).click()
  await gallery.getByRole('button', { name: '添加到首页', exact: true }).focus()
  await page.keyboard.press('Escape')
  await page.keyboard.press('Enter')
  await expect(gallery).toHaveCount(0)
  expect(await order(page)).toEqual(original)
})

test('a menu closes with focus restored when its anchor is clipped by the main scroller', async ({ page }) => {
  await openEditor(page)
  await page.setViewportSize({ width: 1440, height: 600 })
  await page.getByRole('button', { name: '添加小组件', exact: true }).click()
  const gallery = page.getByRole('dialog', { name: '组件画廊' })
  await gallery.getByRole('button', { name: '预览收支日历', exact: true }).click()
  await gallery.getByRole('button', { name: '添加到首页', exact: true }).click()
  await page.keyboard.press('Escape'); await expect(gallery).toHaveCount(0)
  const trigger = grid(page).getByRole('button', { name: '净资产选项', exact: true })
  await trigger.click()
  const menu = page.getByRole('region', { name: '净资产选项菜单', exact: true })
  await expect(menu).toBeVisible()
  const anchorBottom = await trigger.evaluate(element => element.getBoundingClientRect().bottom)
  await page.getByRole('main').evaluate((element, bottom) => {
    element.scrollTop += bottom - element.getBoundingClientRect().top + 20
  }, anchorBottom)
  await expect(menu).toHaveCount(0)
  await expect(trigger).toBeFocused()
})

for (const width of [320, 390]) {
  test(`mobile gallery reveals the selected item and locates a safe control at ${width}px`, async ({ page }) => {
    await openEditor(page, width)
    await page.getByRole('button', { name: '添加小组件', exact: true }).click()
    const gallery = page.getByRole('dialog', { name: '组件画廊' })
    await expect(gallery).toHaveCSS('transform', 'none')
    const visible = await gallery.locator('.widget-gallery-list').evaluate(element => {
      const selected = element.querySelector('[aria-pressed="true"]')!.getBoundingClientRect()
      const bounds = element.getBoundingClientRect()
      return selected.left >= bounds.left - 1 && selected.right <= bounds.right + 1
    })
    expect(visible).toBe(true)
    await gallery.getByRole('button', { name: '定位已有组件', exact: true }).click()
    await expect(grid(page).getByRole('button', { name: '拖动本月预算', exact: true })).toBeFocused()
  })
}
