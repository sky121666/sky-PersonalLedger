<script setup lang="ts">
import FinancePage from '@/components/ui/FinancePage.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue'
import { accountApi, isDebtAccount, type Account, type CreateAccountParams, type AccountType } from '@/api/account'
import { Plus, ChevronDown, Trash2, Archive, Wallet, CreditCard, ArchiveRestore, Pen, ScrollText } from '@lucide/vue'
import { useRouter } from 'vue-router'
import { accountSummaryTotals } from '@/utils/accountSummary'

const router = useRouter()
import { toast } from '@/composables/useToast'
import DynamicIcon from '@/components/DynamicIcon.vue'
import Hover3D from '@/components/Hover3D.vue'
import { notifyLedgerMutation, useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { createRequestGeneration } from '@/utils/requestGeneration'
import { createFormSubmission } from '@/utils/formSubmission'
import { debtApi } from '@/api/debt'
import { debtCents } from '@/utils/debtAmounts'

const supportsManagedDebt = ref(false)
const debtCapabilityError = ref('')

const accounts = ref<Account[]>([])
const archivedAccounts = ref<Account[]>([])
const totalAssets = ref(0)
const totalLiabilities = ref(0)
const showArchived = ref(false)
const ledgerMutationRevision = useLedgerMutationRevision()
const accountRequests = createRequestGeneration()
const loading = ref(false)
const loadError = ref('')
const hasLoaded = ref(false)

const showDialog = ref(false)
const editingAccount = ref<Account | null>(null)
const formSubmission = createFormSubmission()
const saving = formSubmission.saving
const showDeleteModal = ref(false)
const deletingId = ref<string | null>(null)
const dialogTrigger = ref<HTMLElement | null>(null)
const deleteTrigger = ref<HTMLElement | null>(null)
const pageHeading = ref<HTMLElement | null>(null)

const form = ref({
  name: '',
  type: 'cash',
  icon: '',
  color: '#3B82F6',
  initial_balance: '0',
  debt_tracking_mode: 'legacy' as 'legacy' | 'managed',
})

const colorOptions = [
  '#EF4444', '#F97316', '#F59E0B', '#84CC16', '#10B981',
  '#06B6D4', '#3B82F6', '#6366F1', '#8B5CF6', '#EC4899',
  '#1677FF', '#07C160', '#1F2937', '#4B5563'
]

const accountTypes = [
  // 现金
  { value: 'cash', label: '现金', icon: 'banknote' },
  // 银行
  { value: 'bank_card', label: '银行卡', icon: 'landmark' },
  { value: 'savings', label: '储蓄卡', icon: 'credit-card' },
  // 第三方支付
  { value: 'alipay', label: '支付宝', icon: 'circle-dot' },
  { value: 'wechat', label: '微信', icon: 'message-circle' },
  { value: 'qq_pay', label: 'QQ钱包', icon: 'message-square' },
  { value: 'jd_pay', label: '京东钱包', icon: 'shopping-bag' },
  { value: 'apple_pay', label: 'Apple Pay', icon: 'smartphone' },
  // 信贷/负债
  { value: 'credit', label: '信用卡', icon: 'credit-card' },
  { value: 'huabei', label: '花呗', icon: 'flower-2' },
  { value: 'baitiao', label: '白条', icon: 'scroll' },
  { value: 'loan', label: '贷款', icon: 'building-2' },
  { value: 'mortgage', label: '房贷', icon: 'home' },
  { value: 'car_loan', label: '车贷', icon: 'car' },
  { value: 'consumer_loan', label: '消费贷', icon: 'wallet' },
  { value: 'payable', label: '应付款', icon: 'wallet' },
  { value: 'receivable', label: '应收款', icon: 'wallet' },
  // 投资
  { value: 'investment', label: '投资账户', icon: 'trending-up' },
  { value: 'fund', label: '基金', icon: 'pie-chart' },
  { value: 'stock', label: '股票', icon: 'bar-chart-2' },
  { value: 'crypto', label: '数字货币', icon: 'bitcoin' },
  // 其他
  { value: 'prepaid', label: '充值卡', icon: 'ticket' },
  { value: 'other', label: '其他', icon: 'wallet' }
]

const netAssets = computed(() => totalAssets.value - totalLiabilities.value)

const isFormValid = computed(() => {
  if (!editingAccount.value && form.value.debt_tracking_mode === 'managed' && isDebtAccount(form.value.type)) {
    if (!supportsManagedDebt.value) return false
    try { debtCents(String(form.value.initial_balance)) } catch { return false }
  }
  return form.value.name.trim() !== ''
})

onMounted(() => {
  loadAccounts()
  void loadDebtCapability()
})

async function loadDebtCapability() {
  debtCapabilityError.value = ''
  try {
    const caps = await debtApi.capabilities()
    supportsManagedDebt.value = caps.contract_version === 1 && caps.multiple_plans &&
      caps.explicit_allocation && caps.reversal && caps.managed_accounts === 'new_accounts_only'
  } catch (error) {
    supportsManagedDebt.value = false
    if ((error as { status?: number }).status !== 404) debtCapabilityError.value = '多分期能力暂未确认，可重试；旧模式账户继续可用。'
  }
}

watch(ledgerMutationRevision, () => void loadAccounts())
onBeforeUnmount(() => {
  accountRequests.begin()
  formSubmission.reset()
})

async function loadAccounts() {
  const requestGeneration = accountRequests.begin()
  loading.value = true
  loadError.value = ''
  try {
    const allData = await accountApi.getList(true)
    if (!accountRequests.isLatest(requestGeneration)) return
    accounts.value = allData.list.filter(a => !a.is_archived)
    archivedAccounts.value = allData.list.filter(a => a.is_archived)
    const totals = accountSummaryTotals(allData)
    totalAssets.value = totals.totalAssets
    totalLiabilities.value = totals.totalLiabilities
    hasLoaded.value = true
  } catch (e) {
    if (accountRequests.isLatest(requestGeneration)) {
      loadError.value = '账户加载失败，请检查网络后重试。'
    }
  } finally {
    if (accountRequests.isLatest(requestGeneration)) {
      loading.value = false
    }
  }
}

function formatMoney(value: number) {
  return value.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

function getAccountIcon(type: string) {
  const found = accountTypes.find(t => t.value === type)
  return found?.icon || 'wallet'
}

function openCreate(event?: Event) {
  if (event?.currentTarget instanceof HTMLElement) dialogTrigger.value = event.currentTarget
  formSubmission.reset()
  editingAccount.value = null
  const defaultType = accountTypes[0]
  form.value = { 
    name: '', 
    type: 'cash', 
    icon: defaultType.icon,
    color: '#3B82F6',
    initial_balance: '0',
    debt_tracking_mode: 'legacy',
  }
  showDialog.value = true
}

function openEdit(account: Account, event?: Event) {
  if (event?.currentTarget instanceof HTMLElement) dialogTrigger.value = event.currentTarget
  formSubmission.reset()
  editingAccount.value = account
  form.value = {
    name: account.name,
    type: account.type,
    icon: account.icon || getAccountIcon(account.type),
    color: account.color || '#3B82F6',
    initial_balance: account.initial_balance.toString(),
    debt_tracking_mode: account.debt_tracking_mode ?? 'legacy',
  }
  showDialog.value = true
}

function closeDialog() {
  formSubmission.reset()
  showDialog.value = false
  editingAccount.value = null
}

async function submitForm() {
  if (saving.value || !isFormValid.value) return
  const submission = formSubmission.begin()
  if (!submission) return
  const editingId = editingAccount.value?.id
  
  try {
    const params: CreateAccountParams = {
      name: form.value.name,
      type: form.value.type as AccountType,
      icon: form.value.icon,
      color: form.value.color,
      initial_balance: parseFloat(form.value.initial_balance) || 0
    }
    
    if (editingId) {
      await accountApi.update(editingId, {
        name: params.name,
        icon: params.icon,
        color: params.color
      })
      notifyLedgerMutation()
      if (!submission.isCurrent()) return
      toast.success('修改成功')
    } else {
      if (form.value.debt_tracking_mode === 'managed' && isDebtAccount(params.type)) {
        if (!supportsManagedDebt.value) throw Error('尚未确认后端多分期能力，请重试')
        params.debt_tracking_mode = 'managed'
        params.initial_balance = debtCents(String(form.value.initial_balance)) / 100
      }
      const created = await accountApi.create(params)
      notifyLedgerMutation()
      if (!submission.isCurrent()) return
      toast.success('添加成功')
      if (params.debt_tracking_mode === 'managed' && created.id) void router.push({ path: '/reminders', query: { account_id: created.id } })
    }
    
    closeDialog()
  } catch (e: any) {
    if (submission.isCurrent()) toast.error(e.message || '保存失败')
  } finally {
    submission.finish()
  }
}

function confirmDelete(id: string, event?: Event) {
  if (event?.currentTarget instanceof HTMLElement) deleteTrigger.value = event.currentTarget
  deletingId.value = id
  showDeleteModal.value = true
}

async function handleDelete() {
  if (!deletingId.value) return
  try {
    await accountApi.delete(deletingId.value)
    showDeleteModal.value = false
    deletingId.value = null
    toast.success('删除成功')
    loadAccounts()
  } catch (e: any) {
    const msg = e.message || ''
    if (msg.includes('non-zero balance') || msg.includes('history') || msg.includes('referenced')) {
      toast.error('仅未使用且余额为零的账户可删除，有历史记录或关联记录请归档')
    } else {
      toast.error(msg || '删除失败')
    }
  }
}

async function toggleArchive(account: Account) {
  try {
    await accountApi.archive(account.id, !account.is_archived)
    toast.success(account.is_archived ? '已恢复账户' : '已归档')
    loadAccounts()
  } catch (e: any) {
    toast.error(e.message || '操作失败')
  }
}

const displayAccounts = computed(() => showArchived.value ? archivedAccounts.value : accounts.value)
</script>

<template>
  <FinancePage title="我的钱包" :context="hasLoaded ? `${accounts.length} 个账户` : '尚未加载'" :icon="Wallet" back-label="返回上一页" @back="router.back()">
    <template #actions>
      <button type="button" :aria-label="showArchived ? '查看在用账户' : '查看归档账户'" class="finance-icon-button" :class="{ 'text-amber-600': showArchived }" @click="showArchived = !showArchived"><Archive :size="19" /></button>
      <button ref="pageHeading" v-if="!showArchived" type="button" aria-label="添加新账户" class="finance-icon-button" @click="openCreate($event)"><Plus :size="20" /></button>
    </template>

    <div class="space-y-6">
      <div v-if="loadError" role="alert" class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
        <p>{{ loadError }}</p>
        <p v-if="hasLoaded" class="mt-1">以下账户和余额为上次成功加载的结果，尚未更新。</p>
        <button class="mt-3 rounded-lg border border-current px-3 py-1.5 font-medium disabled:opacity-50" :disabled="loading" @click="loadAccounts">重新加载账户</button>
      </div>
      <p v-else-if="loading" role="status" class="text-center text-sm text-gray-500 dark:text-gray-400">
        {{ hasLoaded ? '账户更新中，以下暂时保留已加载的余额…' : '账户加载中…' }}
      </p>
      <!-- Asset Overview Cards -->
      <div v-if="hasLoaded" class="account-summary grid grid-cols-3 gap-2 md:gap-4">
        <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-2xl p-3 md:p-4 flex flex-col items-center justify-center gap-0.5 shadow-sm border border-white/40 dark:border-white/5">
          <div class="account-summary-value text-base md:text-2xl font-bold font-nums text-gray-900 dark:text-white w-full text-center">¥{{ formatMoney(netAssets) }}</div>
          <div class="text-[10px] md:text-xs text-gray-500">净资产</div>
        </div>
        <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-2xl p-3 md:p-4 flex flex-col items-center justify-center gap-0.5 shadow-sm border border-white/40 dark:border-white/5">
          <div class="account-summary-value text-base md:text-2xl font-bold font-nums text-green-600 dark:text-green-400 w-full text-center">¥{{ formatMoney(totalAssets) }}</div>
          <div class="text-[10px] md:text-xs text-gray-500">总资产</div>
        </div>
        <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-2xl p-3 md:p-4 flex flex-col items-center justify-center gap-0.5 shadow-sm border border-white/40 dark:border-white/5">
          <div class="account-summary-value text-base md:text-2xl font-bold font-nums text-red-500 dark:text-red-400 w-full text-center">¥{{ formatMoney(totalLiabilities) }}</div>
          <div class="text-[10px] md:text-xs text-gray-500">总负债</div>
        </div>
      </div>

      <!-- Section Title -->
      <RouterLink to="/reminders"
        class="flex items-center justify-between gap-3 rounded-2xl border border-blue-100/70 bg-white/70 px-5 py-4 text-blue-600 shadow-sm backdrop-blur-xl dark:border-blue-500/15 dark:bg-[#1C1C1E]/70 dark:text-blue-300">
        <div><span class="text-sm font-bold">负债管理</span><p class="mt-1 text-xs text-gray-500">按账户管理多笔分期，保留原有还款提醒</p></div>
        <ChevronDown :size="18" class="-rotate-90 shrink-0" />
      </RouterLink>
      <div v-if="debtCapabilityError" role="status" class="text-xs leading-relaxed text-gray-500">{{ debtCapabilityError }} <button class="min-h-8 text-blue-500" @click="loadDebtCapability">重试</button></div>
      <div v-if="hasLoaded" class="flex items-center justify-between pt-2">
        <h2 class="text-sm font-bold text-gray-900 dark:text-white px-1">{{ showArchived ? '已归档账户' : '我的账户' }}</h2>
        <span class="text-xs text-gray-400">{{ displayAccounts.length }} 张卡片</span>
      </div>

      <!-- Account Cards Grid -->
      <div v-if="displayAccounts.length > 0" class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-1 lg:grid-cols-2 gap-6">
        <Hover3D
          v-for="account in displayAccounts" 
          :key="account.id"
          :intensity="15"
          :scale="1.03"
        >
          <div 
            class="group relative w-full aspect-[1.586/1] min-h-60 rounded-[22px] p-5 flex flex-col justify-between overflow-hidden card-premium"
            :style="{ 
              background: `linear-gradient(145deg, 
                color-mix(in srgb, ${account.color || '#3B82F6'} 100%, white 15%) 0%,
                ${account.color || '#3B82F6'} 35%,
                color-mix(in srgb, ${account.color || '#3B82F6'} 100%, black 20%) 100%)`,
              boxShadow: `
                0 25px 50px -12px ${account.color || '#3B82F6'}40,
                0 12px 25px -8px ${account.color || '#3B82F6'}30,
                inset 0 1px 1px rgba(255,255,255,0.2),
                inset 0 -1px 1px rgba(0,0,0,0.1)
              `
            }"
          >
            <!-- Metallic Texture Overlay -->
            <div class="absolute inset-0 opacity-[0.08] pointer-events-none" 
                 style="background: repeating-linear-gradient(
                   90deg,
                   transparent,
                   transparent 1px,
                   rgba(255,255,255,0.03) 1px,
                   rgba(255,255,255,0.03) 2px
                 );"></div>
            <!-- Glass Shine Effect -->
            <div class="absolute inset-0 bg-gradient-to-br from-white/30 via-white/5 to-transparent pointer-events-none"></div>
            <div class="absolute inset-0 bg-gradient-to-t from-black/20 via-transparent to-transparent pointer-events-none"></div>
            <!-- Top Light Reflection -->
            <div class="absolute top-0 left-0 right-0 h-1/3 bg-gradient-to-b from-white/15 to-transparent pointer-events-none"></div>
            <!-- Corner Highlights -->
            <div class="absolute -top-32 -right-32 w-64 h-64 bg-white/15 rounded-full blur-3xl pointer-events-none"></div>
            <div class="absolute -bottom-20 -left-20 w-48 h-48 bg-black/15 rounded-full blur-3xl pointer-events-none"></div>
            <!-- Edge Highlight -->
            <div class="absolute inset-0 rounded-[22px] pointer-events-none" style="box-shadow: inset 0 0 0 1px rgba(255,255,255,0.15);"></div>

            <!-- Top Row: Icon & Name -->
            <div class="relative z-10 flex items-start justify-between text-white gap-2">
              <div class="flex items-center gap-3 min-w-0 flex-1">
                <!-- Keep the translucent material without a backdrop filter per account: long lists stall WebKit. -->
                <div class="w-11 h-11 rounded-xl bg-white/15 flex items-center justify-center shadow-lg border border-white/20 flex-shrink-0"
                     style="box-shadow: 0 6px 12px rgba(0,0,0,0.12), inset 0 1px 1px rgba(255,255,255,0.2);">
                  <DynamicIcon :icon="account.icon || getAccountIcon(account.type)" :size="20" class="drop-shadow-md" />
                </div>
                <div class="min-w-0 flex-1">
                  <div class="font-bold text-lg leading-snug drop-shadow-md truncate" style="text-shadow: 0 2px 4px rgba(0,0,0,0.2);">{{ account.name }}</div>
                  <div class="text-[10px] text-white/60 uppercase tracking-widest mt-0.5 font-medium">{{ account.type.replace('_', ' ').toUpperCase() }}</div>
                </div>
              </div>
            </div>

            <div class="relative z-10 flex items-center justify-between gap-2">
              <div class="w-10 sm:w-14 h-10 shrink-0 rounded-lg flex items-center justify-center relative overflow-hidden"
                   style="background: linear-gradient(145deg, #fcd34d 0%, #f59e0b 50%, #b45309 100%);
                          box-shadow: 0 4px 8px rgba(0,0,0,0.2), inset 0 1px 2px rgba(255,255,255,0.4), inset 0 -1px 2px rgba(0,0,0,0.2);">
                <div class="absolute inset-0 bg-[linear-gradient(110deg,transparent_25%,rgba(255,255,255,0.4)_50%,transparent_75%)] animate-shimmer"></div>
                <!-- Chip Pattern -->
                <div class="grid grid-cols-4 gap-[2px] w-8">
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                </div>
              </div>
              <div class="flex shrink-0 gap-1">
                <button
                  class="w-11 h-11 flex items-center justify-center bg-white/20 active:bg-white/40 hover:bg-white/30 rounded-xl text-white border border-white/25 shadow-md"
                  :aria-label="`查看账户流水 ${account.name}`"
                  @click.stop="router.push(`/account-logs/${account.id}`)"
                >
                  <ScrollText :size="16" />
                </button>
                <button
                  class="w-11 h-11 flex items-center justify-center bg-white/20 active:bg-white/40 hover:bg-white/30 rounded-xl text-white border border-white/25 shadow-md"
                  :aria-label="`编辑账户 ${account.name}`"
                  @click.stop="openEdit(account, $event)"
                >
                  <Pen :size="16" />
                </button>
                <button
                  class="w-11 h-11 flex items-center justify-center bg-white/20 active:bg-white/40 hover:bg-white/30 rounded-xl text-white border border-white/25 shadow-md"
                  :aria-label="`${account.is_archived ? '恢复' : '归档'}账户 ${account.name}`"
                  @click.stop="toggleArchive(account)"
                >
                  <ArchiveRestore v-if="account.is_archived" :size="16" />
                  <Archive v-else :size="16" />
                </button>
                <button
                  class="w-11 h-11 flex items-center justify-center bg-white/20 active:bg-red-500 hover:bg-red-500 rounded-xl text-white border border-white/25 shadow-md"
                  :aria-label="`删除账户 ${account.name}`"
                  @click.stop="confirmDelete(account.id, $event)"
                >
                  <Trash2 :size="16" />
                </button>
              </div>
            </div>

            <!-- Bottom: Balance -->
            <div class="relative z-10 text-white">
              <div class="flex items-end justify-between">
                <div>
                  <div class="text-[11px] text-white/60 mb-1.5 uppercase tracking-widest font-semibold drop-shadow-sm">Current Balance</div>
                  <div class="text-[28px] font-bold font-nums tracking-tight" style="text-shadow: 0 2px 8px rgba(0,0,0,0.25);">
                    <span class="text-lg align-top opacity-70 mr-0.5">¥</span>{{ formatMoney(account.current_balance) }}
                  </div>
                </div>
                <!-- Logo/Type indicator bottom right -->
                <RouterLink v-if="account.debt_tracking_mode === 'managed'" :to="{ path: '/reminders', query: { account_id: account.id } }"
                  :aria-label="`管理负债 ${account.name}`" class="flex min-h-11 shrink-0 items-center rounded-xl border border-white/20 bg-white/15 px-3 text-xs font-semibold text-white">管理负债</RouterLink>
                <div v-else class="opacity-25 drop-shadow-lg">
                  <CreditCard :size="32" stroke-width="1.5" />
                </div>
              </div>
            </div>
          </div>
        </Hover3D>

        <!-- Add Card Button (Card Style) -->
        <Hover3D
          v-if="!showArchived"
          :intensity="8"
          :scale="1.02"
          :shine="false"
        >
          <button 
            class="aspect-[1.586/1] w-full rounded-[22px] border-2 border-dashed border-gray-300/80 dark:border-gray-600/50 flex flex-col items-center justify-center gap-4 text-gray-400 hover:text-blue-500 hover:border-blue-400/50 hover:bg-blue-50/50 dark:hover:bg-blue-900/10 transition-all duration-300 group bg-white/50 dark:bg-white/5 backdrop-blur-sm"
            @click="openCreate($event)"
          >
            <div class="w-14 h-14 rounded-2xl bg-gray-100 dark:bg-gray-800 flex items-center justify-center group-hover:bg-blue-100 dark:group-hover:bg-blue-900/30 transition-all duration-300 shadow-sm group-hover:shadow-lg group-hover:shadow-blue-500/10">
              <Plus :size="28" class="group-hover:scale-110 transition-transform duration-300" stroke-width="1.5" />
            </div>
            <div class="text-center">
              <div class="font-semibold text-sm">添加新账户</div>
              <div class="text-xs text-gray-400 mt-0.5">银行卡 / 支付宝 / 微信...</div>
            </div>
          </button>
        </Hover3D>
      </div>

      <!-- Empty State -->
      <div v-else-if="hasLoaded && !loading && !loadError" class="py-24 text-center">
        <div class="w-24 h-24 bg-gradient-to-br from-gray-100 to-gray-50 dark:from-gray-800 dark:to-gray-900 rounded-3xl flex items-center justify-center mx-auto mb-6 text-gray-400 shadow-lg shadow-gray-200/50 dark:shadow-black/30">
          <Archive v-if="showArchived" :size="40" stroke-width="1.5" />
          <Wallet v-else :size="40" stroke-width="1.5" />
        </div>
        <h3 class="text-lg font-bold text-gray-700 dark:text-gray-300 mb-2">{{ showArchived ? '暂无归档账户' : '开始管理您的资产' }}</h3>
        <p class="text-sm text-gray-400 mb-8 max-w-xs mx-auto">{{ showArchived ? '归档的账户会显示在这里' : '添加银行卡、支付宝、微信等账户，轻松追踪每一笔收支' }}</p>
        <button
          v-if="!showArchived"
          class="px-8 py-3 bg-gradient-to-r from-blue-500 to-blue-600 text-white rounded-2xl hover:shadow-lg hover:shadow-blue-500/30 hover:-translate-y-0.5 transition-all font-semibold text-sm"
          @click="openCreate($event)"
        >
          <span class="flex items-center gap-2">
            <Plus :size="18" />
            添加第一张卡
          </span>
        </button>
        <button
          v-else
          class="px-6 py-2.5 border border-gray-200 dark:border-gray-600 text-gray-600 dark:text-gray-300 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-800 transition font-medium text-sm"
          @click="showArchived = false"
        >
          返回钱包
        </button>
      </div>
    </div>

    <AppDialog v-if="showDialog" :title="editingAccount ? '编辑卡片' : '添加新卡'" :busy="saving" sheet :return-focus="dialogTrigger" :fallback-focus="pageHeading" @close="closeDialog">
      <form id="account-form" class="account-form" novalidate @submit.prevent="submitForm">
        <div class="account-preview" :style="{ background: `linear-gradient(135deg, ${form.color} 0%, ${form.color}dd 100%)` }">
          <div class="account-preview-top">
            <span class="account-preview-icon"><DynamicIcon :icon="form.icon || getAccountIcon(form.type)" :size="17" /></span>
            <span><strong>{{ form.name || '卡片名称' }}</strong><small>{{ accountTypes.find(t => t.value === form.type)?.label || '账户类型' }}</small></span>
          </div>
          <div class="account-preview-balance"><small>余额</small><strong>¥ {{ form.initial_balance || '0.00' }}</strong></div>
        </div>
        <label class="finance-field">
          <span>卡片名称</span>
          <input v-model="form.name" name="name" type="text" autocomplete="off" placeholder="例如：招商银行" class="finance-input" required />
        </label>
        <div v-if="!editingAccount" class="finance-form-grid">
          <label class="finance-field">
            <span>账户类型</span>
            <span class="account-select-wrap">
              <select v-model="form.type" name="type" aria-label="账户类型" class="finance-input account-select">
                <option v-for="t in accountTypes" :key="t.value" :value="t.value">{{ t.label }}</option>
              </select>
              <ChevronDown :size="17" aria-hidden="true" />
            </span>
          </label>
          <label class="finance-field">
            <span>初始余额</span>
            <span class="account-balance-wrap"><span aria-hidden="true">¥</span><input v-model="form.initial_balance" name="initial_balance" type="number" step="0.01" inputmode="decimal" placeholder="0.00" class="finance-input account-balance-input" /></span>
          </label>
        </div>
        <label v-if="!editingAccount && isDebtAccount(form.type) && supportsManagedDebt" class="finance-field">
          <span>负债管理方式</span>
          <span class="account-select-wrap">
            <select v-model="form.debt_tracking_mode" name="debt_tracking_mode" aria-label="负债管理方式" class="finance-input account-select">
              <option value="legacy">旧模式（保持现有还款方式）</option>
              <option value="managed">多分期（分别跟踪本金与利息）</option>
            </select>
            <ChevronDown :size="17" aria-hidden="true" />
          </span>
          <small class="finance-muted">仅新账户可选择；已有账户与历史还款不自动转换或重算。</small>
        </label>
        <label class="finance-field">
          <span>图标</span>
          <span class="account-icon-field">
            <span class="account-icon-sample" :style="{ backgroundColor: form.color }"><DynamicIcon :icon="form.icon" :size="22" /></span>
            <input v-model="form.icon" name="icon" type="text" placeholder="图标名称或 emoji" class="finance-input" />
          </span>
        </label>
        <fieldset class="account-colors">
          <legend>卡片颜色</legend>
          <button v-for="c in colorOptions" :key="c" type="button" class="account-color" :class="{ 'is-selected': form.color === c }" :style="{ backgroundColor: c }" :aria-label="`选择颜色 ${c}`" :aria-pressed="form.color === c" @click="form.color = c" />
        </fieldset>
      </form>
      <template #footer>
        <button type="button" class="finance-button" :disabled="saving" @click="closeDialog">取消</button>
        <button type="submit" form="account-form" class="finance-button is-primary" :disabled="saving || !isFormValid">{{ saving ? '保存中…' : '保存卡片' }}</button>
      </template>
    </AppDialog>

    <AppDialog v-if="showDeleteModal" title="确认销户" :return-focus="deleteTrigger" :fallback-focus="pageHeading" @close="showDeleteModal = false">
      <p class="finance-muted">仅未使用且余额为零的账户可删除。有历史交易或关联记录的账户，请归档保留记录。</p>
      <template #footer>
        <button type="button" class="finance-button" @click="showDeleteModal = false">取消</button>
        <button type="button" class="finance-button is-danger" @click="handleDelete">销户</button>
      </template>
    </AppDialog>
  </FinancePage>
