import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { authApi } from '@/api/auth'

export const useAuthStore = defineStore('auth', () => {
  const accessToken = ref<string | null>(null)
  const refreshToken = ref<string | null>(null)
  const initialized = ref<boolean | null>(null)

  const isLoggedIn = computed(() => !!accessToken.value)

  async function checkAuth() {
    try {
      const status = await authApi.getStatus()
      initialized.value = status.initialized
      if (!status.initialized) {
        logout()
      }
    } catch {
      initialized.value = false
    }
  }

  async function login(password: string) {
    const result = await authApi.login(password)
    accessToken.value = result.access_token
    refreshToken.value = result.refresh_token
    initialized.value = true
    return result
  }

  async function init(password: string) {
    const result = await authApi.init(password)
    accessToken.value = result.access_token
    refreshToken.value = result.refresh_token
    initialized.value = true
    return result
  }

  async function refresh() {
    if (!refreshToken.value) return false
    try {
      const result = await authApi.refresh(refreshToken.value)
      accessToken.value = result.access_token
      refreshToken.value = result.refresh_token
      return true
    } catch {
      logout()
      return false
    }
  }

  function logout() {
    accessToken.value = null
    refreshToken.value = null
  }

  return {
    accessToken,
    refreshToken,
    initialized,
    isLoggedIn,
    checkAuth,
    login,
    init,
    refresh,
    logout
  }
}, {
  persist: {
    paths: ['accessToken', 'refreshToken']
  }
})
