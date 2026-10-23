<script setup lang="ts">
import { computed } from 'vue'
import { Target } from '@lucide/vue'
import WidgetFrame from '../WidgetFrame.vue'
import type { ResourceState, BudgetModel } from '../readModels'
const props = defineProps<{ state: ResourceState<BudgetModel>; size: 'small'|'medium'|'large' }>()
const emit = defineEmits<{ (e: 'navigate'): void }>()
const progress = computed(() => props.state.data ? `${props.state.data.visualPercentage}%` : '0%')
</script>
<template>
  <WidgetFrame title="本月预算" :size="size" tone="blue" class="home-widget-budget" :class="{ 'home-widget-empty': !state.data || state.data.amount <= 0 }" interactive @activate="emit('navigate')">
    <template #icon><Target :size="18" aria-hidden="true" /></template>
    <template #badge><span v-if="state.data && state.data.amount > 0" class="widget-badge">{{ state.data.percentage }}%</span></template>
    <p v-if="state.phase === 'error'" class="widget-error">{{ state.error }}</p>
    <template v-else-if="state.data">
      <p v-if="state.data.amount <= 0" class="widget-muted">尚未设置总预算</p>
      <div v-if="state.data.amount > 0" class="widget-split"><span>已用 {{ state.data.displaySpent }}</span><span>剩余 {{ state.data.displayRemaining }}</span></div>
      <div v-if="state.data.amount > 0" class="widget-progress budget-progress" role="progressbar" :aria-valuenow="state.data.visualPercentage" aria-valuemin="0" aria-valuemax="100">
        <span :style="{ width: progress }" :class="{ 'is-near': state.data.percentage >= 80, 'is-over': state.data.percentage >= 100 }"></span>
      </div>
      <p v-if="state.data.alertName" class="widget-warning">{{ state.data.alertName }}{{ state.data.alertOver ? '超支' : '接近上限' }}</p>
      <template v-if="size === 'large'">
        <p v-if="state.data.detailsPhase === 'error'" class="widget-error">分类预算加载失败，请刷新重试</p>
        <div v-else-if="state.data.categories.length" class="account-list">
          <div v-for="category in state.data.categories" :key="category.id" class="widget-split">
            <span>{{ category.name }}</span><span>{{ category.displaySpent }} / {{ category.displayAmount }}</span>
          </div>
        </div>
        <p v-else class="widget-muted">{{ state.data.detailsPhase === 'ready' ? '暂无分类预算' : '正在加载分类预算' }}</p>
      </template>
    </template>
    <p v-else class="widget-muted">正在加载预算</p>
  </WidgetFrame>
</template>
