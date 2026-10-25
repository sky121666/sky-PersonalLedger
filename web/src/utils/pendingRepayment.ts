import { createIdempotencyKey } from '@/utils/formSubmission'

type RepaymentKind = 'reminder' | 'lending'

export interface PendingRepayment<Payload> {
  key: string
  payload: Payload
  attempt: number
}

function storageKey(kind: RepaymentKind, targetId: string) {
  return `personal-ledger:pending-repayment:v1:${kind}:${targetId}`
}

/** Keep the exact request, not a mutable form, until its result is confirmed. */
export function readPendingRepayment<Payload>(kind: RepaymentKind, targetId: string): PendingRepayment<Payload> | null {
  try {
    const raw = sessionStorage.getItem(storageKey(kind, targetId))
    if (raw === null) return null
    const record = JSON.parse(raw)
    const payload = record?.payload
    if (
      record?.version !== 1 || record.kind !== kind || record.targetId !== targetId
      || typeof record.key !== 'string' || !/^[0-9a-f-]{36}$/i.test(record.key)
      || !payload || typeof payload !== 'object' || !Number.isFinite(payload.amount) || payload.amount <= 0
      || (kind === 'reminder' && (
        typeof payload.accountId !== 'string' || !payload.accountId
        || !Number.isFinite(payload.principal) || payload.principal < 0
        || !Number.isFinite(payload.interest) || payload.interest < 0
      ))
      || (kind === 'lending' && (typeof payload.record_date !== 'string' || !payload.record_date))
    ) throw new Error('invalid pending repayment')
    return { key: record.key, payload, attempt: Number.isSafeInteger(record.attempt) && record.attempt >= 0 ? record.attempt : 0 }
  } catch {
    // Never discard an unreadable record and silently issue another payment.
    throw new Error('无法读取未确认还款记录，已阻止新还款。请恢复当前浏览器会话存储后重试。')
  }
}

export function createPendingRepayment<Payload>(kind: RepaymentKind, targetId: string, payload: Payload): PendingRepayment<Payload> {
  const existing = readPendingRepayment<Payload>(kind, targetId)
  if (existing) return existing
  const pending = { key: createIdempotencyKey(), payload: JSON.parse(JSON.stringify(payload)) as Payload, attempt: 0 }
  try {
    sessionStorage.setItem(storageKey(kind, targetId), JSON.stringify({ version: 1, kind, targetId, ...pending }))
  } catch {
    throw new Error('无法保存还款确认记录，尚未发送还款。请允许当前浏览器使用会话存储后重试。')
  }
  return pending
}

export function startPendingRepaymentAttempt<Payload>(kind: RepaymentKind, targetId: string, pending: PendingRepayment<Payload>): PendingRepayment<Payload> {
  const current = readPendingRepayment<Payload>(kind, targetId)
  if (current && current.key !== pending.key) throw new Error('已有另一笔未确认还款，请重新打开确认上次还款结果。')
  const next = { ...pending, attempt: (current?.attempt ?? pending.attempt) + 1 }
  try {
    sessionStorage.setItem(storageKey(kind, targetId), JSON.stringify({ version: 1, kind, targetId, ...next }))
  } catch {
    throw new Error('无法保存还款确认记录，尚未发送本次请求。请恢复当前浏览器会话存储后重试。')
  }
  return next
}

export function clearPendingRepayment(kind: RepaymentKind, targetId: string, key: string, expectedAttempt?: number) {
  const current = readPendingRepayment(kind, targetId)
  if (current?.key !== key || (expectedAttempt !== undefined && current.attempt !== expectedAttempt)) return false
  try {
    sessionStorage.removeItem(storageKey(kind, targetId))
  } catch {
    throw new Error('还款结果已返回，但本地确认记录暂时无法清理。请恢复会话存储后重试确认。')
  }
  return true
}

export function isDefinitiveRepaymentRejection(error: unknown) {
  const status = (error as { status?: number } | null)?.status
  return typeof status === 'number' && status >= 400 && status < 500 && status !== 408
}

export const pendingRepaymentMessage = '上次还款结果尚未确认，已恢复并锁定原金额及账户。请确认上次还款结果后，再开始新还款。'
