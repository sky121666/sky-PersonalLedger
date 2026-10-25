import type { Component } from 'vue'

export type WidgetSize = 'small' | 'medium' | 'large'
export type ViewportKind = 'desktop' | 'mobile'

export const WIDGET_KINDS = [
  'netAssets', 'monthlyFlow', 'budget', 'reminders', 'transactions', 'accounts',
  'account', 'calendar', 'lending', 'family', 'ai',
] as const

export type WidgetKind = typeof WIDGET_KINDS[number]
export type WidgetCategory = 'finance' | 'assets' | 'reminders' | 'more'
export type EmptyWidgetConfig = Record<string, never>
export type WidgetConfigByKind = {
  netAssets: EmptyWidgetConfig
  monthlyFlow: EmptyWidgetConfig
  budget: EmptyWidgetConfig
  reminders: EmptyWidgetConfig
  transactions: EmptyWidgetConfig
  accounts: EmptyWidgetConfig
  account: { accountId: string }
  calendar: EmptyWidgetConfig
  lending: EmptyWidgetConfig
  family: EmptyWidgetConfig
  ai: EmptyWidgetConfig
}

export interface WidgetDefinition {
  kind: WidgetKind
  title: string
  category: WidgetCategory
  supportedSizes: readonly WidgetSize[]
  repeatable: boolean
  requiresAccount: boolean
}

export type WidgetInstance = {
  [K in WidgetKind]: {
    id: string
    kind: K
    config: WidgetConfigByKind[K]
    sizes: Record<ViewportKind, WidgetSize>
  }
}[WidgetKind]

export interface HomeLayout {
  widgets: WidgetInstance[]
  orders: Record<ViewportKind, string[]>
}

export type ValidationResult<T> =
  | { ok: true; value: T }
  | { ok: false; issues: string[] }

export type WidgetRendererMap = Record<WidgetKind, Component>

const DEFINITIONS: Record<WidgetKind, WidgetDefinition> = {
  netAssets: { kind: 'netAssets', title: '净资产', category: 'finance', supportedSizes: ['medium'], repeatable: false, requiresAccount: false },
  monthlyFlow: { kind: 'monthlyFlow', title: '本月收支', category: 'finance', supportedSizes: ['medium'], repeatable: false, requiresAccount: false },
  budget: { kind: 'budget', title: '本月预算', category: 'finance', supportedSizes: ['small', 'medium', 'large'], repeatable: false, requiresAccount: false },
  reminders: { kind: 'reminders', title: '还款提醒', category: 'reminders', supportedSizes: ['small', 'medium'], repeatable: false, requiresAccount: false },
  transactions: { kind: 'transactions', title: '最近交易', category: 'finance', supportedSizes: ['medium', 'large'], repeatable: false, requiresAccount: false },
  accounts: { kind: 'accounts', title: '我的账户', category: 'assets', supportedSizes: ['medium'], repeatable: false, requiresAccount: false },
  account: { kind: 'account', title: '指定账户', category: 'assets', supportedSizes: ['small', 'medium'], repeatable: true, requiresAccount: true },
  calendar: { kind: 'calendar', title: '收支日历', category: 'finance', supportedSizes: ['large'], repeatable: false, requiresAccount: false },
  lending: { kind: 'lending', title: '借贷往来', category: 'finance', supportedSizes: ['small', 'medium'], repeatable: false, requiresAccount: false },
  family: { kind: 'family', title: '家庭支出', category: 'finance', supportedSizes: ['small', 'medium'], repeatable: false, requiresAccount: false },
  ai: { kind: 'ai', title: 'AI 分析', category: 'more', supportedSizes: ['small', 'medium'], repeatable: false, requiresAccount: false },
}

const DEFAULT_WIDGETS: readonly { id: string; kind: WidgetKind; sizes: Record<ViewportKind, WidgetSize> }[] = [
  { id: 'net-assets', kind: 'netAssets', sizes: { desktop: 'medium', mobile: 'medium' } },
  { id: 'accounts', kind: 'accounts', sizes: { desktop: 'medium', mobile: 'medium' } },
  { id: 'monthly-flow', kind: 'monthlyFlow', sizes: { desktop: 'medium', mobile: 'medium' } },
  { id: 'budget', kind: 'budget', sizes: { desktop: 'small', mobile: 'small' } },
  { id: 'reminders', kind: 'reminders', sizes: { desktop: 'small', mobile: 'medium' } },
  { id: 'transactions', kind: 'transactions', sizes: { desktop: 'large', mobile: 'large' } },
]

const VIEWPORTS: readonly ViewportKind[] = ['desktop', 'mobile']
const SIZES: readonly WidgetSize[] = ['small', 'medium', 'large']
const emptyConfig = (): EmptyWidgetConfig => ({})

function cloneWidget(widget: WidgetInstance): WidgetInstance {
  return {
    ...widget,
    config: { ...widget.config },
    sizes: { ...widget.sizes },
  } as WidgetInstance
}

