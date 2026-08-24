import { describe, expect, it } from 'vitest'

import { createRequestGeneration } from './requestGeneration'

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise
  })

  return { promise, resolve }
}

describe('createRequestGeneration', () => {
  it('prevents an older response from replacing newer state', async () => {
    const generation = createRequestGeneration()
    const olderResponse = deferred<string>()
    const newerResponse = deferred<string>()
    let state = 'initial'

    const load = async (response: Promise<string>) => {
      const requestGeneration = generation.begin()
      const value = await response
      if (generation.isLatest(requestGeneration)) {
        state = value
      }
    }

    const olderLoad = load(olderResponse.promise)
    const newerLoad = load(newerResponse.promise)

    newerResponse.resolve('newer')
    await newerLoad
    olderResponse.resolve('older')
    await olderLoad

    expect(state).toBe('newer')
  })

  it('allows a date response only while its requested date is still selected', async () => {
    const generation = createRequestGeneration()
    const response = deferred<string>()
    let selectedDate = '2026-08-24'
    let state = 'initial'

    const loadDate = async (date: string) => {
      const requestGeneration = generation.begin()
      const value = await response.promise
      if (generation.isLatest(requestGeneration) && selectedDate === date) {
        state = value
      }
    }

    const pendingLoad = loadDate(selectedDate)
    selectedDate = '2026-08-25'
    response.resolve('stale date data')
    await pendingLoad

    expect(state).toBe('initial')
  })
})
