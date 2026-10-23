<script setup lang="ts">
import { ref } from 'vue'
import WidgetFrame from '../WidgetFrame.vue'
import CalendarView from '@/components/CalendarView.vue'
const calendar = ref<{ loadData: () => Promise<'success' | 'failed' | 'stale'> } | null>(null)
defineExpose({ loadData: () => calendar.value?.loadData() ?? Promise.resolve<'success'>('success') })
defineProps<{ size: 'small'|'medium'|'large'; preview?: boolean; hideAmounts?: boolean }>()
const emit = defineEmits<{ (e: 'navigate'): void; (e: 'select', date: string): void }>()
</script>
<template>
  <WidgetFrame title="收支日历" :size="size" interactive @activate="emit('navigate')">
    <CalendarView ref="calendar" :preview="preview" :hide-amounts="hideAmounts" @select="emit('select', $event)" />
  </WidgetFrame>
</template>
