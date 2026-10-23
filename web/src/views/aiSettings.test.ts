import { afterEach, describe, expect, it, vi } from 'vitest'
import { componentScript, deferred, flushWork } from '@/test/componentScript'
import type { AIProvider, AIProviderPreset } from '@/api/ai'

const provider: AIProvider = {
  id: 'one', name: 'Local AI', provider_type: 'openai_compatible',
  base_url: 'http://localhost:11434/v1', model: 'local-model', enabled: true,
  created_at: '2026-10-22T08:00:00Z', updated_at: '2026-10-22T08:00:00Z',
}
const preset: AIProviderPreset = {
  id: 'example', name: 'Example', provider_type: 'openai_compatible',
  base_url: 'https://ai.example.invalid/v1', model: 'example-model', models: ['example-model', 'other-model'],
}
const schedule = { enabled: true, weekly_enabled: true, monthly_enabled: false, hour: 8 }
const opened: ReturnType<typeof componentScript>[] = []
afterEach(() => { opened.splice(0).forEach(view => view.unmount()) })

function settings() {
  const api = {
    listProviders: vi.fn().mockResolvedValue([provider]),
    listProviderPresets: vi.fn().mockResolvedValue([preset]),
    getScheduleSettings: vi.fn().mockResolvedValue(schedule),
    createProvider: vi.fn().mockResolvedValue(provider),
    updateProvider: vi.fn().mockResolvedValue(provider),
    deleteProvider: vi.fn().mockResolvedValue(undefined),
    testProvider: vi.fn().mockResolvedValue({ ok: true }),
    updateScheduleSettings: vi.fn(), triggerSchedule: vi.fn(),
  }
  let guard!: () => boolean | Promise<boolean>
  const auth = { isLoggedIn: true }
  const router = { push: vi.fn() }
  const window = { addEventListener: vi.fn(), removeEventListener: vi.fn() }
  const view = componentScript('views/AISettingsView.vue', [
    'providers', 'providersLoading', 'loadError', 'schedule', 'scheduleError', 'scheduleStatus',
    'presets', 'presetsError', 'loadData', 'loadProviders', 'loadSchedule', 'loadPresets',
    'startCreate', 'editProvider', 'cancelEdit', 'editorOpen', 'editingProviderId', 'form', 'dirty',
    'applyPreset', 'selectedPresetId', 'modelSuggestions', 'saveProvider', 'formError', 'notice',
    'busy', 'awaitingReadback', 'retrySavedRead', 'testProvider', 'rowFeedback', 'toggleProvider',
    'askDelete', 'deleteTarget', 'deleteError', 'confirmDelete', 'closeDelete',
    'discardOpen', 'resolveDiscard', 'beforeUnload', 'goBack',
  ], {
    '@/api/ai': { aiApi: api },
    '@/stores/auth': { useAuthStore: () => auth },
    'vue-router': { useRouter: () => router, onBeforeRouteLeave: (fn: typeof guard) => { guard = fn } },
  }, {}, { URL, window })
  opened.push(view)
  return { ...view, api, router, window, auth, guard: () => guard() }
}

async function ready() {
  const s = settings()
  await s.entry.loadData()
  return s
}

async function newForm(s: ReturnType<typeof settings>) {
  await s.entry.startCreate()
  Object.assign(s.entry.form, { name: provider.name, base_url: provider.base_url, model: provider.model })
}

