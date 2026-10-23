<script setup lang="ts">
import { Sparkles } from '@lucide/vue'
import { computed } from 'vue'
import WidgetFrame from '../WidgetFrame.vue'
import type { HomeReadModels } from '../readModels'
const props = defineProps<{ state: HomeReadModels['ai']; size: 'small'|'medium'|'large'; hideAmounts?: boolean }>()
const badge = computed(() => {
  if (props.state.phase === 'error') return ''
  if (!props.state.data) return props.state.phase === 'ready' ? '查看分析' : ''
  return ({ completed: '已生成', running: '生成中', pending: '等待中', failed: '生成失败' } as Record<string, string>)[props.state.data.status] ?? '状态未知'
})
const emit = defineEmits<{ (e: 'navigate'): void }>()
</script>
<template>
  <WidgetFrame title="AI 分析" :size="size" tone="cyan" class="home-widget-ai" :class="{ 'home-widget-empty': !state.data }" interactive @activate="emit('navigate')">
    <template #icon><Sparkles :size="18" aria-hidden="true" /></template>
    <template v-if="badge" #badge><span class="widget-badge">{{ badge }}</span></template>
    <p v-if="state.phase === 'error'" class="widget-error">{{ state.error }}</p>
    <template v-else-if="state.data"><p class="widget-meta">{{ state.data.period }}</p><p class="widget-copy" :class="{ 'ai-summary-compact': size === 'small' }">{{ hideAmounts ? '摘要已隐藏' : state.data.summary }}</p></template>
    <p v-else class="widget-muted">{{ state.phase === 'ready' ? '还没有报告' : '正在加载报告' }}</p>
  </WidgetFrame>
</template>
<style scoped>
.ai-summary-compact{display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:3;overflow:hidden}
</style>
