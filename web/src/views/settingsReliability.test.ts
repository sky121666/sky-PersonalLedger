import { afterEach, describe, expect, it, vi } from 'vitest'
import { ref } from 'vue'
import { componentScript, deferred, flushWork } from '@/test/componentScript'

const opened: ReturnType<typeof componentScript>[] = []
afterEach(() => { opened.splice(0).forEach(view => view.unmount()) })

function settings() {
  const authApi = { getProfile: vi.fn(), updateProfile: vi.fn() }
  const notificationApi = { getSettings: vi.fn(), updateSettings: vi.fn(), testEmail: vi.fn() }
  const systemApi = { getEntryPath: vi.fn(), setEntryPath: vi.fn(), generateEntryPath: vi.fn(), disableEntryPath: vi.fn() }
  const request = { get: vi.fn(), put: vi.fn(), post: vi.fn() }
  const toast = { error: vi.fn(), warning: vi.fn(), success: vi.fn(), info: vi.fn() }
  const clipboard = { writeText: vi.fn() }
  const transactionImportApi = { list: vi.fn(), get: vi.fn(), preview: vi.fn(), validate: vi.fn(), commit: vi.fn(), rollback: vi.fn() }
  const view = componentScript('views/SettingsView.vue', [
    'openProfileModal', 'saveProfile', 'openNotificationModal', 'saveNotificationSettings', 'testNotification',
    'openSecurityModal', 'saveEntryPath', 'generateEntryPath', 'disableEntryPath', 'entryPathEnabled',
    'openAutoBackupModal', 'saveAutoBackupSettings', 'autoBackupForm', 'copyToken', 'copyEntryUrl', 'manualCopyText',
    'openTransactionImport', 'handleTransactionImportFileSelect', 'transactionImportFile', 'transactionImportPreview',
    'previewTransactionImport', 'selectTransactionImport', 'validateTransactionImport', 'commitTransactionImport',
    'rollbackTransactionImport', 'transactionImportLoading',
  ], {
    '@/api/auth': { authApi }, '@/api/notification': { notificationApi }, '@/api/system': { systemApi },
    '@/api/import': { transactionImportApi },
    '@/utils/request': request, '@/stores/auth': { useAuthStore: () => ({}) },
    '@/stores/theme': { useThemeStore: () => ({}) }, '@/composables/useToast': { toast },
    '@/composables/useLedgerMutation': { useLedgerMutationRevision: () => ref(0) },
    '../../package.json': { version: 'test' },
  }, {}, { window: { location: { origin: 'https://ledger.test' } }, navigator: { clipboard } })
  opened.push(view)
  return { ...view, authApi, notificationApi, systemApi, request, toast, clipboard, transactionImportApi }
}

it('does not replace a newly selected import file with late history', async () => {
  const s = settings()
  const previous = deferred()
  s.transactionImportApi.list.mockResolvedValue({ list: [{ id: 'previous' }] })
  s.transactionImportApi.get.mockReturnValue(previous.promise)
  const opening = s.entry.openTransactionImport()
  await flushWork()
  const file = { name: 'new-synthetic.json' }
  s.entry.handleTransactionImportFileSelect({ target: { files: [file] } })
  previous.resolve({ id: 'previous', status: 'rolled_back' })
  await opening
  expect(s.entry.transactionImportFile.value).toEqual(file)
  expect(s.entry.transactionImportPreview.value).toBeNull()
})

