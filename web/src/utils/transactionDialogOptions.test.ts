import { describe, expect, it } from 'vitest'

import type { AccountListResponse } from '@/api/account'
import type { Category } from '@/api/category'
import type { FamilyMember } from '@/api/family'
import type { Tag } from '@/api/tag'
import { loadTransactionDialogOptions } from './transactionDialogOptions'

const category: Category = {
  id: 'category-1',
  name: '餐饮',
  type: 'expense',
  icon: 'utensils',
  color: '#ff0000',
  is_system: false,
  sort_order: 0,
}

const accounts: AccountListResponse = {
  list: [
    {
      id: 'account-1',
      name: '现金',
      type: 'cash',
      icon: 'wallet',
      color: '#00ff00',
      initial_balance: 0,
      current_balance: 100,
      total_paid: 0,
      is_archived: false,
      sort_order: 0,
    },
  ],
  total_assets: 100,
  total_liabilities: 0,
  net_assets: 100,
}

const member: FamilyMember = {
  id: 'member-1',
  name: '小明',
  relationship: '家人',
  avatar: '',
  color: '#0000ff',
  sort_order: 0,
  is_default: true,
  is_enabled: true,
}

const tag: Tag = {
  id: 'tag-1',
  user_id: 1,
  name: '报销',
  color: '#333333',
  icon: 'tag',
  is_system: false,
  used_count: 0,
  created_at: '2026-07-31T00:00:00Z',
  updated_at: '2026-07-31T00:00:00Z',
}

describe('loadTransactionDialogOptions', () => {
  it('keeps required account and category data when an optional tag load fails', async () => {
    const tagError = new Error('tag endpoint unavailable')
    const result = await loadTransactionDialogOptions({
      categories: async () => [category],
      accounts: async () => accounts,
      familyMembers: async () => [member],
      tags: async () => Promise.reject(tagError),
    })

    expect(result.categories).toEqual([category])
    expect(result.accounts).toEqual(accounts.list)
    expect(result.familyMembers).toEqual([member])
    expect(result.tags).toEqual([])
    expect(result.failures).toEqual({ tags: tagError })
  })

  it('isolates every source, including synchronous loader failures', async () => {
    const categoryError = new Error('category load failed')
    const familyError = new Error('family load failed')
    const result = await loadTransactionDialogOptions({
      categories: () => {
        throw categoryError
      },
      accounts: async () => accounts,
      familyMembers: async () => Promise.reject(familyError),
      tags: async () => [tag],
    })

    expect(result.categories).toEqual([])
    expect(result.accounts).toEqual(accounts.list)
    expect(result.familyMembers).toEqual([])
    expect(result.tags).toEqual([tag])
    expect(result.failures).toEqual({
      categories: categoryError,
      familyMembers: familyError,
    })
  })
})
