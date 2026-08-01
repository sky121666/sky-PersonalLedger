import { describe, expect, it, vi } from 'vitest'

import { createRefreshCoordinator } from './refreshCoordinator'

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void
  let reject!: (reason?: unknown) => void
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise
    reject = rejectPromise
  })

  return { promise, resolve, reject }
}

describe('createRefreshCoordinator', () => {
  it('shares one refresh across concurrent callers', async () => {
    const refreshResult = deferred<boolean>()
    const refresh = vi.fn(() => refreshResult.promise)
    const coordinator = createRefreshCoordinator()

    const pending = [
      coordinator.run(refresh),
      coordinator.run(refresh),
      coordinator.run(refresh),
    ]

    await Promise.resolve()
    expect(refresh).toHaveBeenCalledTimes(1)
    refreshResult.resolve(true)

    await expect(Promise.all(pending)).resolves.toEqual([true, true, true])
  })

  it('settles every caller when refresh returns false and allows retry', async () => {
    const coordinator = createRefreshCoordinator()
    const failedRefresh = vi.fn().mockResolvedValue(false)

    const results = await Promise.all([
      coordinator.run(failedRefresh),
      coordinator.run(failedRefresh),
      coordinator.run(failedRefresh),
    ])

    expect(failedRefresh).toHaveBeenCalledTimes(1)
    expect(results).toEqual([false, false, false])

    const retryRefresh = vi.fn().mockResolvedValue(true)
    await expect(coordinator.run(retryRefresh)).resolves.toBe(true)
    expect(retryRefresh).toHaveBeenCalledTimes(1)
  })

  it('rejects every caller when refresh throws and allows retry', async () => {
    const refreshResult = deferred<boolean>()
    const refresh = vi.fn(() => refreshResult.promise)
    const coordinator = createRefreshCoordinator()
    const pending = [
      coordinator.run(refresh),
      coordinator.run(refresh),
      coordinator.run(refresh),
    ]

    refreshResult.reject(new Error('refresh failed'))
    const results = await Promise.allSettled(pending)

    expect(refresh).toHaveBeenCalledTimes(1)
    expect(results.every(result => result.status === 'rejected')).toBe(true)

    const retryRefresh = vi.fn().mockResolvedValue(true)
    await expect(coordinator.run(retryRefresh)).resolves.toBe(true)
    expect(retryRefresh).toHaveBeenCalledTimes(1)
  })
})
