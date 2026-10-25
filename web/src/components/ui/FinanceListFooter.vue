<script setup lang="ts">
import { LoaderCircle } from '@lucide/vue'

withDefaults(defineProps<{
  count: number
  hasMore: boolean
  loading?: boolean
  error?: string
  label?: string
  moreLabel?: string
  retryLabel?: string
}>(), {
  label: '列表加载',
  moreLabel: '加载更多',
  retryLabel: '重试加载更多',
})
defineEmits<{ more: [] }>()
</script>

<template>
  <footer class="finance-list-footer" :aria-label="label" :aria-busy="loading || undefined">
    <p role="status" class="finance-list-status">
      <LoaderCircle v-if="loading" :size="15" class="finance-list-spinner" aria-hidden="true" />
      <span>{{ loading ? '正在加载… · ' : '' }}已加载 {{ count }} 条记录</span>
    </p>
    <p v-if="error" role="alert" class="finance-list-error">{{ error }}</p>
    <button v-if="hasMore || error" type="button" class="finance-button is-subtle" :disabled="loading"
      @click="$emit('more')">{{ error ? retryLabel : moreLabel }}</button>
  </footer>
</template>
