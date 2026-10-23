import { formatLocalDate } from '@/utils/localDate'

export type AIReportPeriodPreset = 'week_to_date' | 'previous_week' | 'month_to_date' | 'previous_month' | 'custom'

export function aiReportPeriod(preset: Exclude<AIReportPeriodPreset, 'custom'>, now = new Date()) {
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const end = new Date(start)
  if (preset === 'week_to_date' || preset === 'previous_week') {
    start.setDate(start.getDate() - ((start.getDay() || 7) - 1))
    if (preset === 'previous_week') {
      end.setTime(start.getTime())
      end.setDate(end.getDate() - 1)
      start.setDate(start.getDate() - 7)
    }
  } else {
    start.setDate(1)
    if (preset === 'previous_month') {
      end.setTime(start.getTime())
      end.setDate(0)
      start.setMonth(start.getMonth() - 1)
    }
  }
  return { period_start: formatLocalDate(start), period_end: formatLocalDate(end) }
}