function cloneLayout(layout: HomeLayout): HomeLayout {
  return {
    widgets: layout.widgets.map(cloneWidget),
    orders: { desktop: [...layout.orders.desktop], mobile: [...layout.orders.mobile] },
  }
}

export function createDefaultHomeLayout(): HomeLayout {
  const widgets = DEFAULT_WIDGETS.map(item => ({
    id: item.id,
    kind: item.kind,
    config: emptyConfig(),
    sizes: { ...item.sizes },
  })) as WidgetInstance[]
  const ids = widgets.map(widget => widget.id)
  return { widgets, orders: { desktop: [...ids], mobile: [...ids] } }
}

export function getWidgetDefinition(kind: WidgetKind): WidgetDefinition {
  return DEFINITIONS[kind]
}

export function getWidgetDefinitions(): readonly WidgetDefinition[] {
  return WIDGET_KINDS.map(getWidgetDefinition)
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const actual = Object.keys(value).sort()
  return actual.length === keys.length && actual.every((key, index) => key === [...keys].sort()[index])
}

function isWidgetKind(value: unknown): value is WidgetKind {
  return typeof value === 'string' && (WIDGET_KINDS as readonly string[]).includes(value)
}

function isWidgetSize(value: unknown): value is WidgetSize {
  return typeof value === 'string' && (SIZES as readonly string[]).includes(value)
}

export function normalizeHomeLayout(input: unknown): ValidationResult<HomeLayout> {
  const issues: string[] = []
  if (!isRecord(input) || !hasExactKeys(input, ['widgets', 'orders'])) {
    return { ok: false, issues: ['layout shape'] }
  }
  if (!Array.isArray(input.widgets) || !isRecord(input.orders)) {
    return { ok: false, issues: ['widgets/orders shape'] }
  }
  if (!hasExactKeys(input.orders, ['desktop', 'mobile'])) {
    return { ok: false, issues: ['orders viewports'] }
  }

  const widgets: WidgetInstance[] = []
  const ids = new Set<string>()
  const accountKeys = new Set<string>()
  for (const raw of input.widgets) {
    if (!isRecord(raw) || !hasExactKeys(raw, ['id', 'kind', 'config', 'sizes'])) {
      issues.push('widget shape')
      continue
    }
    if (typeof raw.id !== 'string' || raw.id.trim() === '') {
      issues.push('widget id')
      continue
    }
    if (ids.has(raw.id)) {
      issues.push(`duplicate widget ${raw.id}`)
      continue
    }
    ids.add(raw.id)
    if (!isWidgetKind(raw.kind)) {
      issues.push(`unknown widget kind ${String(raw.kind)}`)
      continue
    }
    if (!isRecord(raw.config)) {
      issues.push(`widget config ${raw.id}`)
      continue
    }
    const definition = getWidgetDefinition(raw.kind)
    if (definition.requiresAccount) {
      if (!hasExactKeys(raw.config, ['accountId']) || typeof raw.config.accountId !== 'string' || raw.config.accountId.trim() === '') {
        issues.push(`account config ${raw.id}`)
        continue
      }
      const accountKey = raw.config.accountId.trim()
      if (accountKeys.has(accountKey)) {
        issues.push(`duplicate account widget ${accountKey}`)
        continue
      }
      accountKeys.add(accountKey)
    } else if (!hasExactKeys(raw.config, [])) {
      issues.push(`unexpected config ${raw.id}`)
      continue
    }
    if (!isRecord(raw.sizes) || !hasExactKeys(raw.sizes, ['desktop', 'mobile'])) {
      issues.push(`sizes ${raw.id}`)
      continue
    }
    const sizes = {} as Record<ViewportKind, WidgetSize>
    for (const viewport of VIEWPORTS) {
      const size = raw.sizes[viewport]
      if (!isWidgetSize(size) || !definition.supportedSizes.includes(size)) {
        issues.push(`unsupported size ${raw.id}/${viewport}`)
      } else {
        sizes[viewport] = size
      }
    }
    widgets.push({
      id: raw.id,
      kind: raw.kind,
      config: definition.requiresAccount
        ? { accountId: String(raw.config.accountId).trim() }
        : emptyConfig(),
      sizes,
    } as WidgetInstance)
  }

  const orders = {} as Record<ViewportKind, string[]>
  for (const viewport of VIEWPORTS) {
    const order = input.orders[viewport]
    if (!Array.isArray(order) || order.some(id => typeof id !== 'string')) {
      issues.push(`order ${viewport}`)
      orders[viewport] = []
      continue
    }
    if (new Set(order).size !== order.length) issues.push(`duplicate order ${viewport}`)
    if (order.some(id => !ids.has(id as string))) issues.push(`unknown order ${viewport}`)
    if (widgets.some(widget => !order.includes(widget.id))) issues.push(`missing order ${viewport}`)
    orders[viewport] = [...order] as string[]
  }

  return issues.length ? { ok: false, issues } : { ok: true, value: cloneLayout({ widgets, orders }) }
}
