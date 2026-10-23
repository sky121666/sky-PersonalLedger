import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useWorkspacePreferencesStore } from './workspacePreferences'
import { createPreferenceKey, writePreferences, type PreferenceStorage } from '@/components/home/preferences'
import { createDefaultHomeLayout } from '@/components/home/model'

const profile = vi.fn()
vi.mock('@/api/auth', () => ({ authApi: { getProfile: () => profile() } }))
vi.mock('@/stores/auth', () => ({ useAuthStore: () => ({ sessionGeneration: 7 }) }))

class MemoryStorage implements PreferenceStorage {
  data = new Map<string, string>()
  getItem(key: string) { return this.data.get(key) ?? null }
  setItem(key: string, value: string) { this.data.set(key, value) }
  removeItem(key: string) { this.data.delete(key) }
}

function setup(storage = new MemoryStorage()) {
  setActivePinia(createPinia())
  const store = useWorkspacePreferencesStore()
  store.attachStorage(storage)
  return { store, storage }
}

beforeEach(() => {
  vi.clearAllMocks()
  profile.mockResolvedValue({ id: 1, username: 'one' })
})

describe('owner resolution and draft isolation', () => {
  it('does not read preferences before the profile owner is confirmed', async () => {
    const { store, storage } = setup()
    const spy = vi.spyOn(storage, 'getItem')
    expect(store.ready).toBe(false)
    expect(spy).not.toHaveBeenCalled()
    expect(store.navigation.mode).toBe('top')
    expect(store.home.widgets).toHaveLength(6)
  })

  it('ignores a late profile from the previous session and never loads that user', async () => {
    const first = setup()
    let resolve!: (value: unknown) => void
    profile.mockReturnValueOnce(new Promise(yes => { resolve = yes }))
    const pending = first.store.resolveOwner(7)
    expect(profile).toHaveBeenCalledTimes(1)
    first.store.invalidateOwner()
    resolve({ id: 9 })
    await pending
    expect(first.store.owner).toBeNull()
    expect(first.store.home.widgets).toHaveLength(6)
  })

  it('cancels edits without writing storage and keeps old sidebar state untouched', async () => {
    const { store, storage } = setup()
    storage.data.set('sidebar-collapsed', 'true')
    await store.resolveOwner(7)
    store.beginEdit()
    store.moveWidget('budget', 1)
    store.cancelEdit()
    expect(store.dirty).toBe(false)
    expect(storage.data.get('sidebar-collapsed')).toBe('true')
    expect(storage.data.size).toBe(1)
  })
})

describe('shared widgets and independent viewports', () => {
  it('changes only the current viewport order and does not persist until commit', async () => {
    const { store, storage } = setup()
    await store.resolveOwner(7)
    if (!store.scope) throw new Error('scope not resolved')
    store.beginEdit()
    store.setViewport('mobile')
    store.moveWidget('budget', 1)
    expect(store.draft!.orders.desktop).toEqual(store.committed!.orders.desktop)
    expect(store.draft!.orders.mobile).not.toEqual(store.committed!.orders.mobile)
    expect(storage.data.size).toBe(0)
    store.cancelEdit()
  })

  it('adds a widget to both viewports, rejects duplicate account content and supports undo', async () => {
    const { store } = setup()
    await store.resolveOwner(7)
    store.beginEdit()
    const before = store.draft!.widgets.length
    store.addWidget('account', { accountId: 'card-1' })
    expect(store.draft!.widgets).toHaveLength(before + 1)
    expect(store.draft!.orders.desktop).toContain('account-card-1')
    expect(store.draft!.orders.mobile).toContain('account-card-1')
    expect(() => store.addWidget('account', { accountId: 'card-1' })).toThrow(/already/i)
    store.undoEdit()
    expect(store.draft!.widgets).toHaveLength(before)
  })

  it('restores home defaults across both viewports but preserves navigation', async () => {
    const { store } = setup()
    await store.resolveOwner(7)
    store.setNavigationMode('rail')
    store.setPinned(['home', 'transactions', 'more'])
    store.beginEdit()
    store.setViewport('mobile')
    store.moveWidget('budget', 1)
    store.restoreDefault()
    expect(store.draft!.widgets.map(w => w.id)).toEqual(createDefaultHomeLayout().widgets.map(w => w.id))
    expect(store.draft!.orders.desktop).toEqual(createDefaultHomeLayout().orders.desktop)
    expect(store.navigation.mode).toBe('rail')
    expect(store.navigation.pinned).toEqual(['home', 'transactions', 'more'])
  })
})

