import type { HomeLayout, WidgetInstance, WidgetKind, WidgetSize } from './model'
import { normalizeHomeLayout } from './model'
import type { NavigationId } from '@/components/navigation/catalog'
import { normalizePinnedIds } from '@/components/navigation/catalog'

export type PreferencePartition = 'home' | 'navigation'
export type NavigationMode = 'top' | 'rail'
export interface NavigationPreferences { mode: NavigationMode; pinned: NavigationId[] }
export interface PreferenceValues { home: HomeLayout; navigation: NavigationPreferences }
export interface PreferenceScope { apiBase: string; userId: number }
export interface PreferenceEnvelope<T> { version: 1; revision: string; value: T }
export type PreferenceStorage = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>

export type ReadPreferenceResult<T> =
  | { status: 'missing' }
  | { status: 'valid'; envelope: PreferenceEnvelope<T> }
  | { status: 'invalid' }
  | { status: 'unsupported'; version: number }
  | { status: 'unavailable' }

export type WritePreferenceResult =
  | { status: 'saved'; revision: string }
  | { status: 'conflict'; revision: string | null; reason?: 'stale' | 'invalid' | 'unsupported' }
  | { status: 'failed' }

const NAMESPACE = 'personal-ledger:workspace'
const PREFERENCE_VERSION = 1
const MODES: readonly NavigationMode[] = ['top', 'rail']

export const DEFAULT_NAVIGATION: NavigationPreferences = {
  mode: 'top',
  pinned: normalizePinnedIds(undefined),
}

export function createPreferenceKey(scope: PreferenceScope, partition: PreferencePartition): string {
  if (!Number.isSafeInteger(scope.userId) || scope.userId <= 0) throw new Error('invalid preference owner')
  const apiBase = scope.apiBase.trim()
  if (!apiBase) throw new Error('invalid api base')
  return `${NAMESPACE}:${encodeURIComponent(apiBase)}:${scope.userId}:${partition}`
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function exactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const actual = Object.keys(value).sort()
  return actual.length === keys.length && actual.every((key, i) => key === [...keys].sort()[i])
}

function normalizeNavigation(value: unknown): NavigationPreferences | null {
  if (!isRecord(value) || !exactKeys(value, ['mode', 'pinned'])) return null
  if (!MODES.includes(value.mode as NavigationMode)) return null
  if (!Array.isArray(value.pinned) || value.pinned.some(id => typeof id !== 'string')) return null
  return { mode: value.mode as NavigationMode, pinned: normalizePinnedIds(value.pinned) }
}

function normalizeValue(partition: PreferencePartition, value: unknown): HomeLayout | NavigationPreferences | null {
  if (partition === 'home') {
    const result = normalizeHomeLayout(value)
    return result.ok ? result.value : null
  }
  return normalizeNavigation(value)
}

export function readPreferences<P extends PreferencePartition>(
  storage: PreferenceStorage,
  scope: PreferenceScope,
  partition: P,
): ReadPreferenceResult<PreferenceValues[P]> {
  let raw: string | null
  try {
    raw = storage.getItem(createPreferenceKey(scope, partition))
  } catch {
    return { status: 'unavailable' }
  }
  if (raw === null) return { status: 'missing' }
  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch {
    return { status: 'invalid' }
  }
  if (!isRecord(parsed) || typeof parsed.version !== 'number') return { status: 'invalid' }
  if (parsed.version !== PREFERENCE_VERSION) return { status: 'unsupported', version: parsed.version }
  if (!exactKeys(parsed, ['version', 'revision', 'value']) || typeof parsed.revision !== 'string' || !parsed.revision) {
    return { status: 'invalid' }
  }
  const value = normalizeValue(partition, parsed.value)
  if (value === null) return { status: 'invalid' }
  return {
    status: 'valid',
    envelope: { version: 1, revision: parsed.revision, value } as PreferenceEnvelope<PreferenceValues[P]>,
  }
}

