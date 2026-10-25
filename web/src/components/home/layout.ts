import type { ViewportKind, WidgetInstance, WidgetSize } from './model'

export interface Placement {
  id: string
  row: number
  column: number
  rowSpan: number
  columnSpan: number
}

export type ColumnCount = 1 | 2 | 4

export function getWidgetUnit(availableWidth: number, columns: ColumnCount): number {
  return Math.max(1, (availableWidth - (columns - 1) * 16) / columns)
}

export function getColumnCount(availableWidth: number): ColumnCount {
  // Half-width summaries need at least 192px each, plus the shared 16px gap.
  if (availableWidth < 400) return 1
  if (availableWidth < 688) return 2
  return 4
}

function spanFor(size: WidgetSize, columns: ColumnCount): { columnSpan: number; rowSpan: number } {
  // Rows follow content height; size selects a presentation, not a square footprint.
  return { columnSpan: size === 'small' ? Math.max(1, columns / 2) : columns, rowSpan: 1 }
}

export function packWidgets(
  widgets: readonly WidgetInstance[],
  order: readonly string[],
  columns: ColumnCount,
  _viewport: ViewportKind,
  options: { fullWidthIds?: ReadonlySet<string> } = {},
): Placement[] {
  const byId = new Map(widgets.map(widget => [widget.id, widget]))
  if (new Set(order).size !== order.length) throw new Error('duplicate order id')
  for (const id of order) if (!byId.has(id)) throw new Error(`unknown order id ${id}`)
  for (const widget of widgets) if (!order.includes(widget.id)) throw new Error(`missing order id ${widget.id}`)

  const occupancy: boolean[][] = []
  const canPlace = (row: number, column: number, rowSpan: number, columnSpan: number): boolean => {
    if (column + columnSpan > columns) return false
    for (let r = row; r < row + rowSpan; r++) {
      for (let c = column; c < column + columnSpan; c++) {
        if (occupancy[r]?.[c]) return false
      }
    }
    return true
  }
  const occupy = (row: number, column: number, rowSpan: number, columnSpan: number) => {
    for (let r = row; r < row + rowSpan; r++) {
      occupancy[r] ??= []
      for (let c = column; c < column + columnSpan; c++) occupancy[r][c] = true
    }
  }

  let cursor = 0
  return order.map(id => {
    const widget = byId.get(id)!
    const size = widget.sizes[_viewport]
    const base = spanFor(size, columns)
    const columnSpan = options.fullWidthIds?.has(id) || (_viewport === 'mobile' && ['reminders', 'lending', 'ai', 'family'].includes(widget.kind))
      ? columns : base.columnSpan
    let row = Math.floor(cursor / columns)
    let column = cursor % columns
    while (!canPlace(row, column, base.rowSpan, columnSpan)) {
      column += 1
      if (column + columnSpan > columns) {
        column = 0
        row += 1
      }
    }
    occupy(row, column, base.rowSpan, columnSpan)
    cursor = row * columns + column + 1
    return { id, row, column, rowSpan: base.rowSpan, columnSpan }
  })
}
