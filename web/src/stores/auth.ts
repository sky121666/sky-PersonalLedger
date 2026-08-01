import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { authApi } from '@/api/auth'
import { clearSetupToken } from '@/utils/setupAccess'

export const useAuthStore = defineStore('auth', () => {
  const accessToken = ref<string | null>(null)
  const initialized = ref<boolean | null>(null)
  let sessionBootstrapAttempted = false

  const isLoggedIn = computed(() => !!accessToken.value)

  async function checkAuth() {
    try {
      const status = await authApi.getStatus()
      initialized.value = status.initialized
      if (!status.initialized) {
        clearSession()
      } else if (!accessToken.value && !sessionBootstrapAttempted) {
        sessionBootstrapAttempted = true
        await refresh(true)
      }
    } catch {
      // 初始化只在后端明确返回 initialized=false 时触发。
      // 状态接口失败可能是后端未启动、网络异常或代理错误，不能误判为需要重新初始化。
      initialized.value = null
    }
  }

  async function login(password: string) {
    const result = await authApi.login(password)
    accessToken.value = result.access_token
    sessionBootstrapAttempted = true
    initialized.value = true
    return result
  }

  async function init(password: string) {
    const result = await authApi.init(password)
    accessToken.value = result.access_token
    sessionBootstrapAttempted = true
    initialized.value = true
    clearSetupToken()
    return result
  }

  async function refresh(silent = false) {
    try {
      const result = await authApi.refresh(silent)
      accessToken.value = result.access_token
      return true
    } catch {
      clearSession()
      return false
    }
  }

  function clearSession() {
    accessToken.value = null
  }

  async function logout() {
    const hasSession = Boolean(accessToken.value)
    try {
      if (hasSession) {
        await authApi.logout()
      }
    } finally {
      clearSession()
    }
  }

  return {
    accessToken,
    initialized,
    isLoggedIn,
    checkAuth,
    login,
    init,
    refresh,
    clearSession,
    logout
  }
})
