import type { AIReport, GenerateAIReportParams } from '@/api/ai'

type RecordValue = Record<string, unknown>
const object = (value: unknown): RecordValue | null => value !== null && typeof value === 'object' && !Array.isArray(value) ? value as RecordValue : null
const text = (value: unknown) => typeof value === 'string' ? value.trim() : ''
const strings = (value: unknown) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string' && Boolean(item.trim())) : []
const records = (value: unknown) => Array.isArray(value) ? value.map(object).filter((item): item is RecordValue => item !== null) : []

function snapshotRecords(value: unknown): RecordValue[] | null {
  if (!Array.isArray(value)) return null
  const items = value.map(object)
  // Dropping unreadable entries would turn an unknown scope into a smaller count.
  return items.some(item => item === null) ? null : items as RecordValue[]
}

export function amount(value: unknown): number | null {
  if ((typeof value !== 'number' && typeof value !== 'string') || String(value).trim() === '') return null
  const result = Number(value)
  return Number.isFinite(result) ? result : null
}

export function formatMoney(value: unknown, currency?: string | null) {
  const number = amount(value)
  if (number === null) return '—'
  const denomination = text(currency)
  const digits = Math.abs(number).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  const sign = number < 0 ? '-' : ''
  if (!denomination) return `${sign}${digits}（币种未知）`
  const symbol = denomination === 'CNY' ? '¥' : `${denomination} `
  return `${sign}${symbol}${digits}`
}

export function parseReportContent(content?: string) {
  if (!content?.trim()) return null
  let value: RecordValue | null
  try { value = object(JSON.parse(content)) } catch {
    if (/^[{\[]|^```/.test(content.trim())) return null
    value = { summary: content.trim() }
  }
  if (!value || !text(value.summary)) return null
  return {
    title: text(value.title), summary: text(value.summary),
    highlights: strings(value.highlights), suggestions: strings(value.suggestions),
    risks: records(value.risks).filter(r => text(r.title) || text(r.detail)).map(r => ({
      title: text(r.title), detail: text(r.detail), level: text(r.level),
    })),
  }
}

export function parseReportSnapshot(raw?: string) {
  let snapshot: RecordValue | null
  try { snapshot = object(JSON.parse(raw || '')) } catch { return null }
  if (!snapshot) return null
  const budget = object(snapshot.budget)
  const period = object(snapshot.period)
  return {
    currency: text(snapshot.currency) || null,
    income: amount(snapshot.income_total), expense: amount(snapshot.expense_total), net: amount(snapshot.net_cashflow),
    period: { start: text(period?.start), end: text(period?.end), timezone: text(period?.timezone) },
    budget: budget ? {
      total: amount(budget.monthly_budget), spent: amount(budget.spent), remaining: amount(budget.remaining),
      used: amount(budget.used_percent), start: text(budget.period_start), end: text(budget.period_end),
      basis: text(budget.settings_basis), totalUnset: budget.monthly_budget === null,
      memberBudgets: snapshotRecords(budget.member_budgets)?.map(item => ({
        name: text(item.member_name) || '名称未知', category: text(item.category_name),
        amount: amount(item.amount), spent: amount(item.spent), remaining: amount(item.remaining), percentage: amount(item.percentage),
      })) ?? null,
    } : null,
    categories: snapshotRecords(snapshot.top_expense_categories)?.map(item => ({ name: text(item.name) || '分类名称未知', amount: amount(item.amount) })) ?? null,
    members: snapshotRecords(snapshot.family_members)?.map(item => ({ name: text(item.display_name) || '名称未知', amount: amount(item.expense_total), count: amount(item.count) })) ?? null,
    accounts: snapshotRecords(snapshot.account_changes)?.map(item => ({ name: text(item.account_name) || '账户名称未知', change: amount(item.balance_delta) })) ?? null,
  }
}

export const typeText = (type: string) => ({ weekly: '每周总结', monthly: '月度总结', family: '家庭分析', budget: '预算建议' })[type] || '财务分析'
export const statusText = (status: string) => ({ completed: '已完成', pending: '等待生成', running: '生成中', failed: '生成失败' })[status] || '状态未知'
export const shortDate = (value: string) => value?.slice(0, 10) || '日期未知'
export const reportPeriod = (report: Pick<AIReport, 'period_start' | 'period_end'>) => `${shortDate(report.period_start)} 至 ${shortDate(report.period_end)}`
export const reportMasked = (report: AIReport): boolean | null => report.prompt_version?.endsWith('-masked') ? true : ['personal-ledger-v3', 'personal-ledger-v4', 'personal-ledger-v5'].includes(report.prompt_version) ? false : null

export function reportMatches(report: AIReport, params: GenerateAIReportParams) {
  return report.report_type === params.report_type && shortDate(report.period_start) === params.period_start
    && shortDate(report.period_end) === params.period_end && report.provider_id === params.provider_id
    && reportMasked(report) === (params.mask_names !== false)
}

export function retryParams(report: AIReport): GenerateAIReportParams {
  return { report_type: report.report_type, period_start: shortDate(report.period_start), period_end: shortDate(report.period_end),
    provider_id: report.provider_id, mask_names: reportMasked(report) !== false }
}

export function chartWidth(value: number | null, maximum: number) {
  return maximum > 0 && value !== null ? `${Math.max(0, Math.min(100, value / maximum * 100))}%` : '0%'
}
