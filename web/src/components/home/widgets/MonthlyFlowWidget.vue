<script setup lang="ts">
import WidgetFrame from '../WidgetFrame.vue'
import type { ResourceState, MonthlyFlowModel } from '../readModels'
defineProps<{ state: ResourceState<MonthlyFlowModel>; size: 'small'|'medium'|'large' }>()
const emit = defineEmits<{ (e: 'navigate'): void }>()
</script>
<template>
  <WidgetFrame title="本月收支" :size="size" class="home-widget-flow" interactive @activate="emit('navigate')">
    <p v-if="state.phase === 'error'" class="widget-error">{{ state.error }}</p>
    <div v-else-if="state.data" class="flow-grid">
      <div><span><i class="flow-dot amount-income" aria-hidden="true" />收入</span><strong class="amount-income">+{{ state.data.displayIncome }}</strong></div>
      <div><span><i class="flow-dot amount-expense" aria-hidden="true" />支出</span><strong class="amount-expense">-{{ state.data.displayExpense }}</strong></div>
      <div><span><i class="flow-dot" aria-hidden="true" />结余</span><strong>{{ state.data.displayBalance }}</strong></div>
    </div>
    <p v-else class="widget-muted">尚未加载</p>
  </WidgetFrame>
</template>
