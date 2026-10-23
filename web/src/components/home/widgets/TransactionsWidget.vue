<script setup lang="ts">
import dayjs from 'dayjs'
import WidgetFrame from '../WidgetFrame.vue'
import DynamicIcon from '@/components/DynamicIcon.vue'
import type { HomeReadModels } from '../readModels'
import type { Transaction } from '@/api/transaction'
import { isManagedTransaction } from '@/utils/managedTransaction'
defineProps<{ state: HomeReadModels['transactions']; size: 'small'|'medium'|'large' }>()
const emit = defineEmits<{ (e: 'navigate'): void; (e: 'select', transaction: Transaction): void }>()
</script>
<template>
  <WidgetFrame title="最近交易" :size="size" class="home-widget-transactions" interactive @activate="emit('navigate')">
    <p v-if="state.phase === 'error'" class="widget-error">{{ state.error }}</p>
    <div v-else-if="state.data?.length" class="transaction-list">
      <button v-for="item in state.data.slice(0, size === 'large' ? 5 : 3)" :key="item.transaction.id" type="button" class="transaction-row" :aria-label="`查看交易 ${item.transaction.remark || item.presentation.title}`" @click="($event.currentTarget as HTMLElement).focus({ preventScroll: true }); isManagedTransaction(item.transaction) ? emit('navigate') : emit('select', item.transaction)">
        <span class="transaction-icon" :style="{ backgroundColor: (item.transaction.type === 'transfer' ? '#6366F1' : item.transaction.category?.color || '#007AFF') + '15' }"><DynamicIcon :icon="item.presentation.icon" :size="22" /></span>
        <span class="transaction-name"><span>{{ item.presentation.title }}</span><small class="widget-transaction-note">{{ dayjs(item.transaction.transaction_date).format('MM-DD HH:mm') }}<template v-if="item.transaction.remark"> · <span>{{ item.transaction.remark }}</span></template></small></span>
        <strong :class="`amount-${item.presentation.tone}`">{{ item.displayAmount }}</strong>
      </button>
    </div>
    <p v-else class="widget-muted">暂无交易记录</p>
  </WidgetFrame>
</template>
