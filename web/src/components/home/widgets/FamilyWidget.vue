<script setup lang="ts">
import { Users } from '@lucide/vue'
import { computed } from 'vue'
import WidgetFrame from '../WidgetFrame.vue'
import type { HomeReadModels } from '../readModels'
const props = defineProps<{ state: HomeReadModels['family']; size: 'small'|'medium'|'large' }>()
const empty = computed(() => props.state.data?.totalExpense === 0 && props.state.data.members === 0)
const emit = defineEmits<{ (e: 'navigate'): void }>()
</script>
<template>
  <WidgetFrame title="家庭支出" :size="size" tone="green" class="home-widget-family" :class="{ 'home-widget-empty': !state.data || empty }" interactive @activate="emit('navigate')">
    <template #icon><Users :size="18" aria-hidden="true" /></template>
    <template v-if="state.data && state.data.members > 0" #badge><span class="widget-badge">{{ state.data.members }}人有支出</span></template>
    <p v-if="state.phase === 'error'" class="widget-error">{{ state.error }}</p>
    <p v-else-if="empty" class="widget-muted">本月暂无支出</p>
    <template v-else-if="state.data"><p class="widget-hero">{{ state.data.displayTotal }}</p><p class="widget-meta">{{ state.data.members ? '本月总支出 · 含未归属' : '本月支出 · 尚未归属成员' }}</p></template>
    <p v-else class="widget-muted">{{ state.phase === 'ready' ? '暂无家庭数据' : '正在加载家庭支出' }}</p>
  </WidgetFrame>
</template>