describe('AI settings saving', () => {
  it('explains a server-rejected local endpoint without exposing arbitrary errors', async () => {
    const s = await ready()
    await newForm(s)
    s.api.createProvider.mockRejectedValue(Object.assign(new Error('ai provider base url is invalid'), { status: 400 }))
    await s.entry.saveProvider()
    expect(s.entry.formError.value).toContain('服务器拒绝')
    expect(s.entry.formError.value).toContain('出站访问')
    expect(s.entry.form.base_url).toBe(provider.base_url)
    expect(s.entry.editorOpen.value).toBe(true)
  })

  it('omits an empty edit key, reads saved values back, and never tests automatically', async () => {
    const s = await ready()
    await s.entry.editProvider(provider)
    s.entry.form.name = 'Updated'
    const saved = { ...provider, name: 'Updated by server' }
    s.api.listProviders.mockResolvedValue([saved])
    await s.entry.saveProvider()
    expect(s.api.updateProvider).toHaveBeenCalledWith('one', {
      name: 'Updated', provider_type: 'openai_compatible', base_url: provider.base_url,
      model: 'local-model', enabled: true,
    })
    expect(s.api.createProvider).not.toHaveBeenCalled()
    expect(s.api.listProviders).toHaveBeenCalledTimes(2)
    expect(s.entry.providers.value).toEqual([saved])
    expect(s.entry.editorOpen.value).toBe(false)
    expect(s.entry.notice.value).not.toBe('')
    expect(s.api.testProvider).not.toHaveBeenCalled()
  })

  it('allows a keyless local service and prevents duplicate creates through readback', async () => {
    const s = await ready()
    await newForm(s)
    const write = deferred<AIProvider>(), read = deferred<AIProvider[]>()
    s.api.createProvider.mockReturnValue(write.promise)
    s.api.listProviders.mockReturnValue(read.promise)
    const saving = s.entry.saveProvider()
    await s.entry.saveProvider()
    await s.entry.testProvider(provider)
    expect(s.api.createProvider).toHaveBeenCalledTimes(1)
    expect(s.api.createProvider.mock.calls[0]![0]).not.toHaveProperty('api_key')
    write.resolve(provider)
    await flushWork()
    await s.entry.saveProvider()
    expect(s.entry.busy.value).toBe(true)
    expect(s.api.createProvider).toHaveBeenCalledTimes(1)
    expect(s.api.testProvider).not.toHaveBeenCalled()
    read.resolve([provider])
    await saving
    await s.entry.saveProvider()
    expect(s.api.createProvider).toHaveBeenCalledTimes(1)
  })

  it('clears the submitted key on successful save and reads back before closing', async () => {
    const s = await ready()
    await newForm(s)
    s.entry.form.api_key = 'synthetic-test-key'
    const read = deferred<AIProvider[]>()
    s.api.listProviders.mockReturnValue(read.promise)
    const saving = s.entry.saveProvider()
    await flushWork()
    expect(s.entry.form.api_key).toBe('')
    expect(s.entry.editorOpen.value).toBe(true)
    expect(s.entry.notice.value).toBe('')
    read.resolve([provider])
    await saving
    expect(s.entry.editorOpen.value).toBe(false)
    expect(s.entry.dirty.value).toBe(false)
  })

  it('retains the form and key on failed save without reporting success or leaking the error', async () => {
    const s = await ready()
    await newForm(s)
    s.entry.form.api_key = 'synthetic-test-key'
    s.api.createProvider.mockRejectedValue(Object.assign(new Error('synthetic-test-key'), { status: 400 }))
    await s.entry.saveProvider()
    expect(s.entry.form.api_key).toBe('synthetic-test-key')
    expect(s.entry.form.name).toBe('Local AI')
    expect(s.entry.editorOpen.value).toBe(true)
    expect(s.entry.dirty.value).toBe(true)
    expect(s.entry.formError.value).not.toBe('')
    expect(s.entry.formError.value).not.toContain('synthetic-test-key')
    expect(s.entry.notice.value).toBe('')
    expect(s.api.testProvider).not.toHaveBeenCalled()
  })

  it('keeps a successful create identity when readback fails and retries only the read', async () => {
    const s = await ready()
    await newForm(s)
    s.entry.form.api_key = 'synthetic-test-key'
    s.api.listProviders.mockRejectedValue(new Error('offline'))
    await s.entry.saveProvider()
    expect(s.entry.editingProviderId.value).toBe('one')
    expect(s.entry.awaitingReadback.value).toBe(true)
    expect(s.entry.form.api_key).toBe('')
    expect(s.entry.formError.value).not.toBe('')
    expect(s.entry.notice.value).toBe('')
    await s.entry.saveProvider()
    expect(s.api.createProvider).toHaveBeenCalledTimes(1)
    expect(s.api.updateProvider).not.toHaveBeenCalled()
    s.api.listProviders.mockResolvedValue([provider])
    await s.entry.retrySavedRead()
    expect(s.entry.editorOpen.value).toBe(false)
    expect(s.entry.providers.value).toEqual([provider])
  })

  it('blocks repeated create after a lost response while preserving the unsaved form', async () => {
    const s = await ready()
    await newForm(s)
    s.entry.form.api_key = 'synthetic-test-key'
    s.api.createProvider.mockRejectedValue(new Error('connection lost after commit'))
    await s.entry.saveProvider()
    await s.entry.saveProvider()
    expect(s.api.createProvider).toHaveBeenCalledTimes(1)
    expect(s.entry.form.api_key).toBe('synthetic-test-key')
    expect(s.entry.editorOpen.value).toBe(true)
    expect(s.entry.notice.value).toBe('')
    expect(s.entry.formError.value).toContain('未确认')
  })

  it('does not treat a readback missing the saved provider as success', async () => {
    const s = await ready()
    await newForm(s)
    s.api.listProviders.mockResolvedValue([])
    await s.entry.saveProvider()
    expect(s.entry.awaitingReadback.value).toBe(true)
    expect(s.entry.editorOpen.value).toBe(true)
    expect(s.entry.formError.value).not.toBe('')
    expect(s.entry.notice.value).toBe('')
  })

  it('preserves a typed key and enabled state when applying a preset', async () => {
    const s = await ready()
    await s.entry.editProvider(provider)
    s.entry.form.api_key = 'synthetic-test-key'
    s.entry.form.enabled = false
    s.entry.selectedPresetId.value = preset.id
    s.entry.applyPreset()
    expect(s.entry.form.api_key).toBe('synthetic-test-key')
    expect(s.entry.form.enabled).toBe(false)
    expect(s.entry.form.base_url).toBe(preset.base_url)
    expect(s.entry.modelSuggestions.value).toContain('other-model')
    s.entry.form.model = 'free-form/model'
    await s.entry.saveProvider()
    expect(s.api.updateProvider.mock.calls[0]![1]).toMatchObject({ api_key: 'synthetic-test-key', model: 'free-form/model', enabled: false })
  })

  it.each([
    'ftp://ai.example.invalid/v1', 'https://user:pass@ai.example.invalid/v1',
    'https://ai.example.invalid/v1?key=synthetic', 'https://ai.example.invalid/v1#key',
    '/relative', 'https:///missing-host', 'https://ai.example.invalid/v1?', 'https://ai.example.invalid/v1#',
  ])('rejects unsafe or malformed base URL %s before saving', async baseURL => {
    const s = await ready()
    await newForm(s)
    s.entry.form.base_url = baseURL
    await s.entry.saveProvider()
    expect(s.api.createProvider).not.toHaveBeenCalled()
    expect(s.entry.formError.value).not.toBe('')
  })
})

