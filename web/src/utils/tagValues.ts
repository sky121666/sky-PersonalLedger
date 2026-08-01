export function parseTransactionTags(value: unknown): string[] {
  if (Array.isArray(value)) {
    return uniqueTagNames(value)
  }
  if (typeof value !== 'string' || !value.trim()) {
    return []
  }

  try {
    const parsed: unknown = JSON.parse(value)
    if (Array.isArray(parsed)) {
      return uniqueTagNames(parsed)
    }
    if (typeof parsed === 'string') {
      return uniqueTagNames([parsed])
    }
  } catch {
    return uniqueTagNames(value.split(','))
  }
  return []
}

export function encodeTransactionTags(values: string[]): string {
  return JSON.stringify(uniqueTagNames(values))
}

function uniqueTagNames(values: unknown[]): string[] {
  const names = values
    .filter((value): value is string => typeof value === 'string')
    .map((value) => value.trim())
    .filter(Boolean)
  return [...new Set(names)].sort((left, right) => left.localeCompare(right, 'zh-CN'))
}