it.each(['preview', 'get', 'validate'] as const)('keeps a new file selected when an older import %s finishes', async method => {
  const s = settings()
  const first = deferred()
  const second = deferred()
  const fileA = { name: 'synthetic-a.json' }
  const fileB = { name: 'synthetic-b.json' }
  s.entry.handleTransactionImportFileSelect({ target: { files: [fileA] } })
  let oldRequest: Promise<unknown>
  if (method === 'preview') {
    s.transactionImportApi.preview.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise)
    oldRequest = s.entry.previewTransactionImport()
  } else if (method === 'get') {
    s.transactionImportApi.get.mockReturnValue(first.promise)
    oldRequest = s.entry.selectTransactionImport({ id: 'old' })
    s.transactionImportApi.preview.mockReturnValue(second.promise)
  } else {
    s.entry.transactionImportPreview.value = { id: 'old', status: 'previewed', invalid_rows: 0 }
    s.transactionImportApi.validate.mockReturnValue(first.promise)
    oldRequest = s.entry.validateTransactionImport()
    s.transactionImportApi.preview.mockReturnValue(second.promise)
  }
  s.entry.handleTransactionImportFileSelect({ target: { files: [fileB] } })
  const newRequest = s.entry.previewTransactionImport()
  first.resolve({ id: 'old', status: 'previewed', invalid_rows: 0 })
  await oldRequest
  expect(s.entry.transactionImportFile.value).toEqual(fileB)
  expect(s.entry.transactionImportPreview.value).toBeNull()
  expect(s.entry.transactionImportLoading.value).toBe(true)
  expect(s.toast.success).not.toHaveBeenCalled()
  second.resolve({ id: 'new', status: 'previewed', invalid_rows: 0 })
  await newRequest
  expect(s.entry.transactionImportPreview.value.id).toBe('new')
  expect(s.entry.transactionImportLoading.value).toBe(false)
})

it.each(['commit', 'rollback'] as const)('blocks file changes and duplicate writes during import %s', async method => {
  const s = settings()
  const writing = deferred()
  const preview = { id: 'writing', status: method === 'commit' ? 'previewed' : 'committed', invalid_rows: 0 }
  s.entry.transactionImportPreview.value = preview
  s.transactionImportApi[method].mockReturnValue(writing.promise)
  const action = method === 'commit' ? s.entry.commitTransactionImport : s.entry.rollbackTransactionImport
  const pending = action()
  s.entry.handleTransactionImportFileSelect({ target: { files: [{ name: 'next.json' }] } })
  await action()
  expect(s.transactionImportApi[method]).toHaveBeenCalledTimes(1)
  expect(s.entry.transactionImportPreview.value).toEqual(preview)
  writing.resolve({ ...preview, status: method === 'commit' ? 'committed' : 'rolled_back' })
  await pending
  expect(s.entry.transactionImportPreview.value.status).toBe(method === 'commit' ? 'committed' : 'rolled_back')
})

describe('settings load failures', () => {
  it('keeps loaded backup settings when the independent file list fails', async () => {
    const s = settings()
    const saved = { enabled: true, frequency: 'weekly', hour: 5, max_backups: 20 }
    s.request.get.mockImplementation(url => url.endsWith('settings') ? Promise.resolve(saved) : Promise.reject(new Error('list failed')))
    await s.entry.openAutoBackupModal()
    expect(s.entry.autoBackupForm.value).toEqual(saved)
    await s.entry.saveAutoBackupSettings()
    expect(s.request.put).toHaveBeenCalledWith('/backup/auto/settings', saved)
  })

  it.each(['profile', 'notification', 'security', 'backup'])('blocks %s writes after a failed read and permits them after retry', async type => {
    const s = settings()
    const cases: Record<string, any> = {
      profile: [s.authApi.getProfile, s.entry.openProfileModal, s.entry.saveProfile, s.authApi.updateProfile, { nickname: 'saved' }],
      notification: [s.notificationApi.getSettings, s.entry.openNotificationModal, s.entry.saveNotificationSettings, s.notificationApi.updateSettings, { enabled: true }],
      security: [s.systemApi.getEntryPath, s.entry.openSecurityModal, s.entry.saveEntryPath, s.systemApi.setEntryPath, { enabled: true, entry_path: '/saved' }],
      backup: [s.request.get, s.entry.openAutoBackupModal, s.entry.saveAutoBackupSettings, s.request.put, { enabled: true, files: [] }],
    }
    const [read, open, save, write, value] = cases[type]
    read.mockRejectedValue(new Error('read failed'))
    write.mockResolvedValue(value)
    await open()
    await save()
    expect(write).not.toHaveBeenCalled()
    read.mockResolvedValue(value)
    await open()
    await save()
    expect(write).toHaveBeenCalledTimes(1)
  })

  it('blocks backup saves while configuration is still loading', async () => {
    const s = settings()
    const reading = deferred()
    s.request.get.mockReturnValue(reading.promise)
    const load = s.entry.openAutoBackupModal()
    await s.entry.saveAutoBackupSettings()
    expect(s.request.put).not.toHaveBeenCalled()
    reading.resolve({ enabled: true, files: [] })
    await load
  })
})

