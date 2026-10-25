<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, useId, watch } from 'vue'
import { Check, ChevronDown, Search, Wallet } from '@lucide/vue'
import type { Account, AccountType } from '@/api/account'
import { getAccountTypeName } from '@/utils/constants'
import { formatMoney } from './readModels'

const props = withDefaults(defineProps<{
  modelValue: string
  accounts: Account[]
  disabled?: boolean
  showAmounts?: boolean
}>(), { showAmounts: true })
const emit = defineEmits<{ 'update:modelValue': [id: string]; 'tab-forward': [] }>()
const id = useId()
const root = ref<HTMLElement | null>(null)
const trigger = ref<HTMLButtonElement | null>(null)
const searchInput = ref<HTMLInputElement | null>(null)
const open = ref(false)
const search = ref('')
const activeIndex = ref(-1)
const available = computed(() => props.accounts.filter(account => !account.is_archived))
const selected = computed(() => available.value.find(account => account.id === props.modelValue))
const groupDefinitions: { name: string; types: AccountType[] }[] = [
  { name: '现金与支付', types: ['cash', 'alipay', 'wechat', 'prepaid', 'qq_pay', 'jd_pay', 'apple_pay'] },
  { name: '银行卡与储蓄', types: ['bank_card', 'savings'] },
  { name: '投资', types: ['investment', 'fund', 'stock', 'crypto'] },
  { name: '信用与贷款', types: ['credit', 'loan', 'mortgage', 'car_loan', 'consumer_loan', 'huabei', 'baitiao', 'payable'] },
  { name: '其他', types: ['receivable', 'other'] },
]
const groups = computed(() => {
  const query = search.value.trim().toLocaleLowerCase()
  let index = 0
  return groupDefinitions.map(group => ({
    name: group.name,
    options: available.value.filter(account => {
      const belongs = group.types.includes(account.type)
        || (group.name === '其他' && !groupDefinitions.some(item => item.types.includes(account.type)))
      return belongs && `${account.name} ${getAccountTypeName(account.type)} ${group.name}`.toLocaleLowerCase().includes(query)
    }).map(account => ({ account, index: index++ })),
  })).filter(group => group.options.length)
})
const options = computed(() => groups.value.flatMap(group => group.options))
const activeId = computed(() => activeIndex.value >= 0 && activeIndex.value < options.value.length
  ? `${id}-option-${activeIndex.value}` : undefined)

function close(restoreFocus = false) {
  open.value = false
  if (restoreFocus) trigger.value?.focus({ preventScroll: true })
}
async function toggle() {
  if (open.value) return close()
  search.value = ''
  activeIndex.value = -1
  open.value = true
  await nextTick()
  searchInput.value?.focus()
}
function choose(accountId: string) {
  emit('update:modelValue', accountId)
  close(true)
}
function move(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    event.preventDefault()
    event.stopPropagation()
    close(true)
    return
  }
  if (event.key === 'Tab') {
    event.preventDefault()
    if (event.shiftKey) {
      close(true)
    } else {
      close()
      emit('tab-forward')
    }
    return
  }
  const count = options.value.length
  if (event.key === 'Enter') {
    event.preventDefault()
    const option = options.value[activeIndex.value]
    if (option) choose(option.account.id)
    return
  }
  if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return
  event.preventDefault()
  if (!count) return
  if (event.key === 'Home') activeIndex.value = 0
  else if (event.key === 'End') activeIndex.value = count - 1
  else if (event.key === 'ArrowDown') activeIndex.value = (activeIndex.value + 1) % count
  else activeIndex.value = activeIndex.value <= 0 ? count - 1 : activeIndex.value - 1
  void nextTick(() => {
    if (activeId.value) document.getElementById(activeId.value)?.scrollIntoView({ block: 'nearest' })
  })
}
function outside(event: MouseEvent) {
  if (open.value && event.target instanceof Node && !root.value?.contains(event.target)) close()
}
watch(search, () => { activeIndex.value = -1 })
watch(() => props.disabled, disabled => { if (disabled) close() })
watch(options, () => { activeIndex.value = -1 })
// Closing on pointerdown would recenter the dialog before the click completes.
onMounted(() => document.addEventListener('click', outside))
onBeforeUnmount(() => document.removeEventListener('click', outside))
</script>

