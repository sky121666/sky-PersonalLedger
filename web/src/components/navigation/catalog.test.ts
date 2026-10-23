import { describe, expect, it } from 'vitest'
import {
  NAVIGATION_IDS,
  getNavigationItem,
  getNavigationItems,
  getNavigationItemForRoute,
  normalizePinnedIds,
} from './catalog'

describe('navigation catalog', () => {
  it('contains every existing business destination and keeps fixed entries unremovable', () => {
    expect(NAVIGATION_IDS).toEqual([
      'home', 'transactions', 'statistics', 'budgets', 'accounts', 'reminders', 'lendings', 'account-logs',
      'family', 'ai', 'report', 'categories', 'tags', 'templates', 'settings', 'more',
    ])
    expect(getNavigationItem('home')).toMatchObject({ path: '/', pinnedByDefault: true, canUnpin: false })
    expect(getNavigationItem('more')).toMatchObject({ path: null, pinnedByDefault: true, canUnpin: false })
    expect(getNavigationItem('settings')).toMatchObject({ path: '/settings', pinnedByDefault: false })
    expect(getNavigationItems().map(item => item.id)).toEqual(NAVIGATION_IDS)
  })

  it('attributes account logs to accounts and the compatibility debt route to reminders', () => {
    expect(getNavigationItemForRoute('account-logs')).toMatchObject({ id: 'accounts', path: '/accounts' })
    expect(getNavigationItemForRoute('account-log-detail')).toMatchObject({ id: 'accounts', path: '/accounts' })
    expect(getNavigationItemForRoute('debt')).toMatchObject({ id: 'reminders', path: '/reminders' })
  })

  it('drops unknown, duplicate and unpinnable entries while keeping fixed entries once', () => {
    expect(normalizePinnedIds(['statistics', 'ghost', 'statistics', 'home', 'more', 'settings'])).toEqual([
      'home', 'statistics', 'settings', 'more',
    ])
  })

  it('keeps default pins and enforces stable ordering', () => {
    expect(normalizePinnedIds(undefined)).toEqual(['home', 'transactions', 'statistics', 'budgets', 'more'])
    expect(normalizePinnedIds([])).toEqual(['home', 'more'])
  })

  it('does not misclassify unsupported navigation names', () => {
    expect(getNavigationItems().every(item => item.path === null || item.path.startsWith('/'))).toBe(true)
  })
})
