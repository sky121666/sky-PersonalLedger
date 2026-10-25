import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { authApi } from '@/api/auth'
import { useAuthStore } from '@/stores/auth'
import {
  DEFAULT_NAVIGATION,
  cloneHomeLayout,
  cloneNavigation,
  createAccountWidget,
  createPreferenceKey,
  readPreferences,
  recoverInvalidNavigation,
  recoverInvalidHome,
  writePreferences,
  type NavigationPreferences,
  type PreferenceScope,
  type PreferenceStorage,
} from '@/components/home/preferences'
import {
  createDefaultHomeLayout,
  getWidgetDefinition,
  normalizeHomeLayout,
  type HomeLayout,
  type WidgetInstance,
  type WidgetKind,
  type WidgetSize,
  type ViewportKind,
} from '@/components/home/model'
import { normalizePinnedIds } from '@/components/navigation/catalog'

type Draft = HomeLayout
type CommitResult = { status: 'saved' } | { status: 'conflict' } | { status: 'failed' }

function cloneWidgets(layout: HomeLayout): HomeLayout { return cloneHomeLayout(layout) }

function defaultLayout(): HomeLayout { return createDefaultHomeLayout() }

function normalizeDraft(layout: HomeLayout): HomeLayout {
  const result = normalizeHomeLayout(layout)
  if (!result.ok) throw new Error(`invalid home layout: ${result.issues.join(', ')}`)
  return result.value
}

function moveId(ids: string[], id: string, offset: number): string[] {
  const from = ids.indexOf(id)
  if (from < 0) throw new Error('widget not found')
  const to = Math.max(0, Math.min(ids.length - 1, from + offset))
  if (from === to) return [...ids]
  const next = [...ids]
  const [item] = next.splice(from, 1)
  next.splice(to, 0, item)
  return next
}

function syncOrders(layout: HomeLayout): HomeLayout {
  for (const viewport of ['desktop', 'mobile'] as const) {
    const known = new Set(layout.widgets.map(widget => widget.id))
    const kept = layout.orders[viewport].filter(id => known.has(id))
    for (const widget of layout.widgets) if (!kept.includes(widget.id)) kept.push(widget.id)
    layout.orders[viewport] = kept
  }
  return layout
}

