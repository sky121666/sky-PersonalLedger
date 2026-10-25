<script setup lang="ts">
import { computed, ref } from 'vue'
import type { AccountDetailModel, HomeReadModels, ResourceState } from './readModels'
import type { WidgetInstance } from './model'
import type { Transaction } from '@/api/transaction'
import NetAssetsWidget from './widgets/NetAssetsWidget.vue'
import MonthlyFlowWidget from './widgets/MonthlyFlowWidget.vue'
import BudgetWidget from './widgets/BudgetWidget.vue'
import ReminderWidget from './widgets/ReminderWidget.vue'
import AccountsWidget from './widgets/AccountsWidget.vue'
import TransactionsWidget from './widgets/TransactionsWidget.vue'
import AccountWidget from './widgets/AccountWidget.vue'
import CalendarWidget from './widgets/CalendarWidget.vue'
import LendingWidget from './widgets/LendingWidget.vue'
import FamilyWidget from './widgets/FamilyWidget.vue'
import AIWidget from './widgets/AIWidget.vue'

const calendarWidget = ref<{ loadData: () => Promise<'success' | 'failed' | 'stale'> } | null>(null)
defineExpose({ loadData: () => calendarWidget.value?.loadData() ?? Promise.resolve<'success'>('success') })
const props = defineProps<{ instance: WidgetInstance; readModels: HomeReadModels; viewport: 'desktop' | 'mobile'; preview?: boolean; showAmounts?: boolean }>()
const emit = defineEmits<{ (e: 'navigate', kind: WidgetInstance['kind'], accountId?: string): void; (e: 'select-date', date: string): void; (e: 'select-transaction', transaction: Transaction): void }>()
const selectedAccount = computed<ResourceState<AccountDetailModel>>(() => {
  const state = props.readModels.accounts
  const id = props.instance.kind === 'account' ? props.instance.config.accountId : ''
  const account = state.data?.find(item => item.id === id)
  const records = props.readModels.accountTransactions[id]
  return { ...state, data: account ? { ...account, recentTransactions: records?.data ?? [], recordsPhase: records?.phase ?? 'idle' } : null, queryKey: `account:${id}`, phase: state.phase === 'ready' && !account ? 'error' : state.phase, error: state.phase === 'ready' && !account ? '账户不可用' : state.error }
})
const size = computed(() => props.instance.sizes[props.viewport])
function handleTransactionsNavigate() { emit('navigate', 'transactions') }
</script>

<template>
  <NetAssetsWidget v-if="instance.kind === 'netAssets'" :state="readModels.netAssets" :size="size" @navigate="emit('navigate', 'netAssets')" />
  <MonthlyFlowWidget v-else-if="instance.kind === 'monthlyFlow'" :state="readModels.overview" :size="size" @navigate="emit('navigate', 'monthlyFlow')" />
  <BudgetWidget v-else-if="instance.kind === 'budget'" :state="readModels.budget" :size="size" @navigate="emit('navigate', 'budget')" />
  <ReminderWidget v-else-if="instance.kind === 'reminders'" :state="readModels.reminders" :size="size" @navigate="emit('navigate', 'reminders')" />
  <TransactionsWidget v-else-if="instance.kind === 'transactions'" :state="readModels.transactions" :size="size" @navigate="handleTransactionsNavigate" @select="emit('select-transaction', $event)" />
  <AccountsWidget v-else-if="instance.kind === 'accounts'" :state="readModels.accounts" :size="size" @navigate="emit('navigate', 'accounts')" />
  <AccountWidget v-else-if="instance.kind === 'account'" :state="selectedAccount" :size="size" :account-id="instance.config.accountId" @navigate="emit('navigate', 'account', instance.config.accountId)" />
  <CalendarWidget ref="calendarWidget" v-else-if="instance.kind === 'calendar'" :size="size" :preview="preview" :hide-amounts="showAmounts === false" @select="emit('select-date', $event)" @navigate="emit('navigate', 'calendar')" />
  <LendingWidget v-else-if="instance.kind === 'lending'" :state="readModels.lending" :size="size" @navigate="emit('navigate', 'lending')" />
  <FamilyWidget v-else-if="instance.kind === 'family'" :state="readModels.family" :size="size" @navigate="emit('navigate', 'family')" />
  <AIWidget v-else-if="instance.kind === 'ai'" :state="readModels.ai" :size="size" :hide-amounts="showAmounts === false" @navigate="emit('navigate', 'ai')" />
</template>
