import { describe, expect, it } from 'vitest'
import {
  WIDGET_KINDS,
  createDefaultHomeLayout,
  getWidgetDefinition,
  normalizeHomeLayout,
  type HomeLayout,
  type WidgetInstance,
} from './model'

describe('home widget catalog', () => {
  it('defines the complete approved catalog with only real supported sizes', () => {
    expect(WIDGET_KINDS).toEqual([
      'netAssets', 'monthlyFlow', 'budget', 'reminders', 'transactions', 'accounts',
      'account', 'calendar', 'lending', 'family', 'ai',
    ])
    expect(getWidgetDefinition('netAssets').supportedSizes).toEqual(['medium'])
    expect(getWidgetDefinition('transactions').supportedSizes).toEqual(['medium', 'large'])
    expect(getWidgetDefinition('calendar').supportedSizes).toEqual(['large'])
    expect(getWidgetDefinition('account')).toMatchObject({ repeatable: true, requiresAccount: true })
    expect(getWidgetDefinition('budget')).toMatchObject({ repeatable: false, requiresAccount: false })
  })

  it('creates the approved six-card default without sharing mutable references', () => {
    const first = createDefaultHomeLayout()
    expect(first.widgets.map(({ kind, sizes }) => [kind, sizes])).toEqual([
      ['netAssets', { desktop: 'medium', mobile: 'medium' }],
      ['accounts', { desktop: 'medium', mobile: 'medium' }],
      ['monthlyFlow', { desktop: 'medium', mobile: 'medium' }],
      ['budget', { desktop: 'small', mobile: 'small' }],
      ['reminders', { desktop: 'small', mobile: 'medium' }],
      ['transactions', { desktop: 'large', mobile: 'large' }],
    ])
    expect(first.orders.desktop).toEqual(first.widgets.map(widget => widget.id))
    expect(first.orders.mobile).toEqual(first.widgets.map(widget => widget.id))
    const second = createDefaultHomeLayout()
    expect(second.widgets).not.toBe(first.widgets)
    expect(second.widgets[0]).not.toBe(first.widgets[0])
    expect(second.widgets[0].sizes).not.toBe(first.widgets[0].sizes)
  })
})

describe('home layout validation', () => {
  const valid = (): HomeLayout => createDefaultHomeLayout()

  it.each(['lending', 'ai'] as const)('accepts small %s cards independently on each device while preserving saved medium cards', kind => {
    const layout: HomeLayout = {
      widgets: [{ id: kind, kind, config: {}, sizes: { desktop: 'small', mobile: 'medium' } }],
      orders: { desktop: [kind], mobile: [kind] },
    }
    expect(normalizeHomeLayout(layout)).toEqual({ ok: true, value: layout })
    layout.widgets[0]!.sizes = { desktop: 'medium', mobile: 'small' }
    expect(normalizeHomeLayout(layout)).toEqual({ ok: true, value: layout })
  })

  it('accepts an explicit empty layout as valid rather than replacing it with defaults', () => {
    const result = normalizeHomeLayout({ widgets: [], orders: { desktop: [], mobile: [] } })
    expect(result).toEqual({ ok: true, value: { widgets: [], orders: { desktop: [], mobile: [] } } })
  })

  it('preserves legacy order and per-device sizes rather than applying the new defaults', () => {
    const legacy = valid()
    const order = ['net-assets', 'monthly-flow', 'budget', 'reminders', 'transactions', 'accounts']
    legacy.orders = { desktop: [...order].reverse(), mobile: [...order] }
    legacy.widgets.find(widget => widget.id === 'reminders')!.sizes.mobile = 'small'
    const before = structuredClone(legacy)
    const result = normalizeHomeLayout(legacy)
    expect(result).toEqual({ ok: true, value: before })
    expect(legacy).toEqual(before)
  })

  it('rejects duplicate IDs, duplicate account content, unknown kinds and unknown fields', () => {
    const duplicate = valid()
    duplicate.widgets[1].id = duplicate.widgets[0].id
    expect(normalizeHomeLayout(duplicate).ok).toBe(false)

    const repeated = valid()
    repeated.widgets.push({
      id: 'account-1', kind: 'account', config: { accountId: 'card-1' },
      sizes: { desktop: 'small', mobile: 'medium' },
    })
    repeated.widgets.push({
      id: 'account-2', kind: 'account', config: { accountId: 'card-1' },
      sizes: { desktop: 'small', mobile: 'small' },
    })
    repeated.orders.desktop.push('account-1', 'account-2')
    repeated.orders.mobile.push('account-1', 'account-2')
    expect(normalizeHomeLayout(repeated).ok).toBe(false)

    expect(normalizeHomeLayout({ ...valid(), widgets: [{ ...valid().widgets[0], kind: 'future' }] }).ok).toBe(false)
    expect(normalizeHomeLayout({ ...valid(), unexpected: true }).ok).toBe(false)
    expect(normalizeHomeLayout({ widgets: [{ ...valid().widgets[0], config: { accountId: 'x' } }], orders: valid().orders }).ok).toBe(false)
  })

  it('requires a non-empty accountId only for the account kind', () => {
    const emptyAccount = valid()
    emptyAccount.widgets.push({
      id: 'account-empty', kind: 'account', config: { accountId: '  ' },
      sizes: { desktop: 'small', mobile: 'small' },
    })
    emptyAccount.orders.desktop.push('account-empty')
    emptyAccount.orders.mobile.push('account-empty')
    expect(normalizeHomeLayout(emptyAccount).ok).toBe(false)

    const unknownNonAccount = valid()
    unknownNonAccount.widgets[0] = { ...unknownNonAccount.widgets[0], config: { accountId: 'x' } } as WidgetInstance
    expect(normalizeHomeLayout(unknownNonAccount).ok).toBe(false)
  })

  it('requires exact order coverage, no duplicates and supported sizes per viewport', () => {
    const missing = valid()
    missing.orders.desktop.pop()
    expect(normalizeHomeLayout(missing).ok).toBe(false)

    const duplicateOrder = valid()
    duplicateOrder.orders.mobile[1] = duplicateOrder.orders.mobile[0]
    expect(normalizeHomeLayout(duplicateOrder).ok).toBe(false)

    const invalidSize = valid()
    invalidSize.widgets[0].sizes.desktop = 'small'
    expect(normalizeHomeLayout(invalidSize).ok).toBe(false)
  })

  it('normalizes supported account configurations and both independent viewport orders', () => {
    const input = valid()
    input.widgets.push({
      id: 'account-cash', kind: 'account', config: { accountId: 'cash-1' },
      sizes: { desktop: 'small', mobile: 'medium' },
    })
    input.orders.desktop.unshift('account-cash')
    input.orders.mobile.push('account-cash')
    const result = normalizeHomeLayout(input)
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.value).not.toBe(input)
      expect(result.value.widgets[0]).not.toBe(input.widgets[0])
      expect(result.value.orders.desktop).toEqual(['account-cash', ...input.orders.desktop.slice(1)])
      expect(result.value.orders.mobile).toEqual(input.orders.mobile)
    }
  })
})
