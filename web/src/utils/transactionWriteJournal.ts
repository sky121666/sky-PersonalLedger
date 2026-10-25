import type { CreateTransactionParams } from '@/api/transaction'
import { createIdempotencyKey } from '@/utils/formSubmission'

type StorageAccess = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>
export interface PendingTransactionWrite {
  key: string
  payload: CreateTransactionParams
  attempt: number
}

export function createTransactionJournal(userId: number, storage: StorageAccess = sessionStorage) {
  if (!Number.isSafeInteger(userId) || userId <= 0) throw Error('尚未确认当前用户，不能发送记账请求')
  // sessionStorage is also isolated by origin; this Web uses same-origin /api/v1.
  const storageKey = `personal-ledger:transaction-write:v1:${userId}`
  function read(): PendingTransactionWrite | null {
    try {
      const raw = storage.getItem(storageKey)
      if (raw === null) return null
      const record = JSON.parse(raw), payload = record?.payload
      if (record.version !== 1 || record.userId !== userId ||
        typeof record.key !== 'string' || !/^[0-9a-f-]{36}$/i.test(record.key) ||
        !Number.isSafeInteger(record.attempt) || record.attempt < 0 ||
        !payload || !['income', 'expense', 'transfer'].includes(payload.type) ||
        !Number.isFinite(payload.amount) || payload.amount <= 0 ||
        typeof payload.account_id !== 'string' || !payload.account_id ||
        typeof payload.transaction_date !== 'string' || !payload.transaction_date ||
        payload.idempotency_key !== record.key) throw Error('invalid transaction journal')
      return { key: record.key, payload, attempt: record.attempt }
    } catch {
      throw Error('无法读取未确认记账记录，已暂停新记账。请恢复当前浏览器会话存储后重试。')
    }
  }
  function save(record: PendingTransactionWrite) {
    try { storage.setItem(storageKey, JSON.stringify({ version: 1, userId, ...record })) }
    catch { throw Error('无法保存记账确认记录，尚未发送。请允许浏览器使用会话存储后重试。') }
  }
  return {
    read,
    stage(payload: CreateTransactionParams): PendingTransactionWrite {
      if (read()) throw Error('还有未确认记账，请先确认上次结果')
      const key = createIdempotencyKey()
      const record = { key, payload: { ...JSON.parse(JSON.stringify(payload)), idempotency_key: key }, attempt: 0 }
      save(record)
      return record
    },
    attempt(record: PendingTransactionWrite) {
      const current = read()
      if (current && current.key !== record.key) throw Error('记账确认记录已变化，请重新打开')
      // An earlier success may have cleared storage after another dialog
      // recovered this record. Reconfirm that same intent, never generate a key.
      const previous = current || record
      const next = { ...previous, attempt: previous.attempt + 1 }
      save(next)
      return next
    },
    clear(record: PendingTransactionWrite) {
      const current = read()
      if (current?.key !== record.key || current.attempt !== record.attempt) return false
      try { storage.removeItem(storageKey) }
      catch { throw Error('记账结果已返回，但确认记录未能清理。请恢复会话存储后再次确认。') }
      return true
    },
  }
}

export function isTransactionWriteRejection(error: unknown) {
  const item = error as { status?: number; code?: number } | null
  return typeof item?.status === 'number' && item.status >= 400 && item.status < 500 &&
    item.status !== 408 && item.status !== 429 && item.code !== 40903 && item.code !== 40913
}
