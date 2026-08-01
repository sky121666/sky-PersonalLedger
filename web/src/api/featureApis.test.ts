import { beforeEach, describe, expect, it, vi } from 'vitest'

import { del, get, post, put } from '@/utils/request'
import { tagApi } from './tag'
import { templateApi } from './template'

vi.mock('@/utils/request', () => ({
  get: vi.fn(),
  post: vi.fn(),
  put: vi.fn(),
  del: vi.fn(),
}))

describe('tag and template API contracts', () => {
  beforeEach(() => vi.clearAllMocks())

  it('uses the tag CRUD routes', async () => {
    vi.mocked(get).mockResolvedValue([])
    vi.mocked(post).mockResolvedValue({ id: 'tag-1' })
    vi.mocked(put).mockResolvedValue({ id: 'tag-1' })
    vi.mocked(del).mockResolvedValue(undefined)

    await tagApi.list()
    await tagApi.create({ name: '餐饮' })
    await tagApi.update('tag-1', { name: '外食' })
    await tagApi.delete('tag-1')

    expect(get).toHaveBeenCalledWith('/tags')
    expect(post).toHaveBeenCalledWith('/tags', { name: '餐饮' })
    expect(put).toHaveBeenCalledWith('/tags/tag-1', { name: '外食' })
    expect(del).toHaveBeenCalledWith('/tags/tag-1')
  })

  it('unwraps template lists and applies a template through the real route', async () => {
    vi.mocked(get).mockResolvedValue({ list: [] })
    vi.mocked(post).mockResolvedValue({ id: 'transaction-1' })

    await expect(templateApi.list()).resolves.toEqual([])
    await templateApi.apply('template-1', {
      amount: 25,
      transaction_date: '2026-07-31T12:00:00.000Z',
    })

    expect(get).toHaveBeenCalledWith('/templates')
    expect(post).toHaveBeenCalledWith('/templates/template-1/apply', {
      amount: 25,
      transaction_date: '2026-07-31T12:00:00.000Z',
    })
  })
})
