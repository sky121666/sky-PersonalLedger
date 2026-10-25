import { createIdempotencyKey } from '@/utils/formSubmission'
import type { DebtCommand } from '@/api/debt'

export type PendingDebtWrite = DebtCommand & { key: string; attempt: number }
type StorageAccess = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>

export function createDebtJournal(userId: number, storage: StorageAccess = sessionStorage) {
  if (!Number.isSafeInteger(userId) || userId <= 0) throw Error('尚未确认当前用户，不能发送财务操作')
  const storageKey = `personal-ledger:debt-write:v1:${userId}`
  function read(): PendingDebtWrite | null {
    try {
      const raw = storage.getItem(storageKey)
      if (raw === null) return null
      const record = JSON.parse(raw)
      if (record.version !== 1 || record.userId !== userId ||
        !['plan', 'payment', 'allocation', 'interest', 'reversal'].includes(record.kind) ||
        typeof record.target !== 'string' || !record.target || record.target.length > 128 ||
        !record.payload || typeof record.payload !== 'object' || Array.isArray(record.payload) ||
        typeof record.key !== 'string' || !/^[0-9a-f-]{36}$/i.test(record.key) ||
        !Number.isSafeInteger(record.attempt) || record.attempt < 0) throw Error('invalid journal')
      return { kind: record.kind, target: record.target, payload: record.payload, key: record.key, attempt: record.attempt } as PendingDebtWrite
    } catch {
      throw Error('无法读取未确认操作，已暂停新操作。请恢复当前浏览器的会话存储后重试。')
    }
  }
  function save(record: PendingDebtWrite) {
    try { storage.setItem(storageKey, JSON.stringify({ version: 1, userId, ...record })) }
    catch { throw Error('无法保存操作确认记录，尚未发送。请允许浏览器使用会话存储后重试。') }
  }
  return {
    read,
    stage(command: DebtCommand): PendingDebtWrite {
      if (read()) throw Error('还有未确认操作，请先确认上次结果')
      const record = { ...JSON.parse(JSON.stringify(command)), key: createIdempotencyKey(), attempt: 0 } as PendingDebtWrite
      save(record)
      return record
    },
    attempt(record: PendingDebtWrite): PendingDebtWrite {
      const current = read()
      if (!current || current.key !== record.key) throw Error('操作确认记录已变化，请重新加载')
      const next = { ...current, attempt: current.attempt + 1 }
      save(next)
      return next
    },
    clear(record: PendingDebtWrite) {
      const current = read()
      if (current?.key !== record.key || current.attempt !== record.attempt) return false
      try { storage.removeItem(storageKey) }
      catch { throw Error('操作已返回，但确认记录未能清理。请恢复会话存储后再次确认结果。') }
      return true
    },
  }
}

export function isDebtWriteRejection(error: unknown) {
  const item = error as { status?: number; code?: number } | null
  return typeof item?.status === 'number' && item.status >= 400 && item.status < 500 &&
    item.status !== 408 && item.status !== 429 && item.code !== 40903
}
