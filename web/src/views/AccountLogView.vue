<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { accountLogApi, type AccountLog } from '@/api/accountLog'
import { accountApi, type Account } from '@/api/account'
import { ChevronLeft, TrendingUp, TrendingDown, RotateCcw, ArrowLeftRight, Sparkles, ScrollText } from 'lucide-vue-next'
import DynamicIcon from '@/components/DynamicIcon.vue'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { createRequestGeneration } from '@/utils/requestGeneration'
import dayjs from 'dayjs'

const route = useRoute()
const router = useRouter()

const accountId = computed(() => route.params.id as string | undefined)
const account = ref<Account | null>(null)
const logs = ref<AccountLog[]>([])
const loading = ref(false)
const page = ref(1)
const pageSize = ref(50)
const total = ref(0)
const hasMore = computed(() => logs.value.length < total.value)
const ledgerMutationRevision = useLedgerMutationRevision()
const accountRequests = createRequestGeneration()
const logRequests = createRequestGeneration()

onMounted(loadLedgerAccountData)
watch(accountId, () => void loadLedgerAccountData(true))
watch(ledgerMutationRevision, () => void loadLedgerAccountData())

async function loadLedgerAccountData(clearPreviousScope = false) {
  const requestedAccountId = accountId.value
  const accountGeneration = accountRequests.begin()
  if (clearPreviousScope) {
    page.value = 1
    account.value = null
    logs.value = []
    total.value = 0
  }
  const logsPromise = loadLogs(1, true)
  if (requestedAccountId) {
    try {
      const nextAccount = await accountApi.getById(requestedAccountId)
      if (
        accountRequests.isLatest(accountGeneration)
        && accountId.value === requestedAccountId
      ) {
        account.value = nextAccount
      }
    } catch (e) {
      if (accountRequests.isLatest(accountGeneration)) {
        console.error('Failed to load account', e)
      }
    }
  } else if (accountRequests.isLatest(accountGeneration)) {
    account.value = null
  }
  await logsPromise
}

async function loadLogs(requestedPage = page.value, replace = requestedPage === 1) {
  const requestGeneration = logRequests.begin()
  const requestedAccountId = accountId.value
  loading.value = true
  try {
    const params = { page: requestedPage, page_size: pageSize.value }
    const res = requestedAccountId
      ? await accountLogApi.getByAccountId(requestedAccountId, params)
      : await accountLogApi.getAll(params)

    if (
      !logRequests.isLatest(requestGeneration)
      || accountId.value !== requestedAccountId
    ) return

    if (replace) {
      logs.value = res.list || []
      page.value = 1
    } else {
      logs.value = [...logs.value, ...(res.list || [])]
      page.value = requestedPage
    }
    total.value = res.total
  } catch (e) {
    if (logRequests.isLatest(requestGeneration)) {
      console.error('Failed to load logs', e)
    }
  } finally {
    if (logRequests.isLatest(requestGeneration)) {
      loading.value = false
    }
  }
}

function loadMore() {
  if (loading.value || !hasMore.value) return
  const nextPage = page.value + 1
  void loadLogs(nextPage, false)
}

function goBack() {
  router.back()
}

function formatMoney(amount: number): string {
  return new Intl.NumberFormat('zh-CN', {
    style: 'currency',
    currency: 'CNY',
    minimumFractionDigits: 2
  }).format(amount)
}

function formatFullDate(date: string): string {
  return dayjs(date).format('YYYY-MM-DD HH:mm:ss')
}

function getLogTypeInfo(type: string) {
  const types: Record<string, { label: string; bgColor: string; textColor: string; icon: typeof TrendingUp }> = {
    income: { label: '收入', bgColor: 'bg-emerald-100 dark:bg-emerald-900/40', textColor: 'text-emerald-600 dark:text-emerald-400', icon: TrendingUp },
    expense: { label: '支出', bgColor: 'bg-rose-100 dark:bg-rose-900/40', textColor: 'text-rose-600 dark:text-rose-400', icon: TrendingDown },
    transfer_in: { label: '转入', bgColor: 'bg-blue-100 dark:bg-blue-900/40', textColor: 'text-blue-600 dark:text-blue-400', icon: ArrowLeftRight },
    transfer_out: { label: '转出', bgColor: 'bg-amber-100 dark:bg-amber-900/40', textColor: 'text-amber-600 dark:text-amber-400', icon: ArrowLeftRight },
    rollback: { label: '撤回', bgColor: 'bg-violet-100 dark:bg-violet-900/40', textColor: 'text-violet-600 dark:text-violet-400', icon: RotateCcw },
    adjustment: { label: '调整', bgColor: 'bg-gray-100 dark:bg-gray-700', textColor: 'text-gray-600 dark:text-gray-400', icon: Sparkles },
  }
  return types[type] || { label: type, bgColor: 'bg-gray-100 dark:bg-gray-700', textColor: 'text-gray-600 dark:text-gray-400', icon: Sparkles }
}

