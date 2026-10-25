import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import type { AccountListResponse } from '@/api/account'
import type { Transaction } from '@/api/transaction'
import { createHomeReadModels, getReminderReadModel } from './readModels'

const files = [
  'src/components/home/WidgetFrame.vue',
  'src/components/home/HomeWidget.vue',
  ...['NetAssets','MonthlyFlow','Budget','Reminder','Accounts','Transactions','Account','Calendar','Lending','Family','AI'].map(name => `src/components/home/widgets/${name}Widget.vue`),
]
const accounts: AccountListResponse = {
  list: [{ id: 'cash', name: '现金', type: 'cash', icon: 'wallet', color: '#007AFF', initial_balance: 0, current_balance: 300, total_paid: 0, is_archived: false, sort_order: 0 }],
  total_assets: 300, total_liabilities: 0, net_assets: 300,
}
const transfer: Transaction = { id: 't', type: 'transfer', amount: 20, account_id: 'a', to_account_id: 'b', category_id: null, transaction_date: '2026-10-20', remark: '', images: '', tags: '', source: 'manual', recurring_id: null }

describe('all approved widget renderers', () => {
  it('has a component for every catalog kind and all are wired through HomeWidget', () => {
    for (const file of files) expect(readFileSync(file, 'utf8').length).toBeGreaterThan(0)
    const dispatcher = readFileSync('src/components/home/HomeWidget.vue', 'utf8')
    for (const kind of ['netAssets','monthlyFlow','budget','reminders','transactions','accounts','account','calendar','lending','family','ai']) expect(dispatcher).toContain(`'${kind}'`)
  })

  it('does not expose fabricated reminder amounts and uses neutral transfer presentation', () => {
    const debt = { total_debt: 50, total_paid: 10, total_principal: 60, progress: 16.7, active_loans: 1, paid_off_loans: 0, next_payment_day: 8, next_payment_name: '信用卡', days_until_next: 2 }
    expect(getReminderReadModel(debt)).not.toHaveProperty('nextAmount')
    const model = createHomeReadModels({ accounts, debt, recentTransactions: [transfer] })
    expect(model.transactions.data?.[0].presentation.tone).toBe('neutral')
    expect(model.account.data?.id).toBe('cash')
  })

  it('does not request AI generation or writes from widget components', () => {
    for (const file of files.slice(2)) {
      const source = readFileSync(file, 'utf8')
      expect(source).not.toMatch(/generateReport|createProvider|\.post\(|\.put\(|\.patch\(|\.delete\(/)
    }
  })
})
