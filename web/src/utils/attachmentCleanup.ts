import { fileApi } from '@/api/file'

export function decodeAttachmentPaths(value?: string | null): string[] {
  if (!value) return []
  try {
    const parsed = JSON.parse(value)
    if (!Array.isArray(parsed)) return []
    return parsed
      .filter((item): item is string => typeof item === 'string')
      .map(item => item.trim())
      .filter(Boolean)
  } catch {
    return []
  }
}

export function getRemovedAttachmentPaths(
  originalValue?: string | null,
  retainedValue?: string | null,
): string[] {
  const retained = new Set(decodeAttachmentPaths(retainedValue))
  return [...new Set(decodeAttachmentPaths(originalValue))]
    .filter(path => !retained.has(path))
}

export async function deleteRemovedAttachments(
  originalValue?: string | null,
  retainedValue?: string | null,
): Promise<string[]> {
  const failedPaths: string[] = []
  for (const path of getRemovedAttachmentPaths(originalValue, retainedValue)) {
    try {
      await fileApi.delete(path)
    } catch {
      failedPaths.push(path)
    }
  }
  return failedPaths
}
