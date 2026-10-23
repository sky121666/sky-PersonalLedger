export const NAVIGATION_IDS = [
  'home', 'transactions', 'statistics', 'budgets', 'accounts', 'reminders', 'lendings', 'account-logs',
  'family', 'ai', 'report', 'categories', 'tags', 'templates', 'settings', 'more',
] as const

export type NavigationId = typeof NAVIGATION_IDS[number]

export interface NavigationItem {
  id: NavigationId
  path: string | null
  label: string
  pinnedByDefault: boolean
  canUnpin: boolean
  activeFor: readonly string[]
}

const ITEMS: Record<NavigationId, NavigationItem> = {
  home: { id: 'home', path: '/', label: '首页', pinnedByDefault: true, canUnpin: false, activeFor: ['home'] },
  'account-logs': { id: 'account-logs', path: '/account-logs', label: '账户日志', pinnedByDefault: false, canUnpin: true, activeFor: ['account-logs', 'account-log-detail'] },
  transactions: { id: 'transactions', path: '/transactions', label: '明细', pinnedByDefault: true, canUnpin: true, activeFor: ['transactions'] },
  statistics: { id: 'statistics', path: '/statistics', label: '统计', pinnedByDefault: true, canUnpin: true, activeFor: ['statistics'] },
  budgets: { id: 'budgets', path: '/budgets', label: '预算', pinnedByDefault: true, canUnpin: true, activeFor: ['budgets'] },
  accounts: { id: 'accounts', path: '/accounts', label: '账户', pinnedByDefault: false, canUnpin: true, activeFor: ['accounts', 'account-logs', 'account-log-detail'] },
  reminders: { id: 'reminders', path: '/reminders', label: '负债', pinnedByDefault: false, canUnpin: true, activeFor: ['reminders', 'debt'] },
  lendings: { id: 'lendings', path: '/lendings', label: '借贷', pinnedByDefault: false, canUnpin: true, activeFor: ['lendings'] },
  family: { id: 'family', path: '/family', label: '家庭', pinnedByDefault: false, canUnpin: true, activeFor: ['family'] },
  ai: { id: 'ai', path: '/ai', label: 'AI 分析', pinnedByDefault: false, canUnpin: true, activeFor: ['ai', 'ai-settings'] },
  report: { id: 'report', path: '/report', label: '报告', pinnedByDefault: false, canUnpin: true, activeFor: ['report'] },
  categories: { id: 'categories', path: '/categories', label: '分类', pinnedByDefault: false, canUnpin: true, activeFor: ['categories'] },
  tags: { id: 'tags', path: '/tags', label: '标签', pinnedByDefault: false, canUnpin: true, activeFor: ['tags'] },
  templates: { id: 'templates', path: '/templates', label: '模板', pinnedByDefault: false, canUnpin: true, activeFor: ['templates'] },
  settings: { id: 'settings', path: '/settings', label: '设置', pinnedByDefault: false, canUnpin: true, activeFor: ['settings', 'appearance'] },
  more: { id: 'more', path: null, label: '更多', pinnedByDefault: true, canUnpin: false, activeFor: [] },
}

export function getNavigationItem(id: NavigationId): NavigationItem {
  return ITEMS[id]
}

export function getNavigationItems(): readonly NavigationItem[] {
  return NAVIGATION_IDS.map(getNavigationItem)
}

export function normalizePinnedIds(input: readonly string[] | undefined): NavigationId[] {
  const requested = new Set(input ?? ['home', 'transactions', 'statistics', 'budgets', 'more'])
  const pinned: NavigationId[] = ['home']
  for (const item of getNavigationItems()) {
    if (item.id !== 'home' && item.id !== 'more' && item.canUnpin && requested.has(item.id)) pinned.push(item.id)
  }
  pinned.push('more')
  return pinned
}

export function getNavigationItemForRoute(routeName: string | null | undefined): NavigationItem | null {
  if (!routeName) return null
  return getNavigationItems().find(item => item.activeFor.includes(routeName)) ?? null
}

export function getActiveNavigationId(routeName: string | null | undefined): NavigationId | null {
  if (!routeName) return null
  return getNavigationItems().find(item => item.activeFor.includes(routeName))?.id ?? null
}
