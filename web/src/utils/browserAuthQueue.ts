// Cookie writes happen before Axios can reject an obsolete response. Drain the
// entire preceding response before allowing the next authentication mutation.
let tail: Promise<void> = Promise.resolve()

export function browserAuthMutation<T>(operation: () => Promise<T>): Promise<T> {
  const run = async (): Promise<T> => {
    // Locks coordinate same-origin tabs where the browser supports them.
    if (typeof navigator !== 'undefined' && navigator.locks) {
      return await navigator.locks.request('personal-ledger-browser-auth', operation)
    }
    return operation()
  }
  const pending = tail.then(run, run)
  tail = pending.then(() => undefined, () => undefined)
  return pending
}
