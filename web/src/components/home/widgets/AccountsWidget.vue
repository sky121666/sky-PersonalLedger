<script setup lang="ts">
import WidgetFrame from '../WidgetFrame.vue'
import type { AccountSummaryModel, ResourceState } from '../readModels'
defineProps<{ state: ResourceState<AccountSummaryModel[]>; size: 'small'|'medium'|'large' }>()
const emit = defineEmits<{ (e: 'navigate'): void }>()
function scrollAccounts(event: KeyboardEvent) {
  if (event.target !== event.currentTarget || event.altKey || event.ctrlKey || event.metaKey) return
  const strip = event.currentTarget as HTMLElement
  const targets: Record<string, number> = {
    ArrowLeft: strip.scrollLeft - 140, ArrowRight: strip.scrollLeft + 140,
    Home: 0, End: strip.scrollWidth - strip.clientWidth,
  }
  const left = targets[event.key]
  if (left === undefined) return
  event.preventDefault()
  strip.scrollTo({ left, behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' })
}
</script>
<template>
  <WidgetFrame title="我的账户" :size="size" class="home-widget-accounts" interactive @activate="emit('navigate')">
    <p v-if="state.phase === 'error'" class="widget-error">{{ state.error }}</p>
    <div v-else-if="state.data?.length" class="account-tiles" tabindex="0" role="region" aria-label="账户概览" @keydown="scrollAccounts">
      <div v-for="account in state.data.filter(item => !item.archived).slice(0, 6)" :key="account.id" class="account-tile">
        <span class="account-type">{{ account.typeName }}</span>
        <span class="account-name" :title="account.name">{{ account.name }}</span>
        <strong :class="account.balance >= 0 ? 'amount-income' : 'amount-expense'">{{ account.displayBalance }}</strong>
      </div>
    </div>
    <p v-else class="widget-muted">暂无账户</p>
  </WidgetFrame>
</template>