function getAmountChange(log: AccountLog): string {
  const diff = log.balance_after - log.balance_before
  if (diff >= 0) {
    return '+' + formatMoney(diff)
  }
  return formatMoney(diff)
}

function getAmountChangeStyle(log: AccountLog) {
  const diff = log.balance_after - log.balance_before
  if (diff > 0) return 'text-emerald-600 dark:text-emerald-400'
  if (diff < 0) return 'text-rose-600 dark:text-rose-400'
  return 'text-gray-500 dark:text-gray-400'
}

function groupLogsByDate(logs: AccountLog[]) {
  const groups: { date: string; logs: AccountLog[] }[] = []
  let currentDate = ''
  
  for (const log of logs) {
    const date = dayjs(log.created_at).format('YYYY-MM-DD')
    if (date !== currentDate) {
      currentDate = date
      groups.push({ date, logs: [log] })
    } else {
      groups[groups.length - 1].logs.push(log)
    }
  }
  return groups
}

function formatGroupDate(date: string): string {
  const d = dayjs(date)
  const today = dayjs().startOf('day')
  const yesterday = today.subtract(1, 'day')
  
  if (d.isSame(today, 'day')) return '今天'
  if (d.isSame(yesterday, 'day')) return '昨天'
  if (d.isSame(today, 'year')) return d.format('M月D日')
  return d.format('YYYY年M月D日')
}

const groupedLogs = computed(() => groupLogsByDate(logs.value))
</script>