<template>
  <div ref="root" class="account-picker">
    <span :id="`${id}-label`" class="picker-label">关联账户</span>
    <button ref="trigger" type="button" class="picker-trigger" aria-label="组件关联账户"
      aria-haspopup="listbox" :aria-expanded="open" :aria-controls="open ? `${id}-options` : undefined"
      :disabled="disabled" @click="toggle">
      <Wallet :size="18" aria-hidden="true" />
      <span class="picker-selection"><strong>{{ selected?.name ?? (modelValue ? '账户不可用，请重新选择' : '请选择账户') }}</strong><small v-if="selected">{{ getAccountTypeName(selected.type) }}</small></span>
      <ChevronDown :size="16" aria-hidden="true" />
    </button>
    <div v-if="open" class="picker-panel">
      <label class="picker-search"><Search :size="16" aria-hidden="true" />
        <input ref="searchInput" v-model="search" role="combobox" aria-label="搜索账户" aria-autocomplete="list"
          aria-expanded="true" :aria-controls="`${id}-options`" :aria-activedescendant="activeId"
          placeholder="搜索名称或账户类型" autocomplete="off" @keydown="move" />
      </label>
      <div :id="`${id}-options`" role="listbox" aria-label="可选账户" class="picker-options">
        <div v-for="group in groups" :key="group.name" role="group" :aria-label="group.name">
          <p class="picker-group" aria-hidden="true">{{ group.name }}</p>
          <button v-for="option in group.options" :id="`${id}-option-${option.index}`" :key="option.account.id"
            type="button" role="option" tabindex="-1" :value="option.account.id" :aria-selected="modelValue === option.account.id"
            class="picker-option" :class="{ 'is-active': activeIndex === option.index }"
            @pointerdown.prevent @click="choose(option.account.id)">
            <span class="picker-option-name"><strong>{{ option.account.name }}</strong><small>{{ getAccountTypeName(option.account.type) }}</small></span>
            <span class="picker-balance">{{ showAmounts ? formatMoney(option.account.current_balance) : '****' }}</span>
            <Check v-if="modelValue === option.account.id" :size="16" aria-hidden="true" /><span v-else class="picker-check" aria-hidden="true" />
          </button>
        </div>
      </div>
      <p v-if="!options.length" role="status" class="picker-empty">{{ available.length ? '没有匹配的账户' : '暂无可选账户' }}</p>
    </div>
  </div>
</template>

<style scoped>
.account-picker{width:100%;font-size:12px;min-width:0}
.picker-label{display:block;margin-bottom:6px}
.picker-trigger{display:flex;align-items:center;gap:10px;min-height:52px;width:100%;padding:10px 12px;border:1px solid #76768024;border-radius:14px;background:#7676800c;text-align:left;color:inherit;cursor:pointer}
.picker-trigger>svg{flex:none;color:#007aff}.picker-trigger>svg:last-child{color:#8e8e93}
.picker-trigger:disabled{opacity:.5;cursor:default}.picker-selection{display:flex;flex:1;min-width:0;align-items:baseline;gap:8px}.picker-selection strong{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:550}.picker-selection small{color:#63636b;font-size:11px;flex:none}
.picker-panel{margin-top:8px;border:1px solid #76768024;border-radius:16px;background:#fff;overflow:hidden;box-shadow:0 8px 24px #1020400c}
.picker-search{display:flex;align-items:center;gap:8px;margin:8px;border-radius:10px;padding:0 10px;background:#76768010;color:#63636b}
.picker-search input{width:100%;min-width:0;min-height:44px;padding:8px 0;background:transparent;border:0;color:inherit;font:inherit;outline-offset:2px}
.picker-options{max-height:min(280px,32dvh);overflow:auto;overscroll-behavior:contain;scrollbar-width:thin;padding:0 6px 6px}
.picker-group{padding:10px 10px 4px;color:#63636b;font-size:11px;font-weight:600}
.picker-option{display:flex;align-items:center;gap:10px;width:100%;min-height:56px;padding:8px 10px;border:0;border-radius:10px;background:transparent;color:inherit;text-align:left;cursor:pointer}
.picker-option:hover,.picker-option.is-active,.picker-option[aria-selected=true]{background:#007aff12}
.picker-option-name{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
.picker-option strong{font-size:13px;font-weight:550;overflow-wrap:anywhere}.picker-option small{font-size:11px;color:#63636b}
.picker-balance{font-size:12px;font-variant-numeric:tabular-nums;flex:none}.picker-option>svg{color:#007aff;flex:none}.picker-check{width:16px;flex:none}
.picker-empty{padding:16px;text-align:center;color:#63636b}.picker-trigger:focus-visible,.picker-option:focus-visible,.picker-search input:focus-visible{outline:3px solid #007aff;outline-offset:-3px}
.dark .picker-panel{background:#252528;border-color:#76768040}.dark .picker-trigger{border-color:#76768040;background:#76768018}
.dark .picker-selection small,.dark .picker-search,.dark .picker-group,.dark .picker-option small,.dark .picker-empty{color:#a1a1aa}
@media(max-width:380px){.picker-selection{align-items:flex-start;flex-direction:column;gap:2px}.picker-balance{font-size:11px}.picker-option{gap:6px;padding-inline:6px}}
</style>