function revision(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID()
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`
}

export function writePreferences<P extends PreferencePartition>(
  storage: PreferenceStorage,
  scope: PreferenceScope,
  partition: P,
  value: PreferenceValues[P],
  expectedRevision: string | null,
): WritePreferenceResult {
  const normalized = normalizeValue(partition, value)
  if (normalized === null) return { status: 'failed' }
  const current = readPreferences(storage, scope, partition)
  if (current.status === 'unavailable') return { status: 'failed' }
  if (current.status === 'invalid' || current.status === 'unsupported') {
    return { status: 'conflict', revision: null, reason: current.status }
  }
  if (current.status === 'missing' && expectedRevision !== null) {
    return { status: 'conflict', revision: null, reason: 'stale' }
  }
  if (current.status === 'valid' && current.envelope.revision !== expectedRevision) {
    return { status: 'conflict', revision: current.envelope.revision, reason: 'stale' }
  }
  const nextRevision = revision()
  const envelope = { version: 1 as const, revision: nextRevision, value: normalized }
  try {
    storage.setItem(createPreferenceKey(scope, partition), JSON.stringify(envelope))
  } catch {
    return { status: 'failed' }
  }
  return { status: 'saved', revision: nextRevision }
}

export function cloneHomeLayout(layout: HomeLayout): HomeLayout {
  return {
    widgets: layout.widgets.map(widget => ({
      ...widget,
      config: { ...widget.config },
      sizes: { ...widget.sizes },
    })) as WidgetInstance[],
    orders: { desktop: [...layout.orders.desktop], mobile: [...layout.orders.mobile] },
  }
}

export function cloneNavigation(value: NavigationPreferences): NavigationPreferences {
  return { mode: value.mode, pinned: [...value.pinned] }
}

// Called only by the explicit recovery action; future versions are never replaced.
export function recoverInvalidNavigation(storage: PreferenceStorage, scope: PreferenceScope): boolean {
  try {
    const key = createPreferenceKey(scope, 'navigation')
    const raw = storage.getItem(key)
    if (readPreferences(storage, scope, 'navigation').status !== 'invalid' || storage.getItem(key) !== raw) return false
    storage.setItem(key, JSON.stringify({ version: 1, revision: revision(), value: cloneNavigation(DEFAULT_NAVIGATION) }))
    return true
  } catch {
    return false
  }
}

export function recoverInvalidHome(storage: PreferenceStorage, scope: PreferenceScope, layout: HomeLayout): WritePreferenceResult {
  const checked = normalizeHomeLayout(layout)
  if (!checked.ok) return { status: 'failed' }
  try {
    const key = createPreferenceKey(scope, 'home'); const raw = storage.getItem(key)
    if (readPreferences(storage, scope, 'home').status !== 'invalid' || storage.getItem(key) !== raw) return { status: 'conflict', revision: null }
    const nextRevision = revision()
    storage.setItem(key, JSON.stringify({ version: 1, revision: nextRevision, value: checked.value }))
    return { status: 'saved', revision: nextRevision }
  } catch { return { status: 'failed' } }
}

export function accountWidgetId(accountId: string): string {
  return `account-${accountId}`
}

export function createAccountWidget(accountId: string): WidgetInstance {
  const id = accountWidgetId(accountId.trim())
  return {
    id,
    kind: 'account',
    config: { accountId: accountId.trim() },
    sizes: { desktop: 'small', mobile: 'medium' },
  }
}

export function isSupportedSize(kind: WidgetKind, size: WidgetSize): boolean {
  return ({ netAssets: ['medium'], monthlyFlow: ['medium'], budget: ['small', 'medium', 'large'], reminders: ['small', 'medium'], transactions: ['medium', 'large'], accounts: ['medium'], account: ['small', 'medium'], calendar: ['large'], lending: ['medium'], family: ['small', 'medium'], ai: ['medium'] } as Record<WidgetKind, readonly WidgetSize[]>)[kind].includes(size)
}