describe('partition commits and revisions', () => {
  it('exposes corrupt navigation and recovers only that partition on an explicit reset', async () => {
    const { store, storage } = setup()
    const key = createPreferenceKey({ apiBase: '/api/v1', userId: 1 }, 'navigation')
    storage.data.set(key, '{broken')
    await store.resolveOwner(7)
    expect(store.navigationIssue).toBe('invalid')
    store.beginEdit()
    store.moveWidget('budget', 1)
    const draft = JSON.parse(JSON.stringify(store.draft))
    expect(store.restoreNavigationDefaults()).toBe(true)
    expect(store.navigationIssue).toBeNull()
    expect(store.navigation.mode).toBe('top')
    expect(JSON.parse(storage.data.get(key)!).version).toBe(1)
    expect(store.draft).toEqual(draft)
    expect(store.homeRevision).toBeNull()
  })

  it('preserves future-version navigation verbatim and refuses recovery or customization', async () => {
    const { store, storage } = setup()
    const key = createPreferenceKey({ apiBase: '/api/v1', userId: 1 }, 'navigation')
    const future = JSON.stringify({ version: 99, revision: 'future', value: { mode: 'rail', pinned: ['home', 'more'] } })
    storage.data.set(key, future)
    await store.resolveOwner(7)
    expect(store.navigationIssue).toBe('unsupported')
    expect(store.reloadNavigation()).toBe(false)
    expect(store.restoreNavigationDefaults()).toBe(false)
    expect(() => store.setNavigationMode('rail')).toThrow()
    expect(storage.data.get(key)).toBe(future)
  })

  it('keeps the active home draft and revision while changing navigation', async () => {
    const { store } = setup()
    await store.resolveOwner(7)
    store.beginEdit()
    store.moveWidget('budget', 1)
    const draftBefore = JSON.parse(JSON.stringify(store.draft))
    const homeRevision = store.homeRevision
    store.setNavigationMode('rail')
    store.setPinned(['home', 'accounts', 'more'])
    expect(store.draft).toEqual(draftBefore)
    expect(store.homeRevision).toBe(homeRevision)
    expect(store.editing).toBe(true)
    expect(await store.commitEdit()).toEqual({ status: 'saved' })
    expect(store.navigation).toEqual({ mode: 'rail', pinned: ['home', 'accounts', 'more'] })
  })

  it('reloads only navigation after a conflict without acknowledging external home edits', async () => {
    const { store, storage } = setup()
    await store.resolveOwner(7)
    if (!store.scope) throw new Error('scope not resolved')
    store.beginEdit()
    store.moveWidget('budget', 1)
    const draftBefore = JSON.parse(JSON.stringify(store.draft))
    writePreferences(storage, store.scope, 'home', createDefaultHomeLayout(), null)
    writePreferences(storage, store.scope, 'navigation', { mode: 'rail', pinned: ['home', 'more'] }, null)
    expect(store.reloadNavigation()).toBe(true)
    expect(store.navigation.mode).toBe('rail')
    expect(store.draft).toEqual(draftBefore)
    expect(await store.commitEdit()).toEqual({ status: 'conflict' })
    expect(store.dirty).toBe(true)
  })

  it('commits only home and cannot overwrite navigation updated during editing', async () => {
    const { store, storage } = setup()
    await store.resolveOwner(7)
    if (!store.scope) throw new Error('scope not resolved')
    store.setNavigationMode('rail')
    const navKey = createPreferenceKey(store.scope, 'navigation')
    const navBefore = storage.data.get(navKey)
    store.beginEdit()
    store.moveWidget('budget', 1)
    expect(await store.commitEdit()).toMatchObject({ status: 'saved' })
    expect(storage.data.get(navKey)).toBe(navBefore)
    expect(store.dirty).toBe(false)
  })

  it('blocks a home commit after another tab updates its revision and keeps the draft', async () => {
    const { store, storage } = setup()
    await store.resolveOwner(7)
    if (!store.scope) throw new Error('scope not resolved')
    const other = createDefaultHomeLayout()
    other.orders.desktop.reverse()
    const otherWrite = writePreferences(storage, store.scope, 'home', other, null)
    expect(otherWrite.status).toBe('saved')
    store.beginEdit()
    store.moveWidget('budget', 1)
    expect(await store.commitEdit()).toEqual({ status: 'conflict' })
    expect(store.dirty).toBe(true)
    expect(store.draft).not.toBeNull()
  })

  it('does not let a same-partition storage event replace an active home draft', async () => {
    const { store, storage } = setup()
    await store.resolveOwner(7)
    if (!store.scope) throw new Error('scope not resolved')
    store.beginEdit()
    store.moveWidget('budget', 1)
    const draftBefore = JSON.parse(JSON.stringify(store.draft))
    const homeKey = createPreferenceKey(store.scope, 'home')
    storage.data.set(homeKey, JSON.stringify({ version: 1, revision: 'remote', value: createDefaultHomeLayout() }))
    store.handleStorage({ key: homeKey, newValue: storage.data.get(homeKey)! } as StorageEvent)
    expect(store.draft).toEqual(draftBefore)
    expect(store.homeRevision).toBeNull()
  })

  it('reports navigation storage failure instead of pretending the pin was saved', async () => {
    const { store, storage } = setup()
    await store.resolveOwner(7)
    storage.setItem = () => { throw new Error('quota') }
    expect(() => store.setPinned(['home', 'transactions', 'more'])).toThrow(/navigation failed/)
    expect(store.navigation.pinned).toEqual(['home', 'transactions', 'statistics', 'budgets', 'more'])
  })

  it('keeps editing and reports failure when storage rejects a write', async () => {
    const { store, storage } = setup()
    await store.resolveOwner(7)
    if (!store.scope) throw new Error('scope not resolved')
    storage.setItem = () => { throw new Error('quota') }
    store.beginEdit()
    store.moveWidget('budget', 1)
    expect(await store.commitEdit()).toEqual({ status: 'failed' })
    expect(store.dirty).toBe(true)
    expect(store.draft).not.toBeNull()
  })

  it.each(['commit', 'cancel'])('syncs navigation without touching the home draft before %s', async finish => {
    const { store, storage } = setup()
    await store.resolveOwner(7)
    if (!store.scope) throw new Error('scope not resolved')
    store.beginEdit()
    store.moveWidget('budget', 1)
    const draftBefore = JSON.parse(JSON.stringify(store.draft))
    const navKey = createPreferenceKey(store.scope, 'navigation')
    storage.data.set(navKey, JSON.stringify({ version: 1, revision: 'remote', value: { mode: 'rail', pinned: ['home', 'more'] } }))
    store.handleStorage({ key: navKey, newValue: storage.data.get(navKey)! } as StorageEvent)
    expect(store.draft).toEqual(draftBefore)
    expect(store.navigation.mode).toBe('rail')
    if (finish === 'commit') expect(await store.commitEdit()).toEqual({ status: 'saved' })
    else store.cancelEdit()
    expect(store.navigation.mode).toBe('rail')
    expect(() => store.setPinned(['home', 'transactions', 'more'])).not.toThrow()
  })

  it('invalidates memory and draft without deleting another user\'s persisted data', async () => {
    const { store, storage } = setup()
    await store.resolveOwner(7)
    if (!store.scope) throw new Error('scope not resolved')
    store.beginEdit()
    const homeKey = createPreferenceKey(store.scope, 'home')
    storage.data.set(homeKey, JSON.stringify({ version: 1, revision: 'other', value: createDefaultHomeLayout() }))
    store.invalidateOwner()
    expect(store.owner).toBeNull()
    expect(store.draft).toBeNull()
    expect(storage.data.has(homeKey)).toBe(true)
  })
})

