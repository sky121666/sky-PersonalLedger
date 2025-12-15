import { get, post, put, del } from '@/utils/request'

export interface EntryPathResponse {
  entry_path: string
  enabled: boolean
  message?: string
}

export const systemApi = {
  getEntryPath(): Promise<EntryPathResponse> {
    return get<EntryPathResponse>('/system/entry-path')
  },

  setEntryPath(entryPath: string): Promise<EntryPathResponse> {
    return put<EntryPathResponse>('/system/entry-path', { entry_path: entryPath })
  },

  generateEntryPath(): Promise<EntryPathResponse> {
    return post<EntryPathResponse>('/system/entry-path/generate')
  },

  disableEntryPath(): Promise<EntryPathResponse> {
    return del<EntryPathResponse>('/system/entry-path')
  }
}
