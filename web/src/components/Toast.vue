<script setup lang="ts">
import { CheckCircle, XCircle, AlertCircle, Info, X } from 'lucide-vue-next'
import { toast } from '@/composables/useToast'

const { toasts, remove } = toast

const iconMap = {
  success: CheckCircle,
  error: XCircle,
  warning: AlertCircle,
  info: Info
}

const colorMap = {
  success: 'bg-green-500',
  error: 'bg-red-500',
  warning: 'bg-yellow-500',
  info: 'bg-blue-500'
}
</script>

<template>
  <Teleport to="body">
    <div class="fixed top-4 left-1/2 -translate-x-1/2 z-[100] flex flex-col gap-2 pointer-events-none">
      <TransitionGroup name="toast">
        <div
          v-for="item in toasts"
          :key="item.id"
          class="pointer-events-auto flex items-center gap-3 px-4 py-3 bg-white rounded-xl shadow-lg border border-gray-100 min-w-[280px] max-w-[400px]"
        >
          <div :class="[colorMap[item.type], 'w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0']">
            <component :is="iconMap[item.type]" :size="18" class="text-white" />
          </div>
          <span class="flex-1 text-gray-700">{{ item.message }}</span>
          <button class="p-1 hover:bg-gray-100 rounded-lg flex-shrink-0" @click="remove(item.id)">
            <X :size="16" class="text-gray-400" />
          </button>
        </div>
      </TransitionGroup>
    </div>
  </Teleport>
</template>

<style scoped>
.toast-enter-active {
  animation: toast-in 0.3s ease-out;
}
.toast-leave-active {
  animation: toast-out 0.2s ease-in;
}
@keyframes toast-in {
  from {
    opacity: 0;
    transform: translateY(-20px) scale(0.95);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}
@keyframes toast-out {
  from {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
  to {
    opacity: 0;
    transform: translateY(-10px) scale(0.95);
  }
}
</style>