describe('settings drafts and delivery', () => {
  it('requests a draft entry path and keeps the saved enabled state', async () => {
    const s = settings()
    s.systemApi.getEntryPath.mockResolvedValue({ entry_path: '', enabled: false })
    s.systemApi.generateEntryPath.mockResolvedValue({ entry_path: '/draft', enabled: true })
    await s.entry.openSecurityModal()
    await s.entry.generateEntryPath()
    expect(s.systemApi.generateEntryPath).toHaveBeenCalledWith({ draft: true })
    expect(s.entry.entryPathEnabled.value).toBe(false)
    expect(s.systemApi.setEntryPath).not.toHaveBeenCalled()
  })

  it('tests email using the displayed notification recipient', async () => {
    const s = settings()
    s.notificationApi.getSettings.mockResolvedValue({ smtp_host: 'smtp.example.com', email_to: 'reminders@example.com' })
    s.notificationApi.testEmail.mockResolvedValue({ success: true })
    await s.entry.openNotificationModal()
    await s.entry.testNotification('email')
    expect(s.notificationApi.testEmail).toHaveBeenCalledWith(expect.objectContaining({ email_to: 'reminders@example.com' }))
  })

  it.each(['copyToken', 'copyEntryUrl'])('%s waits for clipboard success and reports rejection', async action => {
    const s = settings()
    const pending = deferred()
    s.clipboard.writeText.mockReturnValue(pending.promise)
    const copying = s.entry[action]('visible-token')
    expect(s.toast.success).not.toHaveBeenCalled()
    pending.reject(new Error('clipboard denied'))
    await copying
    expect(s.toast.success).not.toHaveBeenCalled()
    expect(s.toast.warning).toHaveBeenCalled()
    expect(s.entry.manualCopyText.value).toBe(action === 'copyToken' ? 'visible-token' : 'https://ledger.test')
  })
})

describe('setup token lifecycle', () => {
  it('preserves a captured token when mounting a clean URL and clears after initialization', async () => {
    let token = 'captured-token'
    const access = { setSetupToken: (value: unknown) => { token = typeof value === 'string' ? value : ''; return token }, clearSetupToken: () => { token = '' } }
    const auth = { initialized: false, checkAuth: vi.fn(), init: vi.fn().mockResolvedValue(undefined) }
    const view = componentScript('views/SetupView.vue', ['password', 'confirmPassword', 'createAccessPassword'], {
      '@/stores/auth': { useAuthStore: () => auth }, '@/utils/setupAccess': access,
      '@/api/setup': { setupApi: { getStatus: vi.fn().mockResolvedValue({ initialized: false }) } },
      'vue-router': { useRoute: () => ({ query: {}, path: '/setup' }), useRouter: () => ({ replace: vi.fn() }) },
      '@/composables/useToast': { toast: { error: vi.fn(), warning: vi.fn(), success: vi.fn() } },
    })
    opened.push(view)
    view.mount()
    await flushWork()
    expect(token).toBe('captured-token')
    view.entry.password.value = 'password123'
    view.entry.confirmPassword.value = 'password123'
    await view.entry.createAccessPassword()
    expect(token).toBe('')
  })
})