</template>

<style scoped>
.account-summary > div { min-width: 0; }
.account-summary-value { overflow-wrap: anywhere; }
.account-form { display: flex; flex-direction: column; gap: 18px; }
.account-preview { position: relative; display: flex; flex-direction: column; justify-content: space-between; min-height: 146px; padding: 19px; overflow: hidden; border-radius: 17px; color: white; box-shadow: inset 0 1px 1px rgb(255 255 255 / 24%), 0 14px 28px -14px currentColor; }
.account-preview::after { position: absolute; inset: 0; content: ""; pointer-events: none; background: linear-gradient(120deg, rgb(255 255 255 / 24%), transparent 48%, rgb(0 0 0 / 16%)); }
.account-preview-top,.account-preview-balance { position: relative; z-index: 1; }
.account-preview-top { display: flex; align-items: center; gap: 10px; }
.account-preview-top > span:last-child { min-width: 0; }
.account-preview-top strong,.account-preview-top small { display: block; overflow-wrap: anywhere; }
.account-preview-top strong { font-size: 14px; font-weight: 600; }
.account-preview-top small,.account-preview-balance small { margin-top: 3px; color: rgb(255 255 255 / 68%); font-size: 10px; line-height: 1.3; }
.account-preview-icon { display: grid; place-items: center; width: 34px; height: 34px; flex: none; border: 1px solid rgb(255 255 255 / 18%); border-radius: 50%; background: rgb(255 255 255 / 18%); }
.account-preview-balance { align-self: flex-end; text-align: right; }
.account-preview-balance strong { display: block; margin-top: 3px; font-size: 22px; font-weight: 600; font-variant-numeric: tabular-nums; letter-spacing: -.025em; }
.account-select-wrap,.account-balance-wrap { position: relative; display: flex; align-items: center; }
.account-select-wrap svg { position: absolute; right: 13px; color: var(--fp-secondary); pointer-events: none; }
.account-select { appearance: none; padding-right: 38px; font-weight: 500; }
.account-balance-wrap > span { position: absolute; left: 12px; z-index: 1; color: var(--fp-secondary); pointer-events: none; }
.account-balance-input { padding-left: 28px; font-weight: 550; font-variant-numeric: tabular-nums; }
.account-icon-field { display: flex; align-items: center; gap: 10px; min-width: 0; }
.account-icon-sample { display: grid; place-items: center; width: 44px; height: 44px; flex: none; border-radius: 12px; color: white; }
.account-colors { min-width: 0; margin: 0; padding: 0; border: 0; }
.account-colors legend { margin-bottom: 9px; color: var(--fp-secondary); font-size: 12px; font-weight: 500; }
.account-colors { display: flex; flex-wrap: wrap; gap: 11px; }
.account-colors legend { flex-basis: 100%; }
.account-color { width: 32px; height: 32px; flex: none; border-radius: 50%; box-shadow: inset 0 0 0 1px rgb(255 255 255 / 24%); transition: transform 150ms ease, box-shadow 150ms ease; }
.account-color:hover { transform: scale(1.08); }
.account-color.is-selected { box-shadow: 0 0 0 2px var(--fp-solid), 0 0 0 4px var(--fp-secondary); }
@media (prefers-reduced-motion: reduce) { .account-color { transition: none; } }
@media (max-width: 767px) {
  .account-summary { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .account-summary > div:first-child { grid-column: 1 / -1; }
  .account-summary > div:first-child .account-summary-value { font-size: 24px; }
  .account-preview { min-height: 136px; padding: 17px; }
  .account-colors { gap: 9px; }
}
@media (max-width: 359px) {
  .account-summary { grid-template-columns: minmax(0, 1fr); }
}
</style>
