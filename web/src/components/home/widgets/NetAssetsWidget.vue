<script setup lang="ts">
import { Wallet } from '@lucide/vue'
import WidgetFrame from '../WidgetFrame.vue'
import type { ResourceState, NetAssetsModel } from '../readModels'
defineProps<{ state: ResourceState<NetAssetsModel>; size: 'small'|'medium'|'large' }>()
const emit = defineEmits<{ (e: 'navigate'): void }>()
</script>
<template>
  <WidgetFrame title="净资产" :size="size" tone="assets" interactive @activate="emit('navigate')">
    <template #badge><span class="asset-wallet" aria-hidden="true"><Wallet :size="24" /></span></template>
    <p v-if="state.phase === 'error'" class="widget-error">{{ state.error }}</p>
    <p v-else-if="state.data" class="widget-hero">{{ state.data.displayNetAssets }}</p>
    <p v-else class="widget-muted">尚未加载</p>
    <div v-if="state.data" class="asset-totals">
      <div><span>总资产</span><strong>{{ state.data.displayAssets }}</strong></div>
      <div><span>总负债</span><strong class="asset-liabilities">{{ state.data.displayLiabilities }}</strong></div>
    </div>
  </WidgetFrame>
</template>
