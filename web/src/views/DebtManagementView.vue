<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChevronLeft, CreditCard, Layers, Bell, RefreshCw } from '@lucide/vue'
import FinancePage from '@/components/ui/FinancePage.vue'
import SelectionControl from '@/components/ui/SelectionControl.vue'
import DebtView from '@/views/DebtView.vue'
import ReminderView from '@/views/ReminderView.vue'

const debtView = ref<InstanceType<typeof DebtView> | null>(null)
const sections = [{ value: 'plans', label: '账户与分期', icon: Layers }, { value: 'reminders', label: '还款提醒', icon: Bell }]
const route = useRoute()
const router = useRouter()
const section = computed(() => route.query.view === 'reminders' && typeof route.query.operation_id !== 'string' ? 'reminders' : 'plans')

function switchSection(value: 'plans' | 'reminders') {
  const query = { ...route.query }
  delete query.operation_id
  if (value === 'reminders') query.view = 'reminders'
  else delete query.view
  void router.replace({ path: '/reminders', query })
}
</script>

<template>
  <FinancePage title="负债管理" subtitle="账户、分期与还款提醒" :icon="CreditCard">
    <template #actions><button class="finance-icon-button" aria-label="返回我的钱包" @click="router.push('/accounts')"><ChevronLeft :size="19" /></button><button v-if="section === 'plans'" class="finance-icon-button" aria-label="刷新分期数据" :disabled="debtView?.loading || debtView?.saving" @click="debtView?.refresh()"><RefreshCw :size="18" :class="{ 'animate-spin': debtView?.loading }" /></button></template>
    <SelectionControl :model-value="section" label="负债管理视图" :options="sections" solid @update:model-value="switchSection($event as 'plans' | 'reminders')" />
    <!-- Keep pending financial commands mounted while switching the visible section. -->
    <DebtView ref="debtView" v-show="section === 'plans'" embedded :active="section === 'plans'" />
    <ReminderView v-show="section === 'reminders'" embedded :active="section === 'reminders'" />
  </FinancePage>
</template>
