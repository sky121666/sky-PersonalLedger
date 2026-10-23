import { describe, expect, it, vi } from 'vitest'
import { useWidgetDrag } from './useWidgetDrag'

function fixture() {
  const order = ['a', 'b', 'c']
  const move = vi.fn(); const cancel = vi.fn()
  const drag = useWidgetDrag({ getOrder: () => order, getPlacements: () => [
    { id: 'a', left: 0, top: 0, width: 100, height: 100 },
    { id: 'b', left: 110, top: 0, width: 100, height: 100 },
    { id: 'c', left: 0, top: 110, width: 210, height: 200 },
  ], move, cancel })
  return { drag, move, cancel, order }
}

describe('widget pointer draft coordination', () => {
  it('commits exactly once at release using the frozen order and painted rectangles', () => {
    const { drag, move, order } = fixture()
    drag.start('a', 50, 50); drag.update(150, 50)
    expect(move).not.toHaveBeenCalled(); expect(order).toEqual(['a', 'b', 'c'])
    drag.finish(150, 50)
    expect(move).toHaveBeenCalledExactlyOnceWith('a', 1)
    drag.finish(150, 50); expect(move).toHaveBeenCalledTimes(1)
  })
  it.each(['pointercancel', 'Escape', 'blur', 'viewport', 'unmount'])('cancels %s without moving the draft', () => {
    const { drag, move, cancel } = fixture()
    drag.start('c', 50, 150); drag.update(50, 50); drag.cancel()
    expect(move).not.toHaveBeenCalled(); expect(cancel).toHaveBeenCalledOnce()
    expect(drag.active.value).toBeNull()
  })
  it('rejects unknown sources, drops in gaps and changed layouts', () => {
    const { drag, move, order } = fixture()
    expect(drag.start('unknown', 1, 1)).toBe(false)
    drag.start('a', 50, 50); drag.finish(105, 50); expect(move).not.toHaveBeenCalled()
    drag.start('a', 50, 50); order.reverse(); drag.finish(150, 50)
    expect(move).not.toHaveBeenCalled()
  })
  it('does not reorder a nearly stationary press when an animating handle differs from the final grid rectangles', () => {
    const { drag, move } = fixture()
    drag.start('b', 50, 50)
    drag.finish(51, 52)
    expect(move).not.toHaveBeenCalled()
    expect(drag.active.value).toBeNull()
  })
})
