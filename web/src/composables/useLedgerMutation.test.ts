import { describe, expect, it } from 'vitest'
import { watch } from 'vue'
import {
  ledgerMutationConsumers,
  notifyLedgerMutation,
  useLedgerMutationRevision,
} from './useLedgerMutation'

describe('ledger mutation revision', () => {
  it('notifies every mounted derived-data consumer after a mutation', async () => {
    const revision = useLedgerMutationRevision()
    const reloads = new Map(
      ledgerMutationConsumers.map((consumer) => [consumer, [] as number[]]),
    )
    const stops = [...reloads.values()].map((values) =>
      watch(revision, (value) => values.push(value)),
    )

    notifyLedgerMutation()
    await Promise.resolve()

    expect([...reloads.keys()]).toEqual([
      'home',
      'statistics',
      'transactions',
      'accounts',
      'budget',
      'settings',
      'family',
      'report',
      'accountLogs',
      'reminders',
      'lendings',
    ])
    for (const values of reloads.values()) {
      expect(values).toHaveLength(1)
    }

    stops.forEach((stop) => stop())
  })
})
