import dayjs from 'dayjs'

export function toLedgerInstant(value: string): string {
  const parsed = dayjs(value)
  if (!parsed.isValid()) {
    throw new Error('invalid transaction date')
  }
  return parsed.toISOString()
}
