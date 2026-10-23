<script setup lang="ts">
import WidgetFrame from '../WidgetFrame.vue'
import type { AccountDetailModel, ResourceState } from '../readModels'
defineProps<{ state: ResourceState<AccountDetailModel>; size: 'small'|'medium'|'large'; accountId: string }>()
const emit = defineEmits<{ (e: 'navigate'): void }>()
</script>
<template>
  <WidgetFrame title="指定账户" :size="size" class="home-widget-account" :class="{ 'home-widget-empty': !state.data }" interactive @activate="emit('navigate')">
    <p v-if="state.phase === 'error'" class="widget-error">{{ state.error }}</p>
    <template v-else-if="state.data">
      <p class="widget-hero">{{ state.data.displayBalance }}</p>
      <p class="widget-meta">{{ state.data.typeName }} · {{ state.data.name }}</p>
      <template v-if="size === 'medium'">
        <p v-if="state.data.recordsPhase === 'error'" class="widget-error">账户记录加载失败，请刷新重试</p>
        <div v-else-if="state.data.recentTransactions.length" class="transaction-list">
          <div v-for="(record, index) in state.data.recentTransactions" :key="index" class="widget-split">
            <span>{{ record.title }}</span><strong :class="`amount-${record.tone}`">{{ record.displayAmount }}</strong>
          </div>
        </div>
        <p v-else class="widget-muted">{{ state.data.recordsPhase === 'ready' ? '暂无近期记录' : '正在加载近期记录' }}</p>
      </template>
    </template>
    <p v-else class="widget-muted">账户 {{ accountId }} 尚未加载</p>
  </WidgetFrame>
</template>
