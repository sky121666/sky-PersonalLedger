import { createHomeReadModels } from './readModels'
import type { Transaction } from '@/api/transaction'

// Local examples only: the gallery never requests ledger or AI data.
export function createGalleryPreview() {
  const transactions: Transaction[] = [36, 128, 18, 64, 25].map((amount, index) => ({
    id: `preview-${index}`, type: 'expense', amount, account_id: 'preview',
    category_id: 'preview-food', transaction_date: `2026-10-${20 - index}T12:00:00+08:00`,
    remark: ['午餐', '超市采购', '交通', '晚餐', '日用品'][index]!,
    images: '', tags: '', to_account_id: null, source: 'manual', recurring_id: null,
    category: { id: 'preview-food', name: '日常消费', type: 'expense', icon: 'shopping-bag', color: '#007aff' },
  }))
  const state = { phase: 'ready' as const, queryKey: 'gallery-example', receivedAt: 0 }
  return createHomeReadModels({
    receivedAt: 0,
    accounts: {
      list: [
        { id: 'preview', name: '日常银行卡', type: 'bank_card', icon: 'wallet', color: '#007aff', initial_balance: 0, current_balance: 4200, total_paid: 0, is_archived: false, sort_order: 0 },
        { id: 'preview-cash', name: '现金', type: 'cash', icon: 'wallet', color: '#34c759', initial_balance: 0, current_balance: 800, total_paid: 0, is_archived: false, sort_order: 1 },
      ],
      total_assets: 5000, total_liabilities: 0, net_assets: 5000,
    },
    overview: { income: 8000, expense: 1200, balance: 6800, income_change: 0, expense_change: 0, daily_average: 40, transaction_count: 12 },
    budget: { total_amount: 3000, total_spent: 1200, percentage: 40, daily_available: 100, days_remaining: 18, over_budget_categories: [] },
    budgetDetails: { ...state, data: {
      total_budget: null, member_budgets: [],
      category_budgets: ['餐饮', '交通', '日用'].map((name, index) => ({
        id: `preview-budget-${index}`, category_id: `preview-category-${index}`, category_name: name,
        amount: 1000, spent: 400, period: 'monthly', alert_threshold: 80, is_active: true,
      })),
    } },
    debt: { total_debt: 9000, total_paid: 3000, total_principal: 12000, progress: 25, active_loans: 1, paid_off_loans: 0, next_payment_day: 25, next_payment_name: '信用卡还款提醒', days_until_next: 5 },
    recentTransactions: transactions,
    accountTransactions: { preview: { ...state, data: transactions.slice(0, 3) } },
    lending: { total_lend_out: 1500, total_borrow_in: 0, active_lend_out: 1, active_borrow_in: 0, settled_lend_out: 0, settled_borrow_in: 0, total_receivable: 1500, total_payable: 0, net_lending: 1500 },
    family: { month: '2026-10', total_expense: 1200, members: [
      { member_id: 'preview-member', name: '家庭成员', relationship: 'self', color: '#007aff', expense_total: 1200, count: 12 },
    ] },
    aiReport: {
      id: 'preview-report', report_type: 'monthly', period_start: '2026-10-01', period_end: '2026-10-31',
      status: 'completed', snapshot_json: '', content_json: '{"summary":"本月支出主要用于日常生活，预算仍有结余。"}',
      provider_id: '', provider_name: '示例', model: '', prompt_version: '', created_at: '', updated_at: '',
    },
  })
}
