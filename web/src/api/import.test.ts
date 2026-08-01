import { beforeEach, describe, expect, it, vi } from 'vitest'

import { get, post, postForm } from '@/utils/request'
import { transactionImportApi } from './import'

vi.mock('@/utils/request', () => ({
  get: vi.fn(),
  post: vi.fn(),
  postForm: vi.fn(),
}))

describe('transaction import API contract', () => {
  beforeEach(() => vi.clearAllMocks())

  it('uses preview, validate, commit, rollback and status routes', async () => {
    vi.mocked(postForm).mockResolvedValue({ id: 'import-1' })
    vi.mocked(get).mockResolvedValue({ id: 'import-1' })
    vi.mocked(post).mockResolvedValue({ id: 'import-1' })
    const file = new File(['a,b'], 'transactions.csv', { type: 'text/csv' })

    await transactionImportApi.preview(file)
    await transactionImportApi.get('import-1')
    await transactionImportApi.recent()
    await transactionImportApi.list()
    await transactionImportApi.validate('import-1')
    await transactionImportApi.commit('import-1')
    await transactionImportApi.rollback('import-1')

    expect(postForm).toHaveBeenCalledWith(
      '/imports/transactions/preview',
      expect.any(FormData),
    )
    expect(get).toHaveBeenCalledWith('/imports/transactions/import-1')
    expect(get).toHaveBeenCalledWith('/imports/transactions/recent')
    expect(get).toHaveBeenCalledWith('/imports/transactions', {
      params: { limit: 64 },
    })
    expect(post).toHaveBeenNthCalledWith(1, '/imports/transactions/import-1/validate')
    expect(post).toHaveBeenNthCalledWith(2, '/imports/transactions/import-1/commit')
    expect(post).toHaveBeenNthCalledWith(3, '/imports/transactions/import-1/rollback')
  })
})
