import { describe, expect, it } from 'vitest'
import {
  createPreferenceKey,
  readPreferences,
  writePreferences,
  type PreferenceStorage,
  type PreferenceScope,
} from './preferences'
import { createDefaultHomeLayout } from './model'

class MemoryStorage implements PreferenceStorage {
  data = new Map<string, string>()
  failRead = false
  failWrite = false
  getItem(key: string) {
    if (this.failRead) throw new Error('denied')
    return this.data.get(key) ?? null
  }
  setItem(key: string, value: string) {
    if (this.failWrite) throw new Error('quota')
    this.data.set(key, value)
  }
  removeItem(key: string) { this.data.delete(key) }
}

const scope = (userId: number): PreferenceScope => ({ apiBase: '/api/v1', userId })
const home = () => createDefaultHomeLayout()

describe('preference keys and envelopes', () => {
  it('separates users, partitions and API namespaces without putting version in the key', () => {
    const user1Home = createPreferenceKey(scope(1), 'home')
    const user2Home = createPreferenceKey(scope(2), 'home')
    const user1Nav = createPreferenceKey(scope(1), 'navigation')
    expect(user1Home).not.toBe(user2Home)
    expect(user1Home).not.toBe(user1Nav)
    expect(user1Home).not.toMatch(/preference[^:]*:v\d/i)
    expect(createPreferenceKey({ apiBase: '/other', userId: 1 }, 'home')).not.toBe(user1Home)
  })

  it('distinguishes missing, valid, invalid, unsupported and unavailable data without rewriting it', () => {
    const storage = new MemoryStorage()
    const key = createPreferenceKey(scope(1), 'home')
    expect(readPreferences(storage, scope(1), 'home')).toEqual({ status: 'missing' })
    const valid = { version: 1, revision: 'r1', value: home() }
    storage.data.set(key, JSON.stringify(valid))
    expect(readPreferences(storage, scope(1), 'home')).toMatchObject({ status: 'valid', envelope: { revision: 'r1' } })
    storage.data.set(key, '{bad')
    expect(readPreferences(storage, scope(1), 'home')).toEqual({ status: 'invalid' })
    storage.data.set(key, JSON.stringify({ ...valid, version: 2 }))
    expect(readPreferences(storage, scope(1), 'home')).toEqual({ status: 'unsupported', version: 2 })
    storage.failRead = true
    expect(readPreferences(storage, scope(1), 'home')).toEqual({ status: 'unavailable' })
  })

  it('validates partition values instead of treating arbitrary JSON as preferences', () => {
    const storage = new MemoryStorage()
    const key = createPreferenceKey(scope(1), 'navigation')
    storage.data.set(key, JSON.stringify({ version: 1, revision: 'r1', value: { mode: 'bottom', pinned: [] } }))
    expect(readPreferences(storage, scope(1), 'navigation')).toEqual({ status: 'invalid' })
    storage.data.set(key, JSON.stringify({ version: 1, revision: 'r1', value: { mode: 'top', pinned: ['ghost'] } }))
    expect(readPreferences(storage, scope(1), 'navigation')).toEqual({ status: 'valid', envelope: expect.objectContaining({ revision: 'r1' }) })
  })

  it('writes only the selected partition and reports quota failures', () => {
    const storage = new MemoryStorage()
    const result = writePreferences(storage, scope(1), 'home', home(), null)
    expect(result).toMatchObject({ status: 'saved', revision: expect.any(String) })
    expect([...storage.data.keys()]).toEqual([createPreferenceKey(scope(1), 'home')])
    storage.failWrite = true
    expect(writePreferences(storage, scope(1), 'home', home(), result.status === 'saved' ? result.revision : null)).toEqual({ status: 'failed' })
  })

  it('returns conflict for a stale revision and never overwrites invalid/unsupported content', () => {
    const storage = new MemoryStorage()
    const first = writePreferences(storage, scope(1), 'home', home(), null)
    expect(first.status).toBe('saved')
    const revision = first.status === 'saved' ? first.revision : ''
    expect(writePreferences(storage, scope(1), 'home', home(), 'stale')).toEqual({ status: 'conflict', revision, reason: 'stale' })
    const key = createPreferenceKey(scope(1), 'home')
    storage.data.set(key, JSON.stringify({ version: 1, revision: 'r1', value: { widgets: 'bad' } }))
    expect(writePreferences(storage, scope(1), 'home', home(), null)).toEqual({ status: 'conflict', revision: null, reason: 'invalid' })
    storage.data.set(key, JSON.stringify({ version: 2, revision: 'r2', value: {} }))
    expect(writePreferences(storage, scope(1), 'home', home(), null)).toEqual({ status: 'conflict', revision: null, reason: 'unsupported' })
  })

  it('allows an expected-missing write only when the key is absent', () => {
    const storage = new MemoryStorage()
    const first = writePreferences(storage, scope(1), 'home', home(), null)
    expect(first.status).toBe('saved')
    expect(writePreferences(storage, scope(1), 'home', home(), null)).toMatchObject({ status: 'conflict' })
  })
})
