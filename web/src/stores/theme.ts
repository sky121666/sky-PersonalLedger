import { computed, onScopeDispose, ref, watch } from 'vue'
import { defineStore } from 'pinia'

export type ThemePreference = 'light' | 'dark' | 'system'

export const useThemeStore = defineStore('theme', () => {
  const preference = ref<ThemePreference>('system')
  const systemDark = ref(false)
  const isDark = computed(() => preference.value === 'dark' || (preference.value === 'system' && systemDark.value))
  let media: MediaQueryList | null = null
  let listening = false

  function applyTheme() {
    document.documentElement.classList.toggle('dark', isDark.value)
    document.documentElement.style.colorScheme = isDark.value ? 'dark' : 'light'
  }

  function systemChanged() { systemDark.value = media?.matches ?? false }
  function readPreference(value: string | null): ThemePreference {
    return value === 'light' || value === 'dark' ? value : 'system'
  }
  function storageChanged(event: StorageEvent) {
    if (event.key !== 'theme' && event.key !== null) return
    preference.value = readPreference(event.key === null ? null : event.newValue)
    applyTheme()
  }

  function init() {
    try { preference.value = readPreference(localStorage.getItem('theme')) } catch { preference.value = 'system' }
    media?.removeEventListener('change', systemChanged)
    media = window.matchMedia('(prefers-color-scheme: dark)')
    systemChanged()
    media.addEventListener('change', systemChanged)
    if (!listening) {
      window.addEventListener('storage', storageChanged)
      listening = true
    }
    applyTheme()
  }

  function setPreference(value: ThemePreference) {
    try { localStorage.setItem('theme', value) } catch { return false }
    preference.value = value
    applyTheme()
    return true
  }
  function toggle() { return setPreference(isDark.value ? 'light' : 'dark') }

  watch(isDark, applyTheme, { flush: 'sync' })
  onScopeDispose(() => {
    media?.removeEventListener('change', systemChanged)
    if (listening) window.removeEventListener('storage', storageChanged)
  })

  return { isDark, preference, init, setPreference, toggle }
})
