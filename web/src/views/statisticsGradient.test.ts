import { ref } from 'vue'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { componentScript } from '@/test/componentScript'

const views: ReturnType<typeof componentScript>[] = []
afterEach(() => views.splice(0).forEach(view => view.unmount()))

function chart(items: { category_id?: string; color: string; percentage: number; amount: number }[]) {
  const view = componentScript('views/StatisticsView.vue', ['categoryStats', 'categoryTotal', 'pieGradient'], {
    '@/api/statistics': { statisticsApi: {} },
    '@/composables/useToast': { toast: { error: vi.fn() } },
    '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0) },
  })
  views.push(view)
  view.entry.categoryStats.value = items
  return view.entry
}

describe('statistics gradient rendering scale', () => {
  it('merges adjacent equal colors without changing the displayed financial rows', () => {
    const rows = [
      { category_id: 'plan-a', color: '#007AFF', percentage: 20, amount: 20 },
      { category_id: 'plan-b', color: '#007AFF', percentage: 30, amount: 30 },
      { category_id: 'wallet-a', color: '#34C759', percentage: 25, amount: 25 },
      { category_id: 'wallet-b', color: '#34C759', percentage: 25, amount: 25 },
    ]
    const original = JSON.parse(JSON.stringify(rows))
    const e = chart(rows)
    expect(e.pieGradient.value).toBe('conic-gradient(#007AFF 0% 50%, #34C759 50% 100%)')
    expect(e.categoryStats.value).toEqual(original)
    expect(e.categoryStats.value).toHaveLength(4)
    expect(e.categoryTotal.value).toBe(100)
  })

  it('preserves separate sectors when the same color occurs after another color', () => {
    const e = chart([
      { color: '#007AFF', percentage: 20, amount: 20 },
      { color: '#34C759', percentage: 30, amount: 30 },
      { color: '#007AFF', percentage: 50, amount: 50 },
    ])
    expect(e.pieGradient.value).toBe('conic-gradient(#007AFF 0% 20%, #34C759 20% 50%, #007AFF 50% 100%)')
  })

  it('keeps a long same-color history out of the CSS gradient while retaining all categories', () => {
    const e = chart(Array.from({ length: 1280 }, (_, index) => ({
      color: index < 640 ? '#007AFF' : '#34C759', percentage: 0.078125, amount: 1,
    })))
    expect(e.pieGradient.value.length).toBeLessThan(256)
    expect(e.pieGradient.value).toBe('conic-gradient(#007AFF 0% 50%, #34C759 50% 100%)')
    expect(e.categoryStats.value).toHaveLength(1280)
    expect(e.categoryTotal.value).toBe(1280)
  })

  it('keeps the existing empty-chart appearance', () => {
    expect(chart([]).pieGradient.value).toBe('conic-gradient(#e5e7eb 0% 100%)')
  })
})
