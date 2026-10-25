import { afterEach, describe, expect, it, vi } from 'vitest'
import { componentScript, deferred, flushWork } from '@/test/componentScript'

const views: ReturnType<typeof componentScript>[] = []
afterEach(() => {
  views.splice(0).forEach(view => view.unmount())
  vi.restoreAllMocks()
})

function setup(upload: (data: FormData) => Promise<unknown>, props = {}) {
  const toast = { error: vi.fn(), warning: vi.fn() }
  const view = componentScript('components/FileUpload.vue', [
    'uploadFiles', 'handleFileSelect', 'files', 'uploading', 'removeFile', 'failedUploads',
  ], {
    '@/api/file': { fileApi: { upload } },
    '@/composables/useToast': { toast },
  }, { category: 'lendings', refId: 'loan', modelValue: '', maxFiles: 5, ...props }, { FormData })
  views.push(view)
  vi.spyOn(console, 'error').mockImplementation(() => {})
  return { ...view, toast }
}

const attachment = (name: string) => new File(['proof'], name, { type: 'text/plain', lastModified: 123 })
const paths = (view: ReturnType<typeof setup>) =>
  view.emitted.filter(event => event[0] === 'update:modelValue').map(event => JSON.parse(event[1] as string))

describe('attachment upload recovery', () => {
  it('publishes busy state synchronously so the parent cannot save an incomplete batch', async () => {
    const pending = deferred()
    const view = setup(() => pending.promise)
    const batch = view.entry.uploadFiles([attachment('pending.txt')])
    expect(view.emitted.filter(event => event[0] === 'uploading-change')).toEqual([['uploading-change', true]])
    pending.resolve({ path: 'lendings/loan/pending.txt' })
    await batch
    expect(view.emitted.filter(event => event[0] === 'uploading-change')).toEqual([
      ['uploading-change', true], ['uploading-change', false],
    ])
  })
  it('keeps the first success when the next file fails and continues the remaining files', async () => {
    const view = setup(async data => {
      const name = (data.get('file') as File).name
      if (name === 'failed.txt') throw Error('offline')
      return { path: `lendings/loan/${name}` }
    })
    await view.entry.uploadFiles([attachment('first.txt'), attachment('failed.txt'), attachment('last.txt')])
    expect(paths(view).slice(-1)[0]).toEqual(['lendings/loan/first.txt', 'lendings/loan/last.txt'])
    expect(view.toast.error).toHaveBeenCalledWith(expect.stringContaining('failed.txt'))
    expect(view.entry.uploading.value).toBe(false)
  })

  it('emits a successful path before a later request finishes', async () => {
    const later = deferred()
    const view = setup(async data => (data.get('file') as File).name === 'later.txt'
      ? later.promise : { path: 'lendings/loan/first.txt' })
    const batch = view.entry.uploadFiles([attachment('first.txt'), attachment('later.txt')])
    await flushWork()
    expect(paths(view)).toEqual([['lendings/loan/first.txt']])
    later.resolve({ path: 'lendings/loan/later.txt' })
    await batch
  })

  it('blocks overlapping select/drop batches while an upload is pending', async () => {
    const pending = deferred()
    const sent: string[] = []
    const view = setup(data => {
      sent.push((data.get('file') as File).name)
      return pending.promise
    }, { maxFiles: 1 })
    const first = view.entry.uploadFiles([attachment('first.txt')])
    const overlapping = view.entry.uploadFiles([attachment('second.txt')])
    expect(sent).toEqual(['first.txt'])
    pending.resolve({ path: 'lendings/loan/first.txt' })
    await Promise.all([first, overlapping])
    expect(paths(view).slice(-1)[0]).toEqual(['lendings/loan/first.txt'])
  })

  it('enforces the limit before the parent echoes the emitted v-model value', async () => {
    const sent: string[] = []
    const view = setup(async data => {
      const name = (data.get('file') as File).name
      sent.push(name)
      return { path: `lendings/loan/${name}` }
    }, { maxFiles: 2, modelValue: '["existing.txt"]' })
    await view.entry.uploadFiles([attachment('first.txt'), attachment('extra.txt')])
    await view.entry.uploadFiles([attachment('again.txt')])
    expect(sent).toEqual(['first.txt'])
    expect(paths(view).slice(-1)[0]).toEqual(['existing.txt', 'lendings/loan/first.txt'])
    expect(view.toast.warning).toHaveBeenCalled()
  })

  it('reselects only the failed file without uploading an earlier success again', async () => {
    const sent: string[] = []
    let offline = true
    const view = setup(async data => {
      const name = (data.get('file') as File).name
      sent.push(name)
      if (name === 'retry.txt' && offline) throw Error('offline')
      return { path: `lendings/loan/${name}` }
    })
    const first = attachment('first.txt')
    const retry = attachment('retry.txt')
    await view.entry.uploadFiles([first, retry])
    offline = false
    const input = { files: [attachment('retry.txt')], value: 'retry.txt' }
    await view.entry.handleFileSelect({ target: input })
    expect(input.value).toBe('')
    expect(sent).toEqual(['first.txt', 'retry.txt', 'retry.txt'])
    expect(paths(view).slice(-1)[0]).toEqual(['lendings/loan/first.txt', 'lendings/loan/retry.txt'])
    expect(view.entry.failedUploads.value).toEqual([])
  })

  it('does not restore a removed attachment when a pending upload completes', async () => {
    const pending = deferred()
    const view = setup(() => pending.promise, { modelValue: '["old.txt"]' })
    const batch = view.entry.uploadFiles([attachment('new.txt')])
    await view.entry.removeFile('old.txt')
    pending.resolve({ path: 'lendings/loan/new.txt' })
    await batch
    expect(paths(view).slice(-1)[0]).toEqual(['lendings/loan/new.txt'])
  })

  it('treats an upload response without a path as a retryable file failure', async () => {
    const view = setup(async () => ({}))
    await view.entry.uploadFiles([attachment('missing.txt')])
    expect(paths(view)).toEqual([])
    expect(view.toast.error).toHaveBeenCalledWith(expect.stringContaining('missing.txt'))
  })

  it('never uploads in a disabled component', async () => {
    let uploads = 0
    const view = setup(async () => { uploads++; return { path: 'unexpected.txt' } }, { disabled: true })
    await view.entry.uploadFiles([attachment('disabled.txt')])
    expect(uploads).toBe(0)
  })
})
