import { expect, it, vi } from 'vitest'
const post = vi.hoisted(() => vi.fn().mockResolvedValue({ ok: true }))
vi.mock('@/utils/request', () => ({ post, get: vi.fn(), put: vi.fn(), del: vi.fn() }))
import { aiApi } from './ai'

it('allows the server connection-test deadline plus response overhead', async () => {
  await aiApi.testProvider('fixture')
  expect(post).toHaveBeenCalledWith('/ai/providers/fixture/test', undefined, { timeout: 15_000 })
})

it('allows the AI generation deadline plus response overhead', async () => {
  const params = { report_type: 'weekly', period_start: '2026-10-19', period_end: '2026-10-23', mask_names: true }
  await aiApi.generateReport(params)
  expect(post).toHaveBeenCalledWith('/ai/reports/generate', params, { timeout: 60_000 })
})
