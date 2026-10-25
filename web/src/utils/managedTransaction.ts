export interface ManagedTransactionFields {
  source?: string | null
  reminder_id?: string | null
  lending_id?: string | null
  debt_operation_id?: string | null
}

export function isManagedTransaction(transaction: ManagedTransactionFields): boolean {
  const source = transaction.source?.trim().toLowerCase()
  return source === 'lending'
    || source === 'reminder'
    || transaction.lending_id != null
    || transaction.reminder_id != null
    || transaction.debt_operation_id != null
    || source === 'debt_interest' || source === 'debt_payment' || source === 'debt_principal'
}
