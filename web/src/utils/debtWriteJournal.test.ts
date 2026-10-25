import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createDebtJournal, isDebtWriteRejection } from './debtWriteJournal'

function storage() {
  const data = new Map<string, string>()
  return { getItem: (key: string) => data.get(key) ?? null, setItem: (key: string, value: string) => { data.set(key, value) }, removeItem: (key: string) => { data.delete(key) } }
}

const command = { kind: 'payment' as const, target: 'card', payload: {
  account_id: 'card', amount: 10, source_kind: 'external' as const, allocations: [],
  unplanned_amount: 0, unapplied_amount: 10,
} }

describe('debt financial request journal', () => {
  beforeEach(() => vi.unstubAllGlobals())

  it('keeps the exact payload and key across closing, reopening and a lost response', () => {
    const session = storage()
    const journal = createDebtJournal(1, session)
    const draft = { ...command, payload: { ...command.payload } }
    const original = journal.stage(draft)
    draft.payload.amount = 99
    const reopened = createDebtJournal(1, session).read()!
    expect(reopened.key).toBe(original.key)
    expect(reopened.kind).toBe('payment')
    if (reopened.kind !== 'payment') throw Error('unexpected pending kind')
    expect(reopened.payload.amount).toBe(10)
    expect(() => journal.stage(command)).toThrow(/未确认/)
  })

  it('scopes pending financial payloads to the authenticated user', () => {
    const session = storage()
    createDebtJournal(1, session).stage(command)
    expect(createDebtJournal(2, session).read()).toBeNull()
  })

  it('does not let an old response remove a newer retry attempt', () => {
    const journal = createDebtJournal(1, storage())
    const original = journal.stage(command)
    const first = journal.attempt(original)
    const second = journal.attempt(original)
    expect(journal.clear(first)).toBe(false)
    expect(journal.read()?.attempt).toBe(second.attempt)
    expect(journal.clear(second)).toBe(true)
  })

  it('fails closed before sending if session storage is unavailable or corrupt', () => {
    const session = storage()
    session.setItem('personal-ledger:debt-write:v1:1', '{broken')
    expect(() => createDebtJournal(1, session).read()).toThrow(/未确认/)
    expect(() => createDebtJournal(1, { ...storage(), setItem() { throw Error('quota') } }).stage(command)).toThrow(/尚未发送/)
  })

  it('retains ambiguous responses and idempotency conflicts for confirmation', () => {
    expect(isDebtWriteRejection({ status: 400 })).toBe(true)
    expect(isDebtWriteRejection({ status: 409, code: 40911 })).toBe(true)
    expect(isDebtWriteRejection({ status: 409, code: 40903 })).toBe(false)
    expect(isDebtWriteRejection({ status: 408 })).toBe(false)
    expect(isDebtWriteRejection({ status: 429 })).toBe(false)
    expect(isDebtWriteRejection({ status: 500 })).toBe(false)
    expect(isDebtWriteRejection(Error('lost'))).toBe(false)
  })
})
