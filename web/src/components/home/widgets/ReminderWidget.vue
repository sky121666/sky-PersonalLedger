<script setup lang="ts">
import { Bell } from '@lucide/vue'
import WidgetFrame from '../WidgetFrame.vue'
import type { ResourceState, ReminderModel } from '../readModels'
defineProps<{ state: ResourceState<ReminderModel>; size: 'small'|'medium'|'large' }>()
const emit = defineEmits<{ (e: 'navigate'): void }>()
</script>
<template>
  <WidgetFrame title="还款提醒" :size="size" tone="violet" class="home-widget-reminders" :class="{ 'home-widget-empty': !state.data }" interactive @activate="emit('navigate')">
    <template #icon><Bell :size="18" aria-hidden="true" /></template>
    <template #badge><span v-if="state.data" class="widget-badge">{{ state.data.progress.toFixed(1) }}%</span></template>
    <p v-if="state.phase === 'error'" class="widget-error">{{ state.error }}</p>
    <template v-else-if="state.data">
      <div class="widget-split"><span>已还 {{ state.data.displayPaid }}</span><span>待还 {{ state.data.displayDebt }}</span></div>
      <div class="widget-progress"><span :style="{ width: Math.min(100, Math.max(0, state.data.progress)) + '%' }"></span></div>
      <template v-if="size === 'small'">
        <p class="widget-meta">{{ state.data.daysUntil === 0 ? '今日还款' : state.data.daysUntil + '天后还款' }} · {{ state.data.nextName }} · 每月{{ state.data.scheduledDay }}日</p>
      </template>
      <template v-else>
        <p class="widget-meta"><span class="widget-pill">{{ state.data.daysUntil === 0 ? '今日还款' : state.data.daysUntil + '天后还款' }}</span></p>
        <p class="widget-meta">{{ state.data.nextName }} · 每月{{ state.data.scheduledDay }}日</p>
      </template>
      <p class="widget-scope">还款提醒，不含账户分期</p>
    </template>
    <p v-else class="widget-muted">{{ state.phase === 'idle' ? '正在加载还款提醒' : '暂无还款提醒' }}</p>
  </WidgetFrame>
</template>
