import { readonly, ref } from 'vue'

const ledgerMutationRevision = ref(0)

// Every mounted view whose data can change after a transaction mutation must
// subscribe to this revision. Keep this list in sync with the view watchers.
export const ledgerMutationConsumers = [
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
] as const

export function notifyLedgerMutation() {
  ledgerMutationRevision.value += 1
}

export function useLedgerMutationRevision() {
  return readonly(ledgerMutationRevision)
}