describe('AI settings reads and explicit actions', () => {
  it('keeps failed reads unknown, prevents creating from an empty-success illusion, and permits retry', async () => {
    const s = settings()
    s.api.listProviders.mockRejectedValue(new Error('offline'))
    s.api.getScheduleSettings.mockRejectedValue(new Error('offline'))
    await s.entry.loadData()
    expect(s.entry.providers.value).toBeNull()
    expect(s.entry.loadError.value).not.toBe('')
    expect(s.entry.schedule.value).toBeNull()
    expect(s.entry.scheduleStatus.value).toBe('状态未知')
    await s.entry.startCreate()
    expect(s.entry.editorOpen.value).toBe(false)
    expect(s.api.createProvider).not.toHaveBeenCalled()
    s.api.listProviders.mockResolvedValue([])
    s.api.getScheduleSettings.mockResolvedValue({ ...schedule, enabled: false })
    await s.entry.loadData()
    expect(s.entry.providers.value).toEqual([])
    expect(s.entry.scheduleStatus.value).toBe('已关闭')
    await s.entry.startCreate()
    expect(s.entry.editorOpen.value).toBe(true)
    expect(s.api.updateScheduleSettings).not.toHaveBeenCalled()
    expect(s.api.triggerSchedule).not.toHaveBeenCalled()
  })

  it('marks stale schedule data unknown after a refresh failure without changing system settings', async () => {
    const s = await ready()
    expect(s.entry.scheduleStatus.value).toBe('已开启')
    s.api.getScheduleSettings.mockRejectedValue(new Error('offline'))
    await s.entry.loadSchedule()
    expect(s.entry.scheduleStatus.value).toBe('状态未知')
    expect(s.entry.scheduleError.value).not.toBe('')
    expect(s.api.updateScheduleSettings).not.toHaveBeenCalled()
    expect(s.api.triggerSchedule).not.toHaveBeenCalled()
  })

  it('allows manual configuration when presets fail independently', async () => {
    const s = settings()
    s.api.listProviderPresets.mockRejectedValue(new Error('offline'))
    await s.entry.loadData()
    await newForm(s)
    expect(s.entry.presetsError.value).not.toBe('')
    await s.entry.saveProvider()
    expect(s.api.createProvider).toHaveBeenCalledTimes(1)
  })

  it.each([false, 'reject'])('reports an explicit test failure (%s), single-flights, and never changes the provider', async outcome => {
    const s = await ready()
    const request = deferred()
    s.api.testProvider.mockReturnValue(request.promise)
    const testing = s.entry.testProvider(provider)
    await s.entry.testProvider(provider)
    await s.entry.toggleProvider(provider)
    expect(s.api.testProvider).toHaveBeenCalledTimes(1)
    if (outcome === 'reject') request.reject(new Error('synthetic-secret-in-error'))
    else request.resolve({ ok: false })
    await testing
    expect(s.entry.rowFeedback.value.one.kind).toBe('error')
    expect(s.entry.rowFeedback.value.one.message).not.toContain('synthetic-secret-in-error')
    expect(s.api.updateProvider).not.toHaveBeenCalled()
    expect(s.entry.providers.value).toEqual([provider])
  })

  it('does not test while unsaved configuration is open', async () => {
    const s = await ready()
    await s.entry.editProvider(provider)
    s.entry.form.model = 'unsaved'
    await s.entry.testProvider(provider)
    expect(s.api.testProvider).not.toHaveBeenCalled()
    expect(s.entry.formError.value).toContain('先保存')
  })

  it('invalidates an old passing connection test when the saved configuration changes', async () => {
    const s = await ready()
    await s.entry.testProvider(provider)
    expect(s.entry.rowFeedback.value.one.kind).toBe('success')
    await s.entry.editProvider(provider)
    s.entry.form.model = 'new-model'
    s.api.listProviders.mockResolvedValue([{ ...provider, model: 'new-model' }])
    await s.entry.saveProvider()
    expect(s.entry.rowFeedback.value.one).toBeUndefined()
    expect(s.api.testProvider).toHaveBeenCalledTimes(1)
  })

  it('toggles only the selected provider, omits its key, and reads back', async () => {
    const s = await ready()
    const other = { ...provider, id: 'two', name: 'Second' }
    s.api.listProviders.mockResolvedValue([{ ...provider, enabled: false }, other])
    await s.entry.toggleProvider(provider)
    expect(s.api.updateProvider).toHaveBeenCalledWith('one', {
      name: 'Local AI', provider_type: 'openai_compatible', base_url: provider.base_url, model: provider.model, enabled: false,
    })
    expect(s.entry.providers.value[0].enabled).toBe(false)
    expect(s.entry.providers.value[1]).toEqual(other)
    expect(s.api.testProvider).not.toHaveBeenCalled()
  })

  it('requires delete confirmation, retains the target and inline error on failure, and single-flights', async () => {
    const s = await ready()
    s.entry.askDelete(provider)
    expect(s.api.deleteProvider).not.toHaveBeenCalled()
    const request = deferred()
    s.api.deleteProvider.mockReturnValue(request.promise)
    const deleting = s.entry.confirmDelete()
    s.entry.closeDelete()
    await s.entry.confirmDelete()
    expect(s.api.deleteProvider).toHaveBeenCalledTimes(1)
    expect(s.entry.deleteTarget.value.id).toBe('one')
    request.reject(new Error('offline'))
    await deleting
    expect(s.entry.deleteError.value).not.toBe('')
    expect(s.entry.deleteTarget.value.id).toBe('one')
    expect(s.entry.providers.value).toEqual([provider])
  })

  it('ignores superseded load results and all results after unmount', async () => {
    const s = settings(), old = deferred<AIProvider[]>()
    s.api.listProviders.mockReturnValueOnce(old.promise).mockResolvedValueOnce([])
    const loading = s.entry.loadProviders()
    await s.entry.loadProviders()
    old.resolve([provider])
    await loading
    expect(s.entry.providers.value).toEqual([])
    const late = deferred<AIProvider[]>()
    s.api.listProviders.mockReturnValue(late.promise)
    const unmountedLoad = s.entry.loadProviders()
    s.unmount()
    late.resolve([provider])
    await unmountedLoad
    expect(s.entry.providers.value).toEqual([])
  })

  it('does not read back or show save success after unmount', async () => {
    const s = await ready(), write = deferred<AIProvider>()
    await newForm(s)
    s.entry.form.api_key = 'synthetic-test-key'
    s.api.createProvider.mockReturnValue(write.promise)
    const saving = s.entry.saveProvider()
    s.unmount()
    write.resolve(provider)
    await saving
    expect(s.api.listProviders).toHaveBeenCalledTimes(1)
    expect(s.entry.notice.value).toBe('')
    expect(s.entry.form.api_key).toBe('')
  })
})

