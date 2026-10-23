import { ref } from 'vue'

export function createIdempotencyKey() {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID()
  // getRandomValues also works for private deployments opened on a LAN HTTP origin.
  const bytes = crypto.getRandomValues(new Uint8Array(16))
  bytes[6] = (bytes[6]! & 0x0f) | 0x40
  bytes[8] = (bytes[8]! & 0x3f) | 0x80
  const hex = [...bytes].map(byte => byte.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

/** A dialog owns one submission session; reopening invalidates earlier responses. */
export function createFormSubmission() {
  const saving = ref(false)
  let generation = 0

  return {
    saving,
    reset() {
      generation += 1
      saving.value = false
    },
    begin() {
      if (saving.value) return null
      saving.value = true
      const current = ++generation
      return {
        isCurrent: () => generation === current,
        finish() {
          if (generation === current) saving.value = false
        },
      }
    },
  }
}
