import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { authApi } from '@/api/auth'
import { clearSetupToken } from '@/utils/setupAccess'

export const useAuthStore = defineStore('auth', () => {
  const accessToken = ref<string | null>(null)
  const initialized = ref<boolean | null>(null)
  let sessionBootstrapAttempted = false
  const sessionGeneration = ref(0)

  const isLoggedIn = computed(() => !!accessToken.value)

  async function checkAuth() {
    const generation = sessionGeneration.value
    try {
      const status = await authApi.getStatus()
      if (generation !== sessionGeneration.value) return
      initialized.value = status.initialized
      if (!status.initialized) {
        clearSession()
      } else if (!accessToken.value && !sessionBootstrapAttempted) {
        sessionBootstrapAttempted = true
        await refresh(true)
      }
    } catch {
      if (generation !== sessionGeneration.value) return
      // 初始化只在后端明确返回 initialized=false 时触发。
      // 状态接口失败可能是后端未启动、网络异常或代理错误，不能误判为需要重新初始化。
      initialized.value = null
    }
  }

  async function login(password: string) {
    const generation = ++sessionGeneration.value
    accessToken.value = null
    sessionBootstrapAttempted = true
    const result = await authApi.login(password)
    if (generation !== sessionGeneration.value) throw new Error('登录操作已失效')
    accessToken.value = result.access_token
    sessionBootstrapAttempted = true
    initialized.value = true
    return result
  }

  async function init(password: string) {
    const generation = ++sessionGeneration.value
    accessToken.value = null
    sessionBootstrapAttempted = true
    const result = await authApi.init(password)
    if (generation !== sessionGeneration.value) throw new Error('初始化操作已失效')
    accessToken.value = result.access_token
    sessionBootstrapAttempted = true
    initialized.value = true
    clearSetupToken()
    return result
  }

  async function refresh(silent = false, onExpired?: () => void) {
    const generation = sessionGeneration.value
    try {
      const result = await authApi.refresh(silent)
      if (generation !== sessionGeneration.value) return false
      accessToken.value = result.access_token
      return true
    } catch {
      if (generation !== sessionGeneration.value) return false
      clearSession()
      onExpired?.()
      return false
    }
  }

  function clearSession() {
    sessionGeneration.value += 1
    sessionBootstrapAttempted = true
    accessToken.value = null
  }

  async function logout() {
    // Cookie authentication lets logout revoke even an expired access session.
    // The API queue drains pending login/refresh cookie writes before revocation.
    let revocation: Promise<void> = Promise.resolve()
    try {
      revocation = authApi.logout()
    } finally {
      clearSession()
    }
    await revocation
  }

  return {
    accessToken,
    sessionGeneration,
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
