import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { createHomeReadModels, getReminderReadModel } from '@/components/home/readModels'
import type { DebtSummary } from '@/api/reminder'

const debt: DebtSummary = {
  total_debt: 75, total_paid: 25, total_principal: 100, progress: 25,
  active_loans: 1, paid_off_loans: 0, next_payment_day: 22,
  next_payment_name: '房贷', days_until_next: 4,
}

describe('home reminder widget contract', () => {
  it('labels reminder scope honestly and never invents a next-payment amount', () => {
    const model = getReminderReadModel(debt)
    expect(model).toMatchObject({ scope: '还款提醒，不含账户分期', nextName: '房贷', daysUntil: 4, scheduledDay: 22, progress: 25 })
    expect(model).not.toHaveProperty('nextAmount')
    const widget = readFileSync('src/components/home/widgets/ReminderWidget.vue', 'utf8')
    expect(widget).toContain('还款提醒，不含账户分期')
    expect(widget).not.toMatch(/600\.00|nextAmount/)
  })

  it('uses the existing debt-management section as its destination', () => {
    const home = readFileSync('src/views/HomeView.vue', 'utf8')
    expect(home).toContain("reminders: { path: '/reminders', query: { view: 'reminders' } }")
    expect(createHomeReadModels({ debt }).reminders.data?.nextName).toBe('房贷')
  })

  it('does not treat an inactive reminder as today', () => {
    expect(getReminderReadModel({ ...debt, next_payment_name: '' })).toBeNull()
  })
})
