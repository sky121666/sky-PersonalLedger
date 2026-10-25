<script setup lang="ts">
import { computed } from 'vue'
import { ArrowLeftRight } from '@lucide/vue'
import WidgetFrame from '../WidgetFrame.vue'
import type { HomeReadModels } from '../readModels'
const props = defineProps<{ state: HomeReadModels['lending']; size: 'small'|'medium'|'large' }>()
const empty = computed(() => props.state.data?.receivable === 0 && props.state.data.payable === 0 && props.state.data.active === 0)
const emit = defineEmits<{ (e: 'navigate'): void }>()
</script>
<template>
  <WidgetFrame title="借贷往来" :size="size" tone="amber" class="home-widget-lending" :class="{ 'home-widget-empty': !state.data || empty }" interactive @activate="emit('navigate')">
    <template #icon><ArrowLeftRight :size="18" aria-hidden="true" /></template>
    <p v-if="state.phase === 'error'" class="widget-error">{{ state.error }}</p>
    <p v-else-if="empty" class="widget-muted">暂无未结清借贷</p>
    <div v-else-if="state.data" class="lending-panels">
      <div><span>{{ size === 'small' ? '应收' : '应收（别人欠我）' }}</span><strong>{{ state.data.displayReceivable }}</strong></div>
      <div><span>{{ size === 'small' ? '应付' : '应付（我欠别人）' }}</span><strong>{{ state.data.displayPayable }}</strong></div>
    </div>
    <p v-else class="widget-muted">{{ state.phase === 'ready' ? '暂无借贷数据' : '正在加载借贷' }}</p>
  </WidgetFrame>
</template>
