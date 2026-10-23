<script setup lang="ts">
import type { DebtPartInput } from '@/utils/debtAmounts'
import type { DebtPlan } from '@/api/debt'
import { formatDebtMoney } from '@/utils/debtAmounts'
defineProps<{ modelValue: DebtPartInput[]; plans: DebtPlan[]; cashInterest?: boolean; disabled?: boolean }>()
const emit = defineEmits<{ 'update:modelValue': [value: DebtPartInput[]] }>()
function update(rows: DebtPartInput[], index: number, field: 'principal' | 'booked_interest' | 'cash_interest', event: Event) {
  emit('update:modelValue', rows.map((row, i) => i === index ? { ...row, [field]: (event.target as HTMLInputElement).value } : row))
}
</script>

<template>
  <div class="space-y-3">
    <fieldset v-for="(row, index) in modelValue" :key="row.plan_id" :disabled="disabled"
      class="min-w-0 rounded-2xl border border-gray-200/60 bg-gray-50/70 p-3.5 dark:border-white/10 dark:bg-black/15">
      <legend class="max-w-full break-words px-1 text-sm font-semibold text-gray-800 dark:text-gray-100">{{ plans.find(plan => plan.id === row.plan_id)?.name || '分期计划' }}</legend>
      <p class="mb-3 text-xs leading-relaxed text-gray-500">
        待还本金 ¥{{ formatDebtMoney(plans.find(plan => plan.id === row.plan_id)?.principal_balance ?? 0) }}
        · 已入账利息 ¥{{ formatDebtMoney(plans.find(plan => plan.id === row.plan_id)?.interest_balance ?? 0) }}
      </p>
      <div class="grid min-w-0 gap-2" :class="cashInterest ? 'grid-cols-3' : 'grid-cols-2'">
        <label class="min-w-0 text-xs leading-relaxed text-gray-500">本金
          <input :value="row.principal" :aria-label="`${plans.find(plan => plan.id === row.plan_id)?.name} 本金`" inputmode="decimal" placeholder="0.00"
            class="mt-1 h-11 w-full min-w-0 rounded-xl bg-white px-2.5 font-nums text-sm text-gray-900 outline-hidden focus:ring-2 focus:ring-primary/30 disabled:opacity-60 dark:bg-white/5 dark:text-white"
            @input="update(modelValue, index, 'principal', $event)">
        </label>
        <label class="min-w-0 text-xs leading-relaxed text-gray-500">已入账利息
          <input :value="row.booked_interest" :aria-label="`${plans.find(plan => plan.id === row.plan_id)?.name} 已入账利息`" inputmode="decimal" placeholder="0.00"
            class="mt-1 h-11 w-full min-w-0 rounded-xl bg-white px-2.5 font-nums text-sm text-gray-900 outline-hidden focus:ring-2 focus:ring-primary/30 disabled:opacity-60 dark:bg-white/5 dark:text-white"
            @input="update(modelValue, index, 'booked_interest', $event)">
        </label>
        <label v-if="cashInterest" class="min-w-0 text-xs leading-relaxed text-gray-500">当次利息
          <input :value="row.cash_interest" :aria-label="`${plans.find(plan => plan.id === row.plan_id)?.name} 当次利息`" inputmode="decimal" placeholder="0.00"
            class="mt-1 h-11 w-full min-w-0 rounded-xl bg-white px-2.5 font-nums text-sm text-gray-900 outline-hidden focus:ring-2 focus:ring-primary/30 disabled:opacity-60 dark:bg-white/5 dark:text-white"
            @input="update(modelValue, index, 'cash_interest', $event)">
        </label>
      </div>
    </fieldset>
  </div>
</template>