<template>
  <div class="min-h-screen bg-gradient-to-b from-gray-50 to-gray-100 dark:from-gray-900 dark:to-gray-950">
    <!-- Header with Glassmorphism -->
    <div class="sticky top-0 z-10 backdrop-blur-xl bg-white/80 dark:bg-gray-900/80 border-b border-gray-200/50 dark:border-gray-700/50">
      <div class="max-w-3xl mx-auto flex items-center justify-between px-4 py-3">
        <button @click="goBack" class="p-2 -ml-2 rounded-xl hover:bg-gray-100/80 dark:hover:bg-gray-800/80 transition-colors">
          <ChevronLeft :size="24" class="text-gray-600 dark:text-gray-300" />
        </button>
        <h1 class="text-lg font-bold text-gray-900 dark:text-white flex items-center gap-2">
          <ScrollText :size="20" class="text-blue-500" />
          {{ account ? account.name + ' 流水' : '账户流水' }}
        </h1>
        <div class="w-10"></div>
      </div>
    </div>

    <div class="max-w-3xl mx-auto">
      <!-- Account Summary Card -->
      <div v-if="account" class="px-4 pt-4">
        <div 
          class="relative overflow-hidden rounded-2xl p-5 text-white shadow-xl"
          :style="{ 
            background: `linear-gradient(135deg, ${account.color || '#3B82F6'} 0%, ${account.color || '#3B82F6'}dd 100%)` 
          }"
        >
          <div class="absolute top-0 right-0 w-32 h-32 bg-white/10 rounded-full -translate-y-1/2 translate-x-1/2"></div>
          <div class="absolute bottom-0 left-0 w-24 h-24 bg-black/10 rounded-full translate-y-1/2 -translate-x-1/2"></div>
          
          <div class="relative z-10 flex items-center gap-4">
            <div class="w-14 h-14 rounded-2xl bg-white/20 backdrop-blur-sm flex items-center justify-center shadow-lg border border-white/30">
              <DynamicIcon :icon="account.icon || 'wallet'" :size="28" />
            </div>
            <div class="flex-1">
              <div class="text-sm text-white/70 font-medium">当前余额</div>
              <div class="text-3xl font-bold tracking-tight mt-0.5">
                {{ formatMoney(account.current_balance) }}
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Stats Bar -->
      <div class="px-4 py-3 flex items-center justify-between">
        <span class="text-sm font-medium text-gray-500 dark:text-gray-400">
          共 <span class="text-gray-900 dark:text-white font-semibold">{{ total }}</span> 条流水记录
        </span>
      </div>

      <!-- Log List with Date Groups -->
      <div class="px-4 pb-6 space-y-4">
      <div v-for="group in groupedLogs" :key="group.date">
        <!-- Date Header -->
        <div class="flex items-center gap-3 py-2">
          <div class="text-sm font-semibold text-gray-700 dark:text-gray-300">{{ formatGroupDate(group.date) }}</div>
          <div class="flex-1 h-px bg-gradient-to-r from-gray-200 dark:from-gray-700 to-transparent"></div>
        </div>
        
        <!-- Log Cards -->
        <div class="space-y-2">
          <div 
            v-for="log in group.logs" 
            :key="log.id"
            class="bg-white dark:bg-gray-800/80 rounded-2xl p-4 shadow-sm hover:shadow-md transition-all duration-300 border border-gray-100 dark:border-gray-700/50"
          >
            <div class="flex items-center gap-3">
              <!-- Type Icon Badge -->
              <div 
                class="w-11 h-11 rounded-xl flex items-center justify-center shadow-sm"
                :class="[getLogTypeInfo(log.type).bgColor]"
              >
                <component 
                  :is="getLogTypeInfo(log.type).icon" 
                  :size="20" 
                  :class="getLogTypeInfo(log.type).textColor"
                />
              </div>

              <!-- Content -->
              <div class="flex-1 min-w-0">
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-2">
                    <span 
                      class="font-semibold text-sm px-2 py-0.5 rounded-lg"
                      :class="[getLogTypeInfo(log.type).bgColor, getLogTypeInfo(log.type).textColor]"
                    >
                      {{ getLogTypeInfo(log.type).label }}
                    </span>
                    <span v-if="log.account && !accountId" class="text-xs text-gray-500 dark:text-gray-400">
                      {{ log.account.name }}
                    </span>
                  </div>
                  <span 
                    class="text-lg font-bold tabular-nums"
                    :class="getAmountChangeStyle(log)"
                  >
                    {{ getAmountChange(log) }}
                  </span>
                </div>
                
                <!-- Balance Flow -->
                <div class="mt-2 flex items-center gap-2 text-sm">
                  <span class="text-gray-400 dark:text-gray-500 font-mono">{{ formatMoney(log.balance_before) }}</span>
                  <span class="text-gray-300 dark:text-gray-600">→</span>
                  <span class="text-gray-700 dark:text-gray-200 font-mono font-medium">{{ formatMoney(log.balance_after) }}</span>
                </div>

                <!-- Footer -->
                <div class="mt-2 flex items-center justify-between">
                  <span v-if="log.remark" class="text-xs text-gray-500 dark:text-gray-400 truncate max-w-[65%] bg-gray-50 dark:bg-gray-700/50 px-2 py-0.5 rounded">
                    {{ log.remark }}
                  </span>
                  <span v-else></span>
                  <span class="text-xs text-gray-400 dark:text-gray-500" :title="formatFullDate(log.created_at)">
                    {{ dayjs(log.created_at).format('HH:mm') }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Empty State -->
      <div v-if="!loading && logs.length === 0" class="py-20 text-center">
        <div class="w-20 h-20 mx-auto mb-4 rounded-full bg-gray-100 dark:bg-gray-800 flex items-center justify-center">
          <ScrollText :size="32" class="text-gray-300 dark:text-gray-600" />
        </div>
        <div class="text-gray-500 dark:text-gray-400 font-medium mb-1">暂无流水记录</div>
        <div class="text-sm text-gray-400 dark:text-gray-500">交易记录会自动生成流水日志</div>
      </div>

      <!-- Loading -->
      <div v-if="loading" class="py-12 text-center">
        <div class="inline-flex items-center gap-2 px-4 py-2 bg-white dark:bg-gray-800 rounded-full shadow-sm">
          <div class="w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin"></div>
          <span class="text-sm text-gray-500 dark:text-gray-400">加载中...</span>
        </div>
      </div>
      </div>

      <!-- Load More -->
      <div v-if="hasMore && !loading" class="px-4 pb-6">
        <button 
          @click="loadMore"
          class="w-full py-3.5 text-center text-blue-600 dark:text-blue-400 bg-white dark:bg-gray-800 rounded-2xl border border-gray-200 dark:border-gray-700 hover:bg-blue-50 dark:hover:bg-gray-700 font-medium shadow-sm hover:shadow transition-all"
        >
          加载更多
        </button>
      </div>
    </div>
  </div>
</template>
