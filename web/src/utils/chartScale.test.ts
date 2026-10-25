import { describe, expect, it } from 'vitest'
import { chartAxisLimit, chartBarPercent } from './chartScale'

describe('financial chart scales', () => {
  it('leaves room above the maximum using one shared axis', () => {
    const limit = chartAxisLimit(15860)
    expect(limit).toBe(20000)
    expect(chartBarPercent(15860, limit)).toBe(79.3)
    expect(chartBarPercent(4094, limit)).toBeCloseTo(20.47)
  })
  it('does not inflate a zero or a small value to a visual minimum', () => {
    expect(chartBarPercent(0, chartAxisLimit(1000))).toBe(0)
    expect(chartBarPercent(1, 20000)).toBe(.005)
    expect(chartBarPercent(Number.NaN, 10)).toBe(0)
    expect(chartAxisLimit(0)).toBe(1)
  })
})
