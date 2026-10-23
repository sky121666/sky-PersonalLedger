import { describe, expect, it, vi } from 'vitest'
import { componentScript, deferred } from '@/test/componentScript'
import { retryParams } from '@/utils/aiReportPresentation'

const provider = { id: 'p', enabled: true }
const params = { report_type: 'monthly', provider_id: 'p', period_start: '2026-10-01', period_end: '2026-10-22', mask_names: true }
const report = (id: string, status = 'completed') => ({ id, ...params, status, prompt_version: 'personal-ledger-v3-masked', content_json: '{"summary":"A valid summary"}' })
function setup() {
  const api = { listProviders: vi.fn().mockResolvedValue([provider]), listReports: vi.fn().mockResolvedValue([report('old')]), generateReport: vi.fn(), deleteReport: vi.fn().mockResolvedValue(undefined) }
  const toast = { success: vi.fn(), error: vi.fn() }
  const view = componentScript('views/AIView.vue', ['loadData', 'generateReport', 'attempt', 'notice', 'displayReport', 'selectedReport', 'loadError', 'generating', 'openGenerate', 'showGenerate', 'initialRequest', 'canStart', 'selectHistory'], {
    '@/api/ai': { aiApi: api }, '@/composables/useToast': { toast }, '@/assets/ai-report.css': {},
  })
  return { ...view, api, toast }
}

