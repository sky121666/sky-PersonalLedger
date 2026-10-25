import { expect, test } from '@playwright/test'

type MotionSample = { id: string; duration: number | string; activeDuration: number | string; moves: boolean; targetMatches: boolean; finished: boolean; cancelled: boolean }
type MotionWindow = Window & { widgetMotionProbe: MotionSample[] }

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
    const order = () => grid.locator('[data-widget-id]').evaluateAll(elements => elements.map(element => element.getAttribute('data-widget-id')))
    const before = await order()
    expect(before[0]).toBe('net-assets')
    // Observe native Animation objects without replacing their execution or waiting for a lucky frame.
    await grid.locator('[data-widget-id]').evaluateAll(elements => {
      const probe: MotionSample[] = []
      ;(window as unknown as MotionWindow).widgetMotionProbe = probe
      for (const element of elements) {
        const animate = element.animate.bind(element)
        element.animate = (keyframes, options) => {
          const animation = animate(keyframes, options)
          const effect = animation.effect as KeyframeEffect
          const duration = effect.getTiming().duration
          const activeDuration = effect.getComputedTiming().activeDuration
          const transforms = effect.getKeyframes().map(frame => new DOMMatrix(typeof frame.transform === 'string' ? frame.transform : 'none').toString())
          const sample: MotionSample = {
            id: element.getAttribute('data-widget-id')!,
            duration: typeof duration === 'number' ? duration : String(duration),
            activeDuration: typeof activeDuration === 'number' ? activeDuration : String(activeDuration),
            moves: transforms.length >= 2 && transforms[0] !== transforms[transforms.length - 1],
            targetMatches: effect.target === element,
            finished: false,
            cancelled: false,
          }
          probe.push(sample)
          void animation.finished.then(() => { sample.finished = true }, () => { sample.cancelled = true })
          return animation
        }
      }
    })
    await grid.getByRole('button', { name: '拖动净资产', exact: true }).press('ArrowDown')
    await expect.poll(order).toEqual([before[1], before[0], ...before.slice(2)])
    if (reducedMotion === 'no-preference') {
      await expect.poll(() => page.evaluate(() => {
        const samples = (window as unknown as MotionWindow).widgetMotionProbe
        return samples.length > 0 && samples.every(sample => sample.finished && !sample.cancelled)
      })).toBe(true)
    } else {
      // Allow the render and animation microtasks to finish before asserting no motion was started.
      await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))))
    }
    const motion = await page.evaluate(() => (window as unknown as MotionWindow).widgetMotionProbe)
    if (reducedMotion === 'reduce') expect(motion).toEqual([])
    else {
      expect(motion.map(sample => sample.id)).toEqual(expect.arrayContaining(['net-assets', 'accounts']))
      for (const sample of motion) {
        expect(typeof sample.duration).toBe('number')
        expect(Number.isFinite(sample.duration)).toBe(true)
        expect(sample.duration).toBeGreaterThan(0)
        expect(typeof sample.activeDuration).toBe('number')
        expect(Number.isFinite(sample.activeDuration)).toBe(true)
        expect(sample.activeDuration).toBeGreaterThan(0)
        expect(sample.moves).toBe(true)
        expect(sample.targetMatches).toBe(true)
        expect(sample.finished).toBe(true)
        expect(sample.cancelled).toBe(false)
      }
    }
    await test.info().attach('motion-lifecycle', { body: JSON.stringify({ reducedMotion, samples: motion }), contentType: 'application/json' })
    await page.getByRole('button', { name: '取消编辑', exact: true }).click()
    await expect.poll(order).toEqual(before)
  })
}
