import { del, getRaw, postForm } from '@/utils/request'

export interface UploadResult {
  url: string
  path: string
  filename: string
  size: number
}

function filenameFromPath(path: string): string {
  return path.split('/').pop() || 'attachment'
}

export const fileApi = {
  upload(data: FormData): Promise<UploadResult> {
    return postForm<UploadResult>('/upload', data)
  },

  uploadAvatar(data: FormData): Promise<UploadResult> {
    return postForm<UploadResult>('/upload/avatar', data)
  },

  delete(path: string): Promise<{ message: string }> {
    return del<{ message: string }>('/upload', { params: { path } })
  },

  async previewObjectUrl(path: string): Promise<string> {
    const response = await getRaw('/upload/download', { params: { path } })
    return URL.createObjectURL(response.data)
  },

  async download(path: string): Promise<void> {
    const response = await getRaw('/upload/download', { params: { path } })
    const objectUrl = URL.createObjectURL(response.data)
    const link = document.createElement('a')
    link.href = objectUrl
    link.download = filenameFromPath(path)
    document.body.appendChild(link)
    link.click()
    link.remove()
    URL.revokeObjectURL(objectUrl)
  }
}