describe('report-first AI workflow', () => {
  it('keeps server-side running tasks protected when viewing an older report', async () => {
    const v = setup(); v.api.listReports.mockResolvedValue([report('running', 'running'), report('old')])
    await v.entry.loadData(); v.entry.selectHistory(report('old'))
    expect(v.entry.notice.value?.status).toBe('running')
    expect(v.entry.canStart.value).toBe(false)
    v.entry.openGenerate(true); expect(v.entry.showGenerate.value).toBe(false)
    await v.entry.generateReport(params); expect(v.api.generateReport).not.toHaveBeenCalled()
  })
  it('blocks new and retried requests when a refreshed state cannot be confirmed', async () => {
    const v = setup(); await v.entry.loadData()
    v.api.listProviders.mockRejectedValue(Error('offline')); await v.entry.loadData()
    expect(v.entry.canStart.value).toBe(false)
    v.entry.openGenerate(true); expect(v.entry.showGenerate.value).toBe(false)
    await v.entry.generateReport(params); expect(v.api.generateReport).not.toHaveBeenCalled()
  })
  it('retains the confirmed generated document if its immediate list read is lagging', async () => {
    const v = setup(); await v.entry.loadData()
    v.api.generateReport.mockResolvedValue(report('generated'))
    await v.entry.generateReport(params)
    expect(v.entry.displayReport.value.id).toBe('generated')
  })
  it('does not downgrade a confirmed result when an immediate read returns its older running state', async () => {
    const v = setup(); await v.entry.loadData()
    v.api.generateReport.mockResolvedValue(report('generated'))
    v.api.listReports.mockResolvedValue([report('generated', 'running'), report('old')])
    await v.entry.generateReport(params)
    expect(v.entry.displayReport.value.id).toBe('generated')
    expect(v.entry.notice.value).toBeNull()
  })
  it('does not let a local failed attempt bypass another server-side running task', async () => {
    const v = setup(); await v.entry.loadData()
    v.api.generateReport.mockResolvedValue(report('failed', 'failed'))
    v.api.listReports.mockResolvedValue([report('other', 'running'), report('old')])
    await v.entry.generateReport(params)
    expect(v.entry.canStart.value).toBe(false)
    expect(v.entry.notice.value?.status).toBe('running')
    v.entry.openGenerate(true); expect(v.entry.showGenerate.value).toBe(false)
    await v.entry.generateReport(params); expect(v.api.generateReport).toHaveBeenCalledTimes(1)
  })
  it('shows a failed attempt alongside the previous completed report on first load', async () => {
    const v = setup(); v.api.listReports.mockResolvedValue([report('failed', 'failed'), report('old')])
    await v.entry.loadData()
    expect(v.entry.notice.value.status).toBe('failed')
    expect(v.entry.displayReport.value.id).toBe('old')
    v.entry.openGenerate(true)
    expect(v.entry.initialRequest.value).toEqual(params)
  })
  it('reconciles a confirmed failure without clearing the prior report or auto generating again', async () => {
    const v = setup(); await v.entry.loadData()
    v.api.generateReport.mockImplementation(async () => { v.api.listReports.mockResolvedValue([report('new-failed', 'failed'), report('old')]); throw Error('incomplete') })
    await v.entry.generateReport(params)
    expect(v.entry.notice.value.status).toBe('failed')
    expect(v.entry.displayReport.value.id).toBe('old')
    expect(v.api.generateReport).toHaveBeenCalledTimes(1)
    expect(v.toast.success).not.toHaveBeenCalled()
  })
  it('never treats an older matching report as proof of a lost-response success', async () => {
    const v = setup(); await v.entry.loadData()
    v.api.generateReport.mockRejectedValue(Error('network lost'))
    await v.entry.generateReport(params)
    expect(v.entry.notice.value.status).toBe('unknown')
    expect(v.entry.canStart.value).toBe(false)
    expect(v.entry.displayReport.value.id).toBe('old')
    expect(v.api.generateReport).toHaveBeenCalledTimes(1)
  })
  it('recovers one new matching success after a lost response', async () => {
    const v = setup(); await v.entry.loadData()
    v.api.generateReport.mockImplementation(async () => { v.api.listReports.mockResolvedValue([report('new'), report('old')]); throw Error('network lost') })
    await v.entry.generateReport(params)
    expect(v.entry.notice.value).toBeNull()
    expect(v.entry.selectedReport.value.id).toBe('new')
  })
  it('does not overwrite the generated selection with a newer historical record', async () => {
    const v = setup(); await v.entry.loadData()
    v.api.generateReport.mockResolvedValue(report('generated'))
    v.api.listReports.mockResolvedValue([report('newer'), report('generated'), report('old')])
    await v.entry.generateReport(params)
    expect(v.entry.selectedReport.value.id).toBe('generated')
  })
  it('retains readable content on refresh failure and suppresses obsolete responses', async () => {
    const v = setup(); await v.entry.loadData()
    const old = deferred(); v.api.listReports.mockReturnValueOnce(old.promise)
    const read = v.entry.loadData()
    v.api.listReports.mockResolvedValue([report('fresh')]); await v.entry.loadData()
    old.resolve([report('stale')]); await read
    expect(v.entry.selectedReport.value.id).toBe('fresh')
    v.api.listReports.mockRejectedValue(Error('offline')); await v.entry.loadData()
    expect(v.entry.loadError.value).toBeTruthy()
    expect(v.entry.displayReport.value.id).toBe('fresh')
  })
  it('blocks duplicate generation and ignores completion after leaving the page', async () => {
    const v = setup(); await v.entry.loadData(); const gate = deferred(); v.api.generateReport.mockReturnValue(gate.promise)
    const first = v.entry.generateReport(params); await v.entry.generateReport(params)
    expect(v.api.generateReport).toHaveBeenCalledTimes(1)
    v.unmount(); gate.resolve(report('late')); await first
    expect(v.toast.success).not.toHaveBeenCalled()
    expect(v.entry.selectedReport.value.id).toBe('old')
  })
  it('does not claim a completed record with empty content is successful', async () => {
    const v = setup(); await v.entry.loadData()
    v.api.generateReport.mockResolvedValue({ ...report('bad'), content_json: '{}' })
    await v.entry.generateReport(params)
    expect(v.entry.notice.value.status).toBe('failed')
    expect(v.toast.success).not.toHaveBeenCalled()
  })
  it('preserves an explicitly unmasked request when preparing a failed retry', () => {
    expect(retryParams({ ...report('failed', 'failed'), prompt_version: 'personal-ledger-v3' } as any).mask_names).toBe(false)
  })
})
