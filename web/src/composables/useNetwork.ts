import { ref, onMounted, onUnmounted } from 'vue'
import { toast } from './useToast'

const isOnline = ref(navigator.onLine)

export function useNetwork() {
  function handleOnline() {
    isOnline.value = true
    toast.success('网络已恢复')
  }

  function handleOffline() {
    isOnline.value = false
    toast.error('网络连接已断开')
  }

  onMounted(() => {
    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)
  })

  onUnmounted(() => {
    window.removeEventListener('online', handleOnline)
    window.removeEventListener('offline', handleOffline)
  })

  return { isOnline }
}
