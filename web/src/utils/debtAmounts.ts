import type { DebtAllocationPayload, DebtPaymentPart, DebtPaymentPayload } from '@/api/debt'
import { toLedgerInstant } from '@/utils/ledgerDate'

export interface DebtPartInput {
  plan_id: string
  principal: string
  booked_interest: string
  cash_interest: string
}

export function debtCents(input: string, label = '金额'): number {
  const value = input.trim()
  if (!value) return 0
  if (!/^\d+(?:\.\d{1,2})?$/.test(value)) throw Error(`${label}须为非负金额，最多保留两位小数`)
  const [whole = '0', fraction = ''] = value.split('.')
  const cents = Number(whole) * 100 + Number(fraction.padEnd(2, '0'))
  if (!Number.isSafeInteger(cents)) throw Error(`${label}超出支持范围`)
  return cents
}

export function debtAmount(cents: number) {
  if (!Number.isSafeInteger(cents)) throw Error('金额合计超出支持范围')
  return cents / 100
}

export function sumDebtCents(...values: number[]) {
  const total = values.reduce((sum, value) => sum + value, 0)
  if (!Number.isSafeInteger(total)) throw Error('金额合计超出支持范围')
  return total
}

export function buildDebtParts(rows: DebtPartInput[]) {
  let totalCents = 0
  let cashCents = 0
  const seen = new Set<string>()
  const allocations: DebtPaymentPart[] = []
  for (const row of rows) {
    if (!row.plan_id || seen.has(row.plan_id)) throw Error('分期计划重复或缺失，请重新加载')
    seen.add(row.plan_id)
    const principal = debtCents(row.principal, '本金')
    const booked = debtCents(row.booked_interest, '已入账利息')
    const cash = debtCents(row.cash_interest, '当次利息')
    const total = sumDebtCents(principal, booked, cash)
    if (!total) continue
    allocations.push({ plan_id: row.plan_id, principal: debtAmount(principal), booked_interest: debtAmount(booked), cash_interest: debtAmount(cash) })
    totalCents = sumDebtCents(totalCents, total)
    cashCents = sumDebtCents(cashCents, cash)
  }
  return { allocations, totalCents, cashCents }
}

export interface DebtPaymentInput {
  amount: string
  source_kind: 'account' | 'external'
  source_account_id: string
  unplanned_amount: string
  unapplied_amount: string
  occurred_at: string
}

export function buildDebtPayment(form: DebtPaymentInput, rows: DebtPartInput[],
  target: { account_id?: string; standalone_plan_id?: string }, externalCashInterest: boolean): DebtPaymentPayload {
  const parts = buildDebtParts(rows)
  const amount = debtCents(form.amount)
  const unplanned = debtCents(form.unplanned_amount, '未归计划欠款')
  const unapplied = debtCents(form.unapplied_amount, '暂不分配')
  if (!amount || amount !== sumDebtCents(parts.totalCents, unplanned, unapplied)) throw Error('付款金额须等于各项分配合计，请核对差额')
  if ((!target.account_id) === (!target.standalone_plan_id)) throw Error('请选择一个有效付款目标')
  if (target.standalone_plan_id && (unplanned || unapplied || parts.allocations.length !== 1 || parts.allocations[0]?.plan_id !== target.standalone_plan_id)) {
    throw Error('独立计划付款须全部分配到该计划')
  }
  if (form.source_kind === 'account' && !form.source_account_id) throw Error('请选择真实付款账户')
  if (form.source_kind === 'account' && form.source_account_id === target.account_id) throw Error('不能使用同一账户给自己还款')
  if (form.source_kind === 'external' && parts.cashCents && !externalCashInterest) throw Error('外部来源不支持当次利息，请选择真实付款账户')
  const occurred = form.occurred_at ? toLedgerInstant(form.occurred_at) : undefined
  return { ...target, source_kind: form.source_kind,
    ...(form.source_kind === 'account' ? { source_account_id: form.source_account_id } : {}),
    amount: debtAmount(amount), allocations: parts.allocations,
    unplanned_amount: debtAmount(unplanned), unapplied_amount: debtAmount(unapplied),
    ...(occurred ? { occurred_at: occurred } : {}) }
}

export function buildDebtAllocation(rows: DebtPartInput[], unplannedInput: string, availableCents: number, replacement = ''): DebtAllocationPayload {
  const parts = buildDebtParts(rows)
  if (parts.cashCents) throw Error('后续分配不能改变当次利息，请纠正原付款')
  const unplanned = debtCents(unplannedInput, '未归计划欠款')
  const total = sumDebtCents(parts.totalCents, unplanned)
  if (!total || total > availableCents) throw Error('分配合计须大于零，且不能超过该付款的可分配额度')
  return { allocations: parts.allocations, unplanned_amount: debtAmount(unplanned),
    ...(replacement ? { replace_operation_id: replacement } : {}) }
}

export function formatDebtMoney(value: number) {
  return value.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}