export const useWorkspacePreferencesStore = defineStore('workspacePreferences', () => {
  const storage = ref<PreferenceStorage | null>(null)
  const owner = ref<number | null>(null)
  const scope = ref<PreferenceScope | null>(null)
  const ready = ref(false)
  const committed = ref<HomeLayout | null>(null)
  const draft = ref<Draft | null>(null)
  const undoStack = ref<Draft[]>([])
  const homeIssue = ref<'invalid' | 'unsupported' | 'unavailable' | null>(null)
  const recoverHomeOnCommit = ref(false)
  const recoveryUndoStack = ref<boolean[]>([])
  const homeRevision = ref<string | null>(null)
  const navigation = ref<NavigationPreferences>(cloneNavigation(DEFAULT_NAVIGATION))
  const navigationRevision = ref<string | null>(null)
  const navigationIssue = ref<'invalid' | 'unsupported' | 'unavailable' | null>(null)
  const viewport = ref<ViewportKind>('desktop')
  const ownerRequest = ref(0)
  const editing = computed(() => draft.value !== null)
  const dirty = computed(() => editing.value)
  const home = computed<HomeLayout>(() => draft.value ?? committed.value ?? defaultLayout())

  function attachStorage(value: PreferenceStorage) { storage.value = value }
  function setViewport(value: ViewportKind) { viewport.value = value }

  function clearMemory() {
    owner.value = null
    scope.value = null
    ready.value = false
    committed.value = null
    draft.value = null
    undoStack.value = []
    homeIssue.value = null; recoverHomeOnCommit.value = false; recoveryUndoStack.value = []
    homeRevision.value = null
    navigation.value = cloneNavigation(DEFAULT_NAVIGATION)
    navigationRevision.value = null
    navigationIssue.value = null
  }

  function invalidateOwner() {
    ownerRequest.value += 1
    clearMemory()
  }

  async function resolveOwner(sessionGeneration: number) {
    const request = ++ownerRequest.value
    const auth = useAuthStore()
    if (auth.sessionGeneration !== sessionGeneration) return false
    let profile: Awaited<ReturnType<typeof authApi.getProfile>>
    try { profile = await authApi.getProfile() } catch { return false }
    if (request !== ownerRequest.value || auth.sessionGeneration !== sessionGeneration) return false
    if (!Number.isSafeInteger(profile.id) || profile.id <= 0) return false
    const targetStorage = storage.value ?? localStorage
    const nextScope: PreferenceScope = { apiBase: '/api/v1', userId: profile.id }
    const homeRead = readPreferences(targetStorage, nextScope, 'home')
    const navRead = readPreferences(targetStorage, nextScope, 'navigation')
    owner.value = profile.id
    scope.value = nextScope
    committed.value = homeRead.status === 'valid' ? cloneHomeLayout(homeRead.envelope.value) : defaultLayout()
    homeRevision.value = homeRead.status === 'valid' ? homeRead.envelope.revision : null
    homeIssue.value = homeRead.status === 'valid' || homeRead.status === 'missing' ? null : homeRead.status
    navigation.value = navRead.status === 'valid' ? cloneNavigation(navRead.envelope.value) : cloneNavigation(DEFAULT_NAVIGATION)
    navigationRevision.value = navRead.status === 'valid' ? navRead.envelope.revision : null
    navigationIssue.value = navRead.status === 'valid' || navRead.status === 'missing' ? null : navRead.status
    ready.value = true
    return true
  }

  function beginEdit() {
    if (!ready.value) throw new Error('owner not resolved')
    draft.value = cloneWidgets(committed.value ?? defaultLayout())
    undoStack.value = []; recoveryUndoStack.value = []; recoverHomeOnCommit.value = false
  }

  function remember() {
    if (!draft.value) throw new Error('not editing')
    undoStack.value.push(cloneWidgets(draft.value)); recoveryUndoStack.value.push(recoverHomeOnCommit.value)
  }

  function cancelEdit() {
    draft.value = null
    undoStack.value = []; recoveryUndoStack.value = []; recoverHomeOnCommit.value = false
  }

  function undoEdit() {
    const previous = undoStack.value.pop()
    if (previous) { draft.value = previous; recoverHomeOnCommit.value = recoveryUndoStack.value.pop() ?? false }
  }

  function addWidget(kind: WidgetKind, config: { accountId?: string } = {}, size?: WidgetSize) {
    if (!draft.value) throw new Error('not editing')
    const definition = getWidgetDefinition(kind)
    let widget: WidgetInstance
    if (definition.requiresAccount) {
      const accountId = config.accountId?.trim()
      if (!accountId) throw new Error('accountId required')
      if (draft.value.widgets.some(item => item.kind === 'account' && item.config.accountId === accountId)) throw new Error('account widget already exists')
      widget = createAccountWidget(accountId)
    } else {
      if (draft.value.widgets.some(item => item.kind === kind)) throw new Error('widget already exists')
      widget = {
        id: kind,
        kind,
        config: {},
        sizes: { desktop: definition.supportedSizes[0], mobile: definition.supportedSizes[0] },
      } as WidgetInstance
    }
    if (size) {
      if (!definition.supportedSizes.includes(size)) throw new Error('unsupported widget size')
      widget.sizes[viewport.value] = size
    }
    remember()
    draft.value.widgets.push(widget)
    syncOrders(draft.value)
  }

  function configureAccount(id: string, accountId: string) {
    if (!draft.value) throw new Error('not editing')
    const widget = draft.value.widgets.find(w => w.id === id)
    if (!widget || widget.kind !== 'account' || !accountId.trim()) throw new Error('invalid account')
    if (draft.value.widgets.some(w => w.id !== id && w.kind === 'account' && w.config.accountId === accountId)) throw new Error('duplicate account')
    remember()
    const replacement = createAccountWidget(accountId)
    replacement.sizes = { ...widget.sizes }
    draft.value.widgets = draft.value.widgets.map(w => w.id === id ? replacement : w)
    for (const viewport of ['desktop', 'mobile'] as const) draft.value.orders[viewport] = draft.value.orders[viewport].map(key => key === id ? replacement.id : key)
  }

  function reloadHome() {
    if (!scope.value || !storage.value) return false
    const read = readPreferences(storage.value, scope.value, 'home')
    if (read.status !== 'valid' && read.status !== 'missing') return false
    committed.value = read.status === 'valid' ? cloneHomeLayout(read.envelope.value) : defaultLayout()
    homeRevision.value = read.status === 'valid' ? read.envelope.revision : null
    draft.value = cloneHomeLayout(committed.value); undoStack.value = []; recoveryUndoStack.value = []; recoverHomeOnCommit.value = false; homeIssue.value = null
    return true
  }

  function removeWidget(id: string) {
    if (!draft.value) throw new Error('not editing')
    remember()
    draft.value.widgets = draft.value.widgets.filter(widget => widget.id !== id)
    syncOrders(draft.value)
  }

  function moveWidget(id: string, offset: number) {
    if (!draft.value) throw new Error('not editing')
    remember()
    draft.value.orders[viewport.value] = moveId(draft.value.orders[viewport.value], id, offset)
  }

  function resizeWidget(id: string, size: WidgetSize) {
    if (!draft.value) throw new Error('not editing')
    const widget = draft.value.widgets.find(item => item.id === id)
    if (!widget) throw new Error('widget not found')
    const definition = getWidgetDefinition(widget.kind)
    if (!definition.supportedSizes.includes(size)) throw new Error('unsupported widget size')
    remember()
    widget.sizes[viewport.value] = size
  }

  function restoreDefault() {
    if (!draft.value) throw new Error('not editing')
    remember()
    draft.value = defaultLayout(); recoverHomeOnCommit.value = true
  }

  function setPinned(pinned: readonly string[]) {
    if (!ready.value || !scope.value || !storage.value) throw new Error('owner not resolved')
    const next = normalizePinnedIds(pinned)
    const result = writePreferences(storage.value, scope.value, 'navigation', { mode: navigation.value.mode, pinned: next }, navigationRevision.value)
    if (result.status !== 'saved') throw new Error(`navigation ${result.status}`)
    navigation.value = { mode: navigation.value.mode, pinned: next }
    navigationRevision.value = result.revision
  }

  function setNavigationMode(mode: 'top' | 'rail') {
    if (!ready.value || !scope.value || !storage.value) throw new Error('owner not resolved')
    const result = writePreferences(storage.value, scope.value, 'navigation', { mode, pinned: navigation.value.pinned }, navigationRevision.value)
    if (result.status !== 'saved') throw new Error(`navigation ${result.status}`)
    navigation.value = { mode, pinned: [...navigation.value.pinned] }
    navigationRevision.value = result.revision
  }

  function reloadNavigation() {
    if (!ready.value || !scope.value || !storage.value) return false
    const read = readPreferences(storage.value, scope.value, 'navigation')
    navigationIssue.value = read.status === 'valid' || read.status === 'missing' ? null : read.status
    if (read.status === 'valid') {
      navigation.value = cloneNavigation(read.envelope.value)
      navigationRevision.value = read.envelope.revision
      return true
    }
    if (read.status === 'missing') {
      navigation.value = cloneNavigation(DEFAULT_NAVIGATION)
      navigationRevision.value = null
      return true
    }
    return false
  }

  function restoreNavigationDefaults() {
    if (!ready.value || !scope.value || !storage.value) return false
    if (!recoverInvalidNavigation(storage.value, scope.value)) return false
    return reloadNavigation()
  }

  async function commitEdit(): Promise<CommitResult> {
    if (!draft.value || !scope.value || !storage.value) return { status: 'failed' }
    const value = normalizeDraft(cloneWidgets(draft.value))
    const current = readPreferences(storage.value, scope.value, 'home')
    homeIssue.value = current.status === 'valid' || current.status === 'missing' ? null : current.status
    const result = recoverHomeOnCommit.value && current.status === 'invalid'
      ? recoverInvalidHome(storage.value, scope.value, value)
      : writePreferences(storage.value, scope.value, 'home', value, homeRevision.value)
    if (result.status === 'saved') {
      committed.value = value
      homeRevision.value = result.revision; homeIssue.value = null; recoverHomeOnCommit.value = false; recoveryUndoStack.value = []
      draft.value = null
      undoStack.value = []
      return { status: 'saved' }
    }
    return { status: result.status === 'conflict' ? 'conflict' : 'failed' }
  }

  function handleStorage(event: Pick<StorageEvent, 'key' | 'newValue'>) {
    if (!scope.value || !event.key) return
    if (event.key === createPreferenceKey(scope.value, 'navigation')) {
      const read = readPreferences(storage.value ?? localStorage, scope.value, 'navigation')
      if (read.status === 'valid') {
        navigation.value = cloneNavigation(read.envelope.value)
        navigationRevision.value = read.envelope.revision
      }
      return
    }
    if (event.key === createPreferenceKey(scope.value, 'home')) {
      if (draft.value) return
      const read = readPreferences(storage.value ?? localStorage, scope.value, 'home')
      if (read.status === 'valid') {
        committed.value = cloneHomeLayout(read.envelope.value)
        homeRevision.value = read.envelope.revision
      }
    }
  }

  return {
    storage, owner, scope, ready, committed, draft, undoStack, homeRevision, homeIssue, navigationRevision,
    navigation, navigationIssue, viewport, editing, dirty, home,
    attachStorage, setViewport, resolveOwner, invalidateOwner, beginEdit, cancelEdit, undoEdit,
    addWidget, configureAccount, reloadHome, removeWidget, moveWidget, resizeWidget, restoreDefault,
    setPinned, setNavigationMode, reloadNavigation, restoreNavigationDefaults, commitEdit, handleStorage,
  }
})
