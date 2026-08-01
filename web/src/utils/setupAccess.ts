import type { AxiosRequestConfig } from 'axios'

const SETUP_TOKEN_STORAGE_KEY = 'ledger_setup_token'
let memorySetupToken = ''

export function setSetupToken(value: unknown): string {
  const token = typeof value === 'string' ? value.trim() : ''
  memorySetupToken = token
  try {
    if (token) {
      window.sessionStorage.setItem(SETUP_TOKEN_STORAGE_KEY, token)
    } else {
      window.sessionStorage.removeItem(SETUP_TOKEN_STORAGE_KEY)
    }
  } catch {
    // In-memory storage still keeps the current setup flow working when
    // sessionStorage is unavailable (for example, strict privacy mode).
  }
  return token
}

export function getSetupToken(): string {
  if (memorySetupToken) return memorySetupToken
  try {
    memorySetupToken = window.sessionStorage.getItem(SETUP_TOKEN_STORAGE_KEY)?.trim() || ''
  } catch {
    memorySetupToken = ''
  }
  return memorySetupToken
}

export function clearSetupToken(): void {
  setSetupToken('')
}

export function setupAccessConfig(): AxiosRequestConfig {
  const token = getSetupToken()
  return token
    ? { headers: { 'X-Setup-Token': token } }
    : {}
}
