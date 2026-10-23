<script setup lang="ts">
import FinancePage from '@/components/ui/FinancePage.vue'
import FinanceListFooter from '@/components/ui/FinanceListFooter.vue'
import { ref, onMounted, onBeforeUnmount, computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { accountLogApi, type AccountLog } from '@/api/accountLog'
import { accountApi, type Account } from '@/api/account'
import { TrendingUp, TrendingDown, RotateCcw, ArrowLeftRight, Sparkles, ScrollText } from '@lucide/vue'
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
const logsLoaded = ref(false)
const logsFailed = ref(false)
const failedPage = ref(1)
const accountFailed = ref(false)
const hasMore = computed(() => logs.value.length < total.value)
const ledgerMutationRevision = useLedgerMutationRevision()
const accountRequests = createRequestGeneration()
const logRequests = createRequestGeneration()
onBeforeUnmount(() => { accountRequests.begin(); logRequests.begin() })

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
    logsLoaded.value = false
    logsFailed.value = false
  }
  accountFailed.value = false
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
        accountFailed.value = true
      }
    }
  } else if (accountRequests.isLatest(accountGeneration)) {
    account.value = null
  }
  await logsPromise
}

async function loadLogs(requestedPage = page.value, replace = requestedPage === 1): Promise<'success' | 'failed' | 'stale'> {
  const requestGeneration = logRequests.begin()
  const requestedAccountId = accountId.value
  loading.value = true
  logsFailed.value = false
  try {
    const params = { page: requestedPage, page_size: pageSize.value }
    const res = requestedAccountId
      ? await accountLogApi.getByAccountId(requestedAccountId, params)
      : await accountLogApi.getAll(params)

    if (
      !logRequests.isLatest(requestGeneration)
      || accountId.value !== requestedAccountId
    ) return 'stale'

    if (replace) {
      logs.value = res.list || []
      page.value = 1
    } else {
      logs.value = [...logs.value, ...(res.list || [])]
      page.value = requestedPage
    }
    total.value = res.total
    logsLoaded.value = true
    return 'success'
  } catch (e) {
    if (logRequests.isLatest(requestGeneration)) {
      logsFailed.value = true
      failedPage.value = requestedPage
      return 'failed'
    }
    return 'stale'
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
  <FinancePage :title="account ? account.name + ' 流水' : '账户流水'" :icon="ScrollText" back-label="返回账户" @back="goBack">
    <div>
      <div v-if="(logsFailed && (!logsLoaded || failedPage === 1)) || accountFailed" role="alert" class="py-3 text-sm text-amber-700">
        <p v-if="accountFailed">账户信息加载失败。<button class="underline" @click="loadLedgerAccountData()">重试账户信息</button></p>
        <p v-if="logsFailed && (!logsLoaded || failedPage === 1)">流水加载失败。{{ logsLoaded ? '已加载的流水仍保留。' : '尚未获得流水数据。' }}
          <button class="underline" @click="loadLogs(failedPage, failedPage === 1)">重新加载流水</button>
        </p>
      </div>
      <!-- Account Summary Card -->
      <div v-if="account">
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
      <div class="py-3 flex items-center justify-between">
        <span class="text-sm font-medium text-gray-500 dark:text-gray-400">
          <template v-if="logsLoaded">共 <span class="text-gray-900 dark:text-white font-semibold">{{ total }}</span> 条流水记录</template>
          <template v-else>流水总数待加载</template>
        </span>
      </div>

      <!-- Log List with Date Groups -->
      <div class="pb-6 space-y-4">
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
                class="w-11 h-11 shrink-0 rounded-xl flex items-center justify-center shadow-sm"
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
                <div class="flex items-start justify-between gap-2">
                  <div class="min-w-0 flex flex-1 flex-wrap items-center gap-2">
                    <span 
                      class="shrink-0 font-semibold text-sm px-2 py-0.5 rounded-lg"
                      :class="[getLogTypeInfo(log.type).bgColor, getLogTypeInfo(log.type).textColor]"
                    >
                      {{ getLogTypeInfo(log.type).label }}
                    </span>
                    <span v-if="log.account && !accountId" class="min-w-0 [overflow-wrap:anywhere] text-xs text-gray-500 dark:text-gray-400">
                      {{ log.account.name }}
                    </span>
                  </div>
                  <span 
                    class="shrink-0 text-lg font-bold tabular-nums"
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
                <div class="mt-2 flex flex-wrap items-center justify-between gap-2">
                  <span v-if="log.remark" class="text-xs text-gray-500 dark:text-gray-400 truncate max-w-[65%] bg-gray-50 dark:bg-gray-700/50 px-2 py-0.5 rounded">
                    {{ log.remark }}
                  </span>
                  <span v-else></span>
                  <span class="text-xs text-gray-400 dark:text-gray-500" :title="formatFullDate(log.created_at)">
                    {{ dayjs(log.created_at).format('HH:mm') }}
                  </span>
                  <RouterLink v-if="log.debt_operation_id" :to="{ path: '/reminders', query: { operation_id: log.debt_operation_id } }"
                    :aria-label="`查看分期凭证 ${log.id}`" class="inline-flex min-h-11 items-center rounded-lg px-2 text-xs font-medium text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-500/10">查看分期凭证</RouterLink>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Empty State -->
      <div v-if="logsLoaded && !logsFailed && !loading && logs.length === 0" class="py-20 text-center">
        <div class="w-20 h-20 mx-auto mb-4 rounded-full bg-gray-100 dark:bg-gray-800 flex items-center justify-center">
          <ScrollText :size="32" class="text-gray-300 dark:text-gray-600" />
        </div>
        <div class="text-gray-500 dark:text-gray-400 font-medium mb-1">暂无流水记录</div>
        <div class="text-sm text-gray-400 dark:text-gray-500">交易记录会自动生成流水日志</div>
      </div>

      <!-- Loading -->
      <div v-if="loading && (!logsLoaded || logs.length === 0)" role="status" class="py-12 text-center">
        <div class="inline-flex items-center gap-2 px-4 py-2 bg-white dark:bg-gray-800 rounded-full shadow-sm">
          <div class="w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin"></div>
          <span class="text-sm text-gray-500 dark:text-gray-400">加载中...</span>
        </div>
      </div>
      </div>

      <FinanceListFooter v-if="logsLoaded && logs.length > 0 && !(logsFailed && failedPage === 1)"
        label="流水列表加载" :count="logs.length" :has-more="hasMore" :loading="loading"
        :error="logsFailed ? '更多流水加载失败，已加载的流水仍保留。' : ''"
        retry-label="重新加载流水" @more="logsFailed ? loadLogs(failedPage, false) : loadMore()" />
    </div>
  </FinancePage>
</template>
