import type { Account, AccountListResponse } from '@/api/account'
import type { AIReport } from '@/api/ai'
import type { BudgetSummary, BudgetListResponse } from '@/api/budget'
import type { FamilySummary } from '@/api/family'
import type { LendingSummary } from '@/api/lending'
import type { DebtSummary } from '@/api/reminder'
import type { OverviewResponse } from '@/api/statistics'
import type { Transaction } from '@/api/transaction'
import { getCategoryEmoji, getAccountTypeName } from '@/utils/constants'

export interface ResourceState<T> {
  phase: 'idle' | 'loading' | 'ready' | 'error'
  data: T | null
  queryKey: string
  receivedAt: number | null
  error?: string
}

export interface HomeSnapshot {
  accountDetails?: Record<string, AccountDetailModel>
  budgetDetails?: ResourceState<BudgetListResponse>
  accountTransactions?: Record<string, ResourceState<Transaction[]>>
  accounts?: AccountListResponse | null
  overview?: OverviewResponse | null
  budget?: BudgetSummary | null
  debt?: DebtSummary | null
  lending?: LendingSummary | null
  family?: FamilySummary | null
  aiReport?: AIReport | null
  recentTransactions?: Transaction[]
  showAmounts?: boolean
  failures?: string[]
  receivedAt?: number
}

export interface TransactionPresentation {
  title: string
  icon: string
  tone: 'income' | 'expense' | 'neutral'
  signedAmount: string
  displayAmount: string
}

export interface NetAssetsModel {
  netAssets: number
  totalAssets: number
  totalLiabilities: number
  displayNetAssets: string
  displayAssets: string
  displayLiabilities: string
}

export interface MonthlyFlowModel {
  income: number
  expense: number
  balance: number
  displayIncome: string
  displayExpense: string
  displayBalance: string
}

export interface BudgetModel {
  amount: number
  spent: number
  remaining: number
  percentage: number
  visualPercentage: number
  dailyAvailable: number
  daysRemaining: number
  alertName: string | null
  alertOver: boolean
  categories: Array<{ id: string; name: string; displaySpent: string; displayAmount: string }>
  detailsPhase: ResourceState<BudgetListResponse>['phase']
  displaySpent: string
  displayRemaining: string
}

export interface ReminderModel {
  scope: '还款提醒，不含账户分期'
  nextName: string
  daysUntil: number
  scheduledDay: number
  progress: number
  activeLoans: number
  displayPaid: string
  displayDebt: string
}

export interface AccountSummaryModel {
  id: string
  name: string
  typeName: string
  icon: string
  color: string
  balance: number
  displayBalance: string
  archived: boolean
}

export interface AccountDetailModel extends AccountSummaryModel {
  recentTransactions: TransactionPresentation[]
  recordsPhase?: ResourceState<Transaction[]>['phase']
}

export interface HomeReadModels {
  netAssets: ResourceState<NetAssetsModel>
  overview: ResourceState<MonthlyFlowModel>
  budget: ResourceState<BudgetModel>
  reminders: ResourceState<ReminderModel>
  transactions: ResourceState<Array<{ transaction: Transaction; presentation: TransactionPresentation; displayAmount: string }>>
  accounts: ResourceState<AccountSummaryModel[]>
  account: ResourceState<AccountDetailModel>
  accountTransactions: Record<string, ResourceState<TransactionPresentation[]>>
  calendar: ResourceState<null>
  lending: ResourceState<{ receivable: number; payable: number; net: number; active: number; settled: number; displayReceivable: string; displayPayable: string; displayNet: string } | null>
  family: ResourceState<{ totalExpense: number; members: number; displayTotal: string } | null>
  ai: ResourceState<{ status: string; summary: string; period: string; provider: string } | null>
}

