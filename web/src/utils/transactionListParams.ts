import type { TransactionListParams } from '@/api/transaction'

export type TransactionListFilters = Pick<
  TransactionListParams,
  'type' | 'start_date' | 'end_date' | 'keyword'
>

export function buildTransactionListParams(
  page: number,
  pageSize: number,
  filters: TransactionListFilters,
): TransactionListParams {
  const params: TransactionListParams = {
    page,
    page_size: pageSize,
  }

  if (filters.type) params.type = filters.type
  if (filters.start_date) params.start_date = filters.start_date
  if (filters.end_date) params.end_date = filters.end_date
  if (filters.keyword) params.keyword = filters.keyword

  return params
}