describe('widget edit configuration transactions', () => {
  it('adds a chosen size in one undo step and reconfigures both orders atomically', async () => {
    const { store } = setup(); await store.resolveOwner(7); store.beginEdit()
    const count = store.home.widgets.length
    store.addWidget('account', { accountId: 'one' }, 'medium')
    expect(store.home.widgets.find(w => w.id === 'account-one')?.sizes.desktop).toBe('medium')
    store.undoEdit(); expect(store.home.widgets).toHaveLength(count)
    store.addWidget('account', { accountId: 'one' })
    store.configureAccount('account-one', 'two')
    for (const viewport of ['desktop','mobile'] as const) expect(store.home.orders[viewport]).toContain('account-two')
    store.undoEdit(); expect(store.home.widgets.find(w => w.id === 'account-one')).toBeTruthy()
  })
  it('loads an explicitly selected remote layout without changing navigation', async () => {
    const { store, storage } = setup(); await store.resolveOwner(7); store.beginEdit(); store.removeWidget('budget')
    if (!store.scope) throw Error('scope')
    const remote = createDefaultHomeLayout(); remote.orders.desktop.reverse()
    writePreferences(storage, store.scope, 'home', remote, null)
    expect(await store.commitEdit()).toEqual({ status: 'conflict' })
    store.setNavigationMode('rail'); expect(store.reloadHome()).toBe(true)
    expect(store.home.orders.desktop).toEqual(remote.orders.desktop); expect(store.navigation.mode).toBe('rail')
  })
})

describe('home recovery consent', () => {
  it('recovers corrupt home only after an explicit defaults action and successful completion', async () => {
    const { store, storage } = setup();const key=createPreferenceKey({apiBase:'/api/v1',userId:1},'home')
    storage.data.set(key,'{broken');await store.resolveOwner(7);store.beginEdit()
    expect(await store.commitEdit()).toEqual({status:'conflict'})
    store.restoreDefault();expect(storage.data.get(key)).toBe('{broken')
    store.undoEdit();expect(await store.commitEdit()).toEqual({status:'conflict'})
    store.restoreDefault();expect(await store.commitEdit()).toEqual({status:'saved'})
    expect(JSON.parse(storage.data.get(key)!).version).toBe(1)
  })
  it('never overwrites a future home version even after explicit defaults and completion', async () => {
    const { store, storage } = setup();const key=createPreferenceKey({apiBase:'/api/v1',userId:1},'home');const raw='{"version":99,"revision":"next","value":{}}'
    storage.data.set(key,raw);await store.resolveOwner(7);store.beginEdit();store.restoreDefault()
    expect(await store.commitEdit()).toEqual({status:'conflict'});expect(storage.data.get(key)).toBe(raw)
  })
})
