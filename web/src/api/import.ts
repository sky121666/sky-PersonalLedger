import { get, post, postForm } from '@/utils/request'

export interface TransactionImportRow {
  row: number
  type: string
  amount: number
  transaction_date: string
  account: string
  category?: string
  valid: boolean
  duplicate: boolean
  errors?: string[]
  warnings?: string[]
}

export type TransactionImportStatus =
  | 'previewed'
  | 'validated'
  | 'committed'
  | 'rolled_back'

export interface TransactionImportPreview {
  id: string
  filename: string
  format: 'csv' | 'json'
  status: TransactionImportStatus
  total_rows: number
  valid_rows: number
  invalid_rows: number
  duplicate_rows: number
  created_rows: number
  rolled_back_rows: number
  rows: TransactionImportRow[]
  rows_truncated: boolean
  created_at: string
  expires_at: string
  committed_at?: string
  rolled_back_at?: string
}

interface TransactionImportListResponse {
  list: TransactionImportPreview[]
}

export const transactionImportApi = {
  preview(file: File): Promise<TransactionImportPreview> {
    const data = new FormData()
    data.append('file', file)
    return postForm<TransactionImportPreview>('/imports/transactions/preview', data)
  },

  get(id: string): Promise<TransactionImportPreview> {
    return get<TransactionImportPreview>(`/imports/transactions/${id}`)
  },

  recent(): Promise<TransactionImportPreview | null> {
    return get<TransactionImportPreview | null>('/imports/transactions/recent')
  },

  list(): Promise<TransactionImportListResponse> {
    return get<TransactionImportListResponse>('/imports/transactions', {
      params: { limit: 64 }
    })
  },

  validate(id: string): Promise<TransactionImportPreview> {
    return post<TransactionImportPreview>(`/imports/transactions/${id}/validate`)
  },

  commit(id: string): Promise<TransactionImportPreview> {
    return post<TransactionImportPreview>(`/imports/transactions/${id}/commit`)
  },

  rollback(id: string): Promise<TransactionImportPreview> {
    return post<TransactionImportPreview>(`/imports/transactions/${id}/rollback`)
  }
}
