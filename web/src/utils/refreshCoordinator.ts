export interface RefreshCoordinator {
  run(refresh: () => Promise<boolean>): Promise<boolean>
}

export function createRefreshCoordinator(): RefreshCoordinator {
  let pendingRefresh: Promise<boolean> | null = null

  return {
    run(refresh) {
      if (!pendingRefresh) {
        pendingRefresh = Promise.resolve()
          .then(refresh)
          .finally(() => {
            pendingRefresh = null
          })
      }

      return pendingRefresh
    },
  }
}
