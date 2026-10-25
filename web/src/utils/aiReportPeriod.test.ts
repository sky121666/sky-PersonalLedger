import { describe, expect, it } from 'vitest'
import { aiReportPeriod, type AIReportPeriodPreset } from './aiReportPeriod'

describe('AI report local calendar presets', () => {
  it.each<{
    preset: Exclude<AIReportPeriodPreset, 'custom'>
    now: Date
    start: string
    end: string
  }>([
    { preset: 'week_to_date', now: new Date(2026, 9, 22), start: '2026-10-19', end: '2026-10-22' },
    { preset: 'week_to_date', now: new Date(2026, 9, 25), start: '2026-10-19', end: '2026-10-25' },
    { preset: 'previous_week', now: new Date(2026, 0, 1), start: '2025-12-22', end: '2025-12-28' },
    { preset: 'month_to_date', now: new Date(2026, 9, 22), start: '2026-10-01', end: '2026-10-22' },
    { preset: 'previous_month', now: new Date(2026, 0, 31), start: '2025-12-01', end: '2025-12-31' },
    { preset: 'previous_month', now: new Date(2024, 2, 31), start: '2024-02-01', end: '2024-02-29' }
  ])('$preset on $now', ({ preset, now, start, end }) => {
    const original = now.getTime()
    expect(aiReportPeriod(preset, now)).toEqual({ period_start: start, period_end: end })
    expect(now.getTime()).toBe(original)
  })
})
