import { ref } from 'vue'

export interface ToastOptions {
  type: 'success' | 'error' | 'warning' | 'info'
  message: string
  duration?: number
}

interface ToastItem extends ToastOptions {
  id: number
}

const toasts = ref<ToastItem[]>([])
let toastId = 0

export function useToast() {
  function show(options: ToastOptions) {
    const id = ++toastId
    const duration = options.duration ?? 3000
    toasts.value.push({ ...options, id })
    
    if (duration > 0) {
      setTimeout(() => remove(id), duration)
    }
    return id
  }

  function success(message: string, duration?: number) {
    return show({ type: 'success', message, duration })
  }

  function error(message: string, duration?: number) {
    return show({ type: 'error', message, duration })
  }

  function warning(message: string, duration?: number) {
    return show({ type: 'warning', message, duration })
  }

  function info(message: string, duration?: number) {
    return show({ type: 'info', message, duration })
  }

  function remove(id: number) {
    const index = toasts.value.findIndex(t => t.id === id)
    if (index > -1) {
      toasts.value.splice(index, 1)
    }
  }

  function clear() {
    toasts.value = []
  }

  return {
    toasts,
    show,
    success,
    error,
    warning,
    info,
    remove,
    clear
  }
}

export const toast = useToast()
