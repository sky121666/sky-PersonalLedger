import { describe, expect, it } from 'vitest'
import { getColumnCount, packWidgets } from './layout'
import { createDefaultHomeLayout, type WidgetInstance } from './model'

const widget = (id: string, size: 'small' | 'medium' | 'large', kind: WidgetInstance['kind'] = 'budget'): WidgetInstance => ({
  id,
  kind,
  config: {},
  sizes: { desktop: size, mobile: size },
} as WidgetInstance)

describe('deterministic widget packing', () => {
  it.each([2, 4] as const)('groups small lending, AI and family cards in desktop pairs and separate mobile rows with %s columns', columns => {
    const widgets = [widget('lending', 'small', 'lending'), widget('ai', 'small', 'ai'), widget('family', 'small', 'family')]
    const before = structuredClone(widgets)
    const desktop = packWidgets(widgets, ['lending', 'ai', 'family'], columns, 'desktop')
    expect(desktop.map(p => [p.row, p.column, p.columnSpan])).toEqual([
      [0, 0, columns / 2], [0, columns / 2, columns / 2], [1, 0, columns / 2],
    ])
    const mobile = packWidgets(widgets, ['lending', 'ai', 'family'], columns, 'mobile')
    expect(mobile.map(p => [p.row, p.column, p.columnSpan])).toEqual([
      [0, 0, columns], [1, 0, columns], [2, 0, columns],
    ])
    expect(widgets).toEqual(before)
  })

  it('selects columns from available content width, not the device mode', () => {
    expect([327, 328, 399, 400, 687, 688].map(getColumnCount)).toEqual([1, 1, 1, 2, 2, 4])
  })

  it('places the approved desktop layout without overlap or dense reordering', () => {
    const layout = createDefaultHomeLayout()
    const placements = packWidgets(layout.widgets, layout.orders.desktop, 4, 'desktop')
    expect(placements.map(({ id, row, column, rowSpan, columnSpan }) => [id, row, column, rowSpan, columnSpan])).toEqual([
      ['net-assets', 0, 0, 1, 4],
      ['accounts', 1, 0, 1, 4],
      ['monthly-flow', 2, 0, 1, 4],
      ['budget', 3, 0, 1, 2],
      ['reminders', 3, 2, 1, 2],
      ['transactions', 4, 0, 1, 4],
    ])
    const occupied = new Set<string>()
    for (const p of placements) {
      for (let r = p.row; r < p.row + p.rowSpan; r++) {
        for (let c = p.column; c < p.column + p.columnSpan; c++) {
          const key = `${r}:${c}`
          expect(occupied.has(key)).toBe(false)
          occupied.add(key)
        }
      }
    }
  })

  it('keeps source order and never mutates widgets, order or full-width options', () => {
    const widgets = [widget('a', 'small'), widget('b', 'large'), widget('c', 'medium')]
    const order = ['c', 'a', 'b']
    const widgetsBefore = structuredClone(widgets)
    const orderBefore = [...order]
    const fullWidth = new Set(['b'])
    const placements = packWidgets(widgets, order, 2, 'mobile', { fullWidthIds: fullWidth })
    expect(placements.map(p => p.id)).toEqual(order)
    expect(placements.map(p => p.columnSpan)).toEqual([2, 1, 2])
    expect(widgets).toEqual(widgetsBefore)
    expect(order).toEqual(orderBefore)
    expect([...fullWidth]).toEqual(['b'])
  })

  it.each([
    [4, 'small', 2], [4, 'medium', 4], [4, 'large', 4],
    [2, 'small', 1], [2, 'medium', 2], [2, 'large', 2],
    [1, 'small', 1], [1, 'medium', 1], [1, 'large', 1],
  ] as const)('fits %s-column %s widgets without overflow', (columns, size, span) => {
    const placements = packWidgets([widget('only', size)], ['only'], columns, columns === 4 ? 'desktop' : 'mobile')
    expect(placements[0].columnSpan).toBe(span)
    expect(placements[0].column).toBeGreaterThanOrEqual(0)
    expect(placements[0].column + placements[0].columnSpan).toBeLessThanOrEqual(columns)
  })

  it('rejects duplicate, missing and unknown order IDs', () => {
    const widgets = [widget('a', 'small'), widget('b', 'small')]
    expect(() => packWidgets(widgets, ['a', 'a'], 2, 'mobile')).toThrow(/duplicate/i)
    expect(() => packWidgets(widgets, ['a'], 2, 'mobile')).toThrow(/missing/i)
    expect(() => packWidgets(widgets, ['a', 'b', 'ghost'], 2, 'mobile')).toThrow(/unknown/i)
  })

  it('uses content rows rather than forcing large cards to span two fixed-height rows', () => {
    const widgets = [widget('large', 'large'), widget('medium', 'medium')]
    expect(packWidgets(widgets, ['large', 'medium'], 4, 'desktop').map(p => [p.row, p.rowSpan])).toEqual([[0, 1], [1, 1]])
  })

  it('keeps saved small reminder sizes while projecting full-width readable mobile reminders', () => {
    const widgets = [widget('budget', 'small'), widget('reminder', 'small', 'reminders')]
    const before = structuredClone(widgets)
    expect(packWidgets(widgets, ['budget', 'reminder'], 2, 'mobile').map(p => [p.column, p.columnSpan])).toEqual([[0, 1], [0, 2]])
    expect(packWidgets(widgets, ['budget', 'reminder'], 4, 'desktop').map(p => [p.column, p.columnSpan])).toEqual([[0, 2], [2, 2]])
    expect(widgets).toEqual(before)
  })

  it('temporarily widens a two-column card only in the current projection', () => {
    const widgets = [widget('a', 'small'), widget('b', 'medium'), widget('c', 'small')]
    const placements = packWidgets(widgets, ['a', 'b', 'c'], 2, 'mobile', { fullWidthIds: new Set(['b']) })
    expect(placements.map(({ id, row, column, columnSpan }) => [id, row, column, columnSpan])).toEqual([
      ['a', 0, 0, 1], ['b', 1, 0, 2], ['c', 2, 0, 1],
    ])
    expect(widgets[1].sizes.mobile).toBe('medium')
  })

  it.each([1, 2, 4] as const)('keeps visual anchor order equal to source order with %s columns', columns => {
    const widgets = [widget('a', 'small'), widget('b', 'medium'), widget('c', 'small'), widget('d', 'large'), widget('e', 'small')]
    const order = widgets.map(widget => widget.id)
    for (const viewport of ['mobile', 'desktop'] as const) {
      const packed = packWidgets(widgets, order, columns, viewport)
      expect([...packed].sort((a, b) => a.row - b.row || a.column - b.column).map(item => item.id)).toEqual(order)
    }
  })
})
