import { ref } from 'vue'

export interface WidgetRect { id: string; left: number; top: number; width: number; height: number }
export function useWidgetDrag(options: {
  getOrder: () => readonly string[]
  getPlacements: () => WidgetRect[]
  move: (id: string, offset: number) => void
  cancel: () => void
  getScrollOffset?: () => number
}) {
  const active = ref<{ id: string; target: string | null } | null>(null)
  let order: string[] = []; let rects: WidgetRect[] = []; let initialScroll = 0
  let frame: number | null = null; let point = { x: 0, y: 0 }
  let startPoint = { x: 0, y: 0 }
  function clear() {
    if (frame !== null) cancelAnimationFrame(frame)
    frame = null; active.value = null
  }
  function cancel() { if (!active.value) return; clear(); options.cancel() }
  function hit(x: number, y: number) {
    const projectedY = y + (options.getScrollOffset?.() ?? 0) - initialScroll
    return rects.find(rect => x >= rect.left && x <= rect.left + rect.width && projectedY >= rect.top && projectedY <= rect.top + rect.height)?.id ?? null
  }
  function start(id: string, x: number, y: number) {
    cancel(); order = [...options.getOrder()]; rects = options.getPlacements().map(rect => ({ ...rect }))
    if (!order.includes(id) || !rects.some(rect => rect.id === id)) return false
    initialScroll = options.getScrollOffset?.() ?? 0; point = { x, y }; startPoint = { x, y }; active.value = { id, target: id }; return true
  }
  function update(x: number, y: number) {
    if (!active.value) return
    point = { x, y }
    const render = () => { frame = null; if (active.value) active.value.target = hit(point.x, point.y) }
    if (typeof requestAnimationFrame === 'undefined') render()
    else if (frame === null) frame = requestAnimationFrame(render)
  }
  function finish(x: number, y: number) {
    if (!active.value) return
    const id = active.value.id; const target = hit(x, y)
    const unchanged = order.join('\0') === options.getOrder().join('\0')
    const moved = Math.hypot(x - startPoint.x, y - startPoint.y) >= 6
    clear()
    if (moved && target && target !== id && unchanged) options.move(id, order.indexOf(target) - order.indexOf(id))
  }
  return { active, start, update, finish, cancel }
}
