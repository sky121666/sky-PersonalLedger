import { describe, expect, it } from 'vitest'

import { isManagedTransaction } from './managedTransaction'

describe('isManagedTransaction', () => {
  it.each([
    { transaction: { source: 'lending' }, reason: 'lending source' },
    { transaction: { source: ' REMINDER ' }, reason: 'reminder source' },
    {
      transaction: { source: 'manual', lending_id: 'lending-1' },
      reason: 'lending id',
    },
    {
      transaction: { source: 'manual', reminder_id: 'reminder-1' },
      reason: 'reminder id',
    },
  ])('recognizes a transaction managed by $reason', ({ transaction }) => {
    expect(isManagedTransaction(transaction)).toBe(true)
  })

  it('keeps manual transactions without link fields editable', () => {
    expect(isManagedTransaction({ source: 'manual' })).toBe(false)
    expect(isManagedTransaction({ source: 'manual', reminder_id: null })).toBe(false)
  })

  it('fails closed when a link field is present even if legacy data stored an empty id', () => {
    expect(isManagedTransaction({ source: 'manual', lending_id: '' })).toBe(true)
  })
})