describe('AI settings unsaved changes', () => {
  it('protects cancel and switching editor, preserving the key when discard is declined', async () => {
    const s = await ready()
    await newForm(s)
    s.entry.form.api_key = 'synthetic-test-key'
    const cancelling = s.entry.cancelEdit()
    expect(s.entry.discardOpen.value).toBe(true)
    s.entry.resolveDiscard(false)
    await cancelling
    expect(s.entry.editorOpen.value).toBe(true)
    expect(s.entry.form.api_key).toBe('synthetic-test-key')
    const switching = s.entry.editProvider({ ...provider, id: 'two' })
    s.entry.resolveDiscard(false)
    await switching
    expect(s.entry.editingProviderId.value).toBeNull()
    const discard = s.entry.cancelEdit()
    s.entry.resolveDiscard(true)
    await discard
    expect(s.entry.editorOpen.value).toBe(false)
    expect(s.entry.form.api_key).toBe('')
  })

  it('protects route departure and browser unload, and routes back to /ai', async () => {
    const s = await ready()
    s.mount()
    await flushWork()
    await newForm(s)
    const event = { preventDefault: vi.fn(), returnValue: undefined }
    s.entry.beforeUnload(event)
    expect(event.preventDefault).toHaveBeenCalledOnce()
    const leaving = s.guard()
    s.entry.resolveDiscard(false)
    expect(await leaving).toBe(false)
    const confirmed = s.guard()
    s.entry.resolveDiscard(true)
    expect(await confirmed).toBe(true)
    s.entry.goBack()
    expect(s.router.push).toHaveBeenCalledWith('/ai')
    expect(s.window.addEventListener).toHaveBeenCalledWith('beforeunload', expect.any(Function))
    s.unmount()
    expect(s.window.removeEventListener).toHaveBeenCalledWith('beforeunload', expect.any(Function))
  })

  it('blocks route departure while saving', async () => {
    const s = await ready(), write = deferred<AIProvider>()
    await newForm(s)
    s.api.createProvider.mockReturnValue(write.promise)
    const saving = s.entry.saveProvider()
    expect(await s.guard()).toBe(false)
    write.resolve(provider)
    await saving
  })

  it('lets existing auth expiry redirect proceed despite unsaved edits or an active request', async () => {
    const s = await ready(), write = deferred<AIProvider>()
    await newForm(s)
    s.api.createProvider.mockReturnValue(write.promise)
    const saving = s.entry.saveProvider()
    s.auth.isLoggedIn = false
    expect(s.guard()).toBe(true)
    expect(s.entry.discardOpen.value).toBe(false)
    write.resolve(provider)
    await saving
  })
})