export function formatMoney(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return '—'
  return value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

function amount(value: number | null | undefined, visible: boolean): string {
  return visible ? formatMoney(value) : '****'
}

export function getTransactionPresentation(transaction: Transaction, visible = true): TransactionPresentation {
  const tone = transaction.type === 'transfer' ? 'neutral' : transaction.type
  const title = transaction.type === 'transfer' ? '转账' : (transaction.category?.name || '未分类')
  const icon = transaction.type === 'transfer' ? 'repeat' : getCategoryEmoji(title, transaction.category?.icon)
  const prefix = transaction.type === 'income' ? '+' : transaction.type === 'expense' ? '-' : ''
  return {
    title,
    icon,
    tone,
    signedAmount: `${prefix}${formatMoney(transaction.amount)}`,
    displayAmount: visible ? `${prefix}${formatMoney(transaction.amount)}` : '****',
  }
}

export function getReminderReadModel(debt: DebtSummary | null | undefined, visible = true): ReminderModel | null {
  if (!debt || !debt.next_payment_name) return null
  return {
    scope: '还款提醒，不含账户分期',
    nextName: debt.next_payment_name,
    daysUntil: debt.days_until_next,
    scheduledDay: debt.next_payment_day,
    progress: debt.progress,
    activeLoans: debt.active_loans,
    displayPaid: amount(debt.total_paid, visible),
    displayDebt: amount(debt.total_debt, visible),
  }
}

function ready<T>(data: T, queryKey: string, receivedAt: number): ResourceState<T> {
  return { phase: 'ready', data, queryKey, receivedAt }
}
function failed<T>(queryKey: string, error: string): ResourceState<T> {
  return { phase: 'error', data: null, queryKey, receivedAt: null, error }
}
function fromFailure<T>(failure: string | undefined, data: T, queryKey: string, receivedAt: number): ResourceState<T> {
  return failure ? failed<T>(queryKey, failure) : ready(data, queryKey, receivedAt)
}

function summaryAccount(account: Account, visible: boolean): AccountSummaryModel {
  return {
    id: account.id,
    name: account.name,
    typeName: getAccountTypeName(account.type),
    icon: account.icon,
    color: account.color,
    balance: account.current_balance,
    displayBalance: amount(account.current_balance, visible),
    archived: account.is_archived,
  }
}

function reportSummary(report: AIReport): string {
  if (report.status === 'failed') return '报告生成失败'
  if (report.status === 'running') return '报告正在生成'
  if (report.status === 'pending') return '报告等待生成'
  if (report.status !== 'completed') return '报告状态未知'
  if (!report.content_json.trim()) return '报告已完成，暂无摘要'
  try {
    const content: unknown = JSON.parse(report.content_json)
    if (typeof content === 'string') return content
    if (content && typeof content === 'object') {
      const value = content as Record<string, unknown>
      if (typeof value.summary === 'string' && value.summary.trim()) return value.summary
      if (typeof value.title === 'string' && value.title.trim()) return value.title
    }
    return '报告已完成，查看完整内容'
  } catch { return report.content_json }
}

export function createHomeReadModels(snapshot: HomeSnapshot): HomeReadModels {
  const receivedAt = snapshot.receivedAt ?? Date.now()
  const failures = new Set(snapshot.failures ?? [])
  const visible = snapshot.showAmounts !== false
  const accounts = snapshot.accounts
  const overview = snapshot.overview
  const budget = snapshot.budget
  const debt = snapshot.debt
  const lending = snapshot.lending
  const family = snapshot.family
  const ai = snapshot.aiReport
  const transactions = snapshot.recentTransactions ?? []
  const budgetAlert = budget?.over_budget_categories.find(item => item.percentage > 0) ?? budget?.over_budget_categories[0]

  const netAssetsData: NetAssetsModel | null = accounts ? {
    netAssets: accounts.net_assets,
    totalAssets: accounts.total_assets,
    totalLiabilities: accounts.total_liabilities,
    displayNetAssets: amount(accounts.net_assets, visible),
    displayAssets: amount(accounts.total_assets, visible),
    displayLiabilities: amount(accounts.total_liabilities, visible),
  } : null
  const overviewData: MonthlyFlowModel | null = overview ? {
    income: overview.income,
    expense: overview.expense,
    balance: overview.balance,
    displayIncome: amount(overview.income, visible),
    displayExpense: amount(overview.expense, visible),
    displayBalance: amount(overview.balance, visible),
  } : null
  const budgetData: BudgetModel | null = budget ? {
    amount: budget.total_amount,
    spent: budget.total_spent,
    remaining: budget.total_amount - budget.total_spent,
    percentage: budget.percentage,
    visualPercentage: Math.max(0, Math.min(100, budget.percentage)),
    dailyAvailable: budget.daily_available,
    daysRemaining: budget.days_remaining,
    alertName: budgetAlert?.name ?? null,
    alertOver: (budgetAlert?.percentage ?? 0) > 0,
    categories: (snapshot.budgetDetails?.data?.category_budgets ?? []).map(item => ({
      id: item.id, name: item.category_name || '未分类', displaySpent: amount(item.spent, visible), displayAmount: amount(item.amount, visible),
    })),
    detailsPhase: snapshot.budgetDetails?.phase ?? 'idle',
    displaySpent: amount(budget.total_spent, visible),
    displayRemaining: amount(budget.total_amount - budget.total_spent, visible),
  } : null
  const reminderData = getReminderReadModel(debt, visible)
  const accountList = accounts?.list.map(account => summaryAccount(account, visible)) ?? []
  const transactionData = transactions.map(transaction => ({
    transaction,
    presentation: getTransactionPresentation(transaction, visible),
    displayAmount: getTransactionPresentation(transaction, visible).displayAmount,
  }))
  const lendingData = lending ? {
    receivable: lending.total_receivable,
    payable: lending.total_payable,
    net: lending.net_lending,
    active: lending.active_lend_out + lending.active_borrow_in,
    settled: lending.settled_lend_out + lending.settled_borrow_in,
    displayReceivable: amount(lending.total_receivable, visible),
    displayPayable: amount(lending.total_payable, visible),
    displayNet: amount(lending.net_lending, visible),
  } : null
  const familyData = family ? {
    totalExpense: family.total_expense,
    members: family.members.length,
    displayTotal: amount(family.total_expense, visible),
  } : null
  const aiData = ai ? {
    status: ai.status,
    summary: reportSummary(ai),
    period: `${ai.period_start.slice(0, 10)} - ${ai.period_end.slice(0, 10)}`,
    provider: ai.provider_name,
  } : null

  const accountData = accountList[0]
    ? { ...accountList[0], recentTransactions: transactionData.slice(0, 3).map(item => item.presentation) }
    : null
  const accountQuery = accountData ? `account:${accountData.id}` : 'account:none'

  return {
    netAssets: fromFailure(failures.has('账户资产') ? '账户资产加载失败' : undefined, netAssetsData as NetAssetsModel, 'accounts', receivedAt),
    overview: fromFailure(failures.has('本月收支') ? '本月收支加载失败' : undefined, overviewData as MonthlyFlowModel, 'overview:current', receivedAt),
    budget: fromFailure(failures.has('预算') ? '预算加载失败' : undefined, budgetData as BudgetModel, 'budget:current', receivedAt),
    reminders: failures.has('债务提醒')
      ? failed('reminders:current', '还款提醒加载失败')
      : { phase: debt ? 'ready' : 'idle', data: reminderData, queryKey: 'reminders:current', receivedAt },
    transactions: fromFailure(failures.has('近期交易') ? '近期交易加载失败' : undefined, transactionData, 'transactions:recent', receivedAt),
    accounts: failures.has('账户资产') ? failed('accounts', '账户资产加载失败')
      : { phase: accounts ? 'ready' : 'idle', data: accounts ? accountList : null, queryKey: 'accounts', receivedAt },
    account: accountData ? ready(accountData, accountQuery, receivedAt) : { phase: 'idle', data: null, queryKey: accountQuery, receivedAt: null },
    accountTransactions: Object.fromEntries(Object.entries(snapshot.accountTransactions ?? {}).map(([id, resource]) => [
      id, { ...resource, data: resource.data?.map(item => getTransactionPresentation(item, visible)) ?? null },
    ])),
    calendar: { phase: 'idle', data: null, queryKey: 'calendar:month', receivedAt: null },
    lending: fromFailure(failures.has('借贷') ? '借贷加载失败' : undefined, lendingData, 'lending:current', receivedAt),
    family: fromFailure(failures.has('家庭成员') ? '家庭成员加载失败' : undefined, familyData, 'family:current', receivedAt),
    ai: fromFailure(failures.has('AI 分析') ? 'AI 分析加载失败' : undefined, aiData, 'ai:reports', receivedAt),
  }
}
