<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { 
  Eye, EyeOff, ChevronRight, RefreshCw, 
  LayoutList, Calendar as CalendarIcon, Wallet,
  AlertCircle, Check, Home
} from 'lucide-vue-next'
import { accountApi, type AccountListResponse } from '@/api/account'
import { transactionApi, type Transaction } from '@/api/transaction'
import { statisticsApi, type OverviewResponse } from '@/api/statistics'
import { budgetApi, type BudgetSummary } from '@/api/budget'
import { reminderApi, type DebtSummary } from '@/api/reminder'
import { lendingApi, type LendingSummary } from '@/api/lending'
import { getAccountTypeName, AMOUNT_COLORS } from '@/utils/constants'
import TransactionDialog from '@/components/TransactionDialog.vue'
import CalendarView from '@/components/CalendarView.vue'
import { toast } from '@/composables/useToast'
import dayjs from 'dayjs'

const router = useRouter()

const loading = ref(false)
const showAmount = ref(true)
const viewMode = ref<'list' | 'calendar'>('list')
const selectedDate = ref(dayjs().format('YYYY-MM-DD'))

// Data states
const accountData = ref<AccountListResponse | null>(null)
const overview = ref<OverviewResponse | null>(null)
const recentTransactions = ref<Transaction[]>([])
const dateTransactions = ref<Transaction[]>([])
const debtSummary = ref<DebtSummary | null>(null)
const budgetSummary = ref<BudgetSummary | null>(null)
const lendingSummary = ref<LendingSummary | null>(null)

// Dialog states
const showDialog = ref(false)
const editingId = ref<string | null>(null)

// Computed
const currentMonth = computed(() => dayjs().format('YYYY年M月'))
const isToday = computed(() => selectedDate.value === dayjs().format('YYYY-MM-DD'))

onMounted(() => {
  loadData()
  loadDateTransactions(selectedDate.value)
})

async function loadData() {
  loading.value = true
  try {
    const [acc, ov, tx, debt, bud, lending] = await Promise.all([
      accountApi.getList(),
      statisticsApi.getOverview(),
      transactionApi.getList({ page_size: 20 }),
      reminderApi.getDebtSummary(),
      budgetApi.getSummary(),
      lendingApi.getSummary()
    ])
    accountData.value = acc
    overview.value = ov
    recentTransactions.value = tx.list.sort((a, b) => 
      new Date(b.transaction_date).getTime() - new Date(a.transaction_date).getTime()
    )
    debtSummary.value = debt
    budgetSummary.value = bud
    lendingSummary.value = lending
  } catch (e: any) {
    toast.error('加载失败，请重试')
  } finally {
    loading.value = false
  }
}

async function loadDateTransactions(date: string) {
  try {
    const res = await transactionApi.getList({
      start_date: date,
      end_date: date,
      page_size: 100
    })
    // Sort by transaction_date DESC
    dateTransactions.value = res.list.sort((a, b) => 
      new Date(b.transaction_date).getTime() - new Date(a.transaction_date).getTime()
    )
  } catch (e) {
    console.error(e)
  }
}

async function refresh() {
  await loadData()
  if (viewMode.value === 'calendar') {
    await loadDateTransactions(selectedDate.value)
    // Refresh calendar data if exposed
  }
  toast.success('刷新成功')
}

function handleDateSelect(date: string) {
  selectedDate.value = date
  loadDateTransactions(date)
}

function formatMoney(value: number | undefined) {
  if (value === undefined) return '0.00'
  return value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

function getCategoryIcon(icon: string | undefined, name: string) {
  if (icon) return icon
  const map: Record<string, string> = {
    '餐饮': '🍽️', '交通': '🚗', '购物': '🛍️', '娱乐': '🎮',
    '居住': '🏠', '医疗': '💊', '教育': '📚', '工资': '💰',
    '奖金': '🎁', '理财': '📈', '通讯': '📱', '服饰': '👔',
    '美容': '💄', '运动': '🏃', '旅行': '✈️', '社交': '👥',
    '宠物': '🐱', '兼职': '💼', '报销': '📄', '红包': '🧧',
    '其他': '💳'
  }
  return map[name] || '💳'
}

function goToTransactions() {
  router.push('/transactions')
}

function addTransaction() {
  editingId.value = null
  showDialog.value = true
}

function editTransaction(id: string) {
  editingId.value = id
  showDialog.value = true
}

function onTransactionSuccess() {
  loadData()
  loadDateTransactions(selectedDate.value)
}
</script>

<template>
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black pb-24 md:pb-8">
    <!-- Header Area -->
    <div class="bg-white/70 dark:bg-[#1C1C1E]/70 pt-4 pb-4 px-4 md:px-8 sticky top-0 z-30 backdrop-blur-xl border-b border-gray-200/50 dark:border-white/10">
      <div class="max-w-5xl mx-auto flex items-center justify-between">
        <div class="flex items-center gap-4">
          <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-primary to-blue-600 flex items-center justify-center shadow-lg shadow-primary/20">
            <Home class="text-white" :size="28" />
          </div>
          <div>
            <h1 class="text-xl font-bold text-gray-900 dark:text-white">Personal Ledger</h1>
            <div class="text-sm text-gray-500 dark:text-gray-400 mt-0.5">{{ currentMonth }}</div>
          </div>
        </div>
        
        <button
          class="p-2.5 bg-gray-100/50 dark:bg-white/5 text-gray-400 hover:text-primary hover:bg-primary/10 dark:hover:bg-primary/20 rounded-full transition"
          :class="{ 'animate-spin': loading }"
          @click="refresh"
        >
          <RefreshCw :size="20" />
        </button>
      </div>
    </div>

    <div class="max-w-5xl mx-auto px-4 md:px-8 py-6 space-y-6">
      <!-- Assets Card -->
      <div class="bg-gradient-to-br from-gray-900 to-gray-800 rounded-3xl p-6 text-white shadow-xl relative overflow-hidden group">
        <!-- Decorative background elements -->
        <div class="absolute top-0 right-0 w-64 h-64 bg-white/5 rounded-full -translate-y-1/2 translate-x-1/3 blur-3xl group-hover:bg-white/10 transition duration-700"></div>
        <div class="absolute bottom-0 left-0 w-48 h-48 bg-primary/20 rounded-full translate-y-1/2 -translate-x-1/3 blur-3xl"></div>
        
        <div class="relative z-10">
          <div class="flex justify-between items-start mb-6">
            <div>
              <div class="flex items-center gap-2 text-white/60 text-sm mb-1">
                <span>净资产</span>
                <button @click="showAmount = !showAmount" class="hover:text-white transition">
                  <Eye v-if="showAmount" :size="16" />
                  <EyeOff v-else :size="16" />
                </button>
              </div>
              <div class="text-3xl md:text-4xl font-bold font-nums tracking-tight">
                {{ showAmount ? formatMoney(accountData?.net_assets) : '****' }}
              </div>
            </div>
            <div class="bg-white/10 p-2.5 rounded-xl backdrop-blur-sm border border-white/10">
              <Wallet class="text-white" :size="24" />
            </div>
          </div>

          <div class="grid grid-cols-2 gap-8 pt-4 border-t border-white/10">
            <div>
              <div class="text-white/60 text-xs mb-1">总资产</div>
              <div class="text-lg font-semibold font-nums">
                {{ showAmount ? formatMoney(accountData?.total_assets) : '****' }}
              </div>
            </div>
            <div>
              <div class="text-white/60 text-xs mb-1">总负债</div>
              <div class="text-lg font-semibold font-nums text-red-300">
                {{ showAmount ? formatMoney(accountData?.total_liabilities) : '****' }}
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Quick Account Access -->
      <div v-if="accountData?.list?.length" class="bg-white/60 dark:bg-gray-800/60 backdrop-blur-xl rounded-3xl p-6 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-white/20 dark:border-gray-700/50">
        <div class="flex items-center justify-between mb-3">
          <h3 class="font-bold text-gray-900 dark:text-white text-sm">我的账户</h3>
          <button @click="router.push('/accounts')" class="text-xs text-primary flex items-center gap-1 hover:underline">
            管理 <ChevronRight :size="14" />
          </button>
        </div>
        <div class="flex gap-3 overflow-x-auto pb-1 -mx-1 px-1 scrollbar-hide">
          <div 
            v-for="acc in accountData.list.filter(a => !a.is_archived).slice(0, 6)" 
            :key="acc.id"
            class="flex-shrink-0 w-32 p-3 rounded-xl border border-gray-100 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer transition flex flex-col justify-between h-20"
            @click="router.push('/accounts')"
          >
            <div class="flex justify-between items-start">
              <span class="text-xs text-gray-500 dark:text-gray-400 bg-gray-100 dark:bg-gray-700 px-1.5 py-0.5 rounded">{{ getAccountTypeName(acc.type) }}</span>
            </div>
            <div>
              <div class="text-xs text-gray-900 dark:text-gray-300 font-medium truncate mb-0.5">{{ acc.name }}</div>
              <div class="font-bold text-sm font-nums" :class="acc.current_balance >= 0 ? AMOUNT_COLORS.positive : AMOUNT_COLORS.negative">
                {{ showAmount ? formatMoney(acc.current_balance) : '****' }}
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Monthly Overview -->
      <div class="bg-white/60 dark:bg-gray-800/60 backdrop-blur-xl rounded-3xl p-6 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-white/20 dark:border-gray-700/50">
        <div class="grid grid-cols-3 gap-4">
          <div class="text-center">
            <div class="flex items-center justify-center gap-1 text-xs text-gray-500 dark:text-gray-400 mb-1">
              <span class="w-1.5 h-1.5 rounded-full bg-red-500"></span>
              <span>收入</span>
            </div>
            <div class="font-bold text-red-500 font-nums text-lg">+{{ formatMoney(overview?.income) }}</div>
          </div>
          <div class="text-center">
            <div class="flex items-center justify-center gap-1 text-xs text-gray-500 dark:text-gray-400 mb-1">
              <span class="w-1.5 h-1.5 rounded-full bg-green-500"></span>
              <span>支出</span>
            </div>
            <div class="font-bold text-green-500 font-nums text-lg">-{{ formatMoney(overview?.expense) }}</div>
          </div>
          <div class="text-center">
            <div class="flex items-center justify-center gap-1 text-xs text-gray-500 dark:text-gray-400 mb-1">
              <span class="w-1.5 h-1.5 rounded-full bg-gray-900 dark:bg-white"></span>
              <span>结余</span>
            </div>
            <div class="font-bold font-nums text-lg" :class="(overview?.balance || 0) >= 0 ? AMOUNT_COLORS.positive : AMOUNT_COLORS.negative">
              {{ formatMoney(overview?.balance) }}
            </div>
          </div>
        </div>
      </div>

      <!-- Dashboard Grid: Budget & Debt -->
      <div class="grid md:grid-cols-2 gap-4">
        <!-- Budget Card -->
        <div 
          class="bg-gradient-to-br from-sky-50/80 to-blue-50/80 dark:from-gray-800/80 dark:to-gray-800/80 backdrop-blur-xl rounded-3xl p-6 border border-white/20 dark:border-gray-700/50 cursor-pointer hover:shadow-lg hover:-translate-y-1 transition-all duration-300 relative overflow-hidden group shadow-sm"
          @click="router.push('/budgets')"
        >
          <div class="absolute right-0 top-0 w-32 h-32 bg-sky-100 dark:bg-sky-900/20 rounded-full blur-3xl -translate-y-1/2 translate-x-1/2"></div>
          
          <div class="relative">
            <div class="flex items-center justify-between mb-3">
              <h3 class="font-bold text-gray-900 dark:text-white flex items-center gap-2">
                <span>📊 本月预算</span>
              </h3>
              <span class="text-xs font-bold px-2 py-1 rounded-lg bg-white dark:bg-gray-700 text-sky-600 dark:text-sky-400 shadow-sm">
                {{ budgetSummary?.percentage || 0 }}%
              </span>
            </div>

            <div class="mb-4">
              <div class="flex justify-between text-xs text-gray-500 mb-1.5">
                <span>已用 {{ formatMoney(budgetSummary?.total_spent) }}</span>
                <span>剩余 {{ formatMoney((budgetSummary?.total_amount || 0) - (budgetSummary?.total_spent || 0)) }}</span>
              </div>
              <div class="h-2.5 bg-white dark:bg-gray-700 rounded-full overflow-hidden shadow-inner">
                <div 
                  class="h-full rounded-full transition-all duration-500"
                  :class="{
                    'bg-green-500': (budgetSummary?.percentage || 0) < 80,
                    'bg-yellow-500': (budgetSummary?.percentage || 0) >= 80 && (budgetSummary?.percentage || 0) < 100,
                    'bg-red-500': (budgetSummary?.percentage || 0) >= 100
                  }"
                  :style="{ width: Math.min(budgetSummary?.percentage || 0, 100) + '%' }"
                ></div>
              </div>
            </div>

            <!-- Daily Available & Alerts -->
            <div class="flex items-center justify-between">
              <div v-if="budgetSummary?.daily_available" class="flex items-center gap-2 text-xs">
                <span class="bg-sky-100 dark:bg-sky-900/30 text-sky-600 dark:text-sky-400 px-2 py-1 rounded-lg font-medium">
                  日均可用 ¥{{ budgetSummary.daily_available.toFixed(0) }}
                </span>
                <span class="text-gray-400">剩{{ budgetSummary.days_remaining }}天</span>
              </div>
              <div v-if="budgetSummary?.over_budget_categories?.length" class="flex items-center gap-1 text-xs text-red-500">
                <AlertCircle :size="12" />
                <span>{{ budgetSummary.over_budget_categories[0].name }}超支</span>
              </div>
              <div v-else-if="budgetSummary?.total_amount" class="text-xs text-gray-400 flex items-center gap-1">
                <Check :size="12" class="text-green-500" />
                <span>控制良好</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Debt Card -->
        <div 
          v-if="debtSummary && (debtSummary.total_debt > 0 || debtSummary.total_principal > 0)"
          class="bg-gradient-to-br from-violet-50/80 to-purple-50/80 dark:from-gray-800/80 dark:to-gray-800/80 backdrop-blur-xl rounded-3xl p-6 border border-white/20 dark:border-gray-700/50 cursor-pointer hover:shadow-lg hover:-translate-y-1 transition-all duration-300 relative overflow-hidden shadow-sm"
          @click="router.push('/reminders')"
        >
          <div class="absolute right-0 top-0 w-32 h-32 bg-violet-100 dark:bg-violet-900/20 rounded-full blur-3xl -translate-y-1/2 translate-x-1/2"></div>

          <div class="relative">
            <div class="flex items-center justify-between mb-3">
              <h3 class="font-bold text-gray-900 dark:text-white flex items-center gap-2">
                <span>🎯 上岸进度</span>
              </h3>
              <span class="text-xs font-bold px-2 py-1 rounded-lg bg-white dark:bg-gray-700 text-violet-600 dark:text-violet-400 shadow-sm">
                {{ debtSummary.progress.toFixed(1) }}%
              </span>
            </div>

            <div class="mb-4">
              <div class="flex justify-between text-xs text-gray-500 mb-1.5">
                <span>已还 {{ formatMoney(debtSummary.total_paid) }}</span>
                <span>待还 {{ formatMoney(debtSummary.total_debt) }}</span>
              </div>
              <div class="h-2.5 bg-white dark:bg-gray-700 rounded-full overflow-hidden shadow-inner">
                <div 
                  class="h-full bg-gradient-to-r from-violet-500 to-purple-600 rounded-full transition-all duration-500"
                  :style="{ width: debtSummary.progress + '%' }"
                ></div>
              </div>
            </div>

            <div class="flex items-center justify-between text-xs">
              <div v-if="debtSummary.next_payment_name" class="flex items-center gap-2">
                <span class="bg-violet-100 dark:bg-violet-900/30 text-violet-600 dark:text-violet-400 px-2 py-1 rounded-lg font-medium">
                  {{ debtSummary.days_until_next === 0 ? '今日还款' : debtSummary.days_until_next + '天后还款' }}
                </span>
                <span class="text-gray-500 truncate max-w-[100px]">{{ debtSummary.next_payment_name }}</span>
              </div>
              <div v-else class="text-gray-400">暂无还款计划</div>
              <span class="text-gray-400">共{{ debtSummary.active_loans }}笔</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Lending Summary Card -->
      <div 
        v-if="lendingSummary && (lendingSummary.total_receivable > 0 || lendingSummary.total_payable > 0)"
        class="bg-gradient-to-br from-amber-50/80 to-orange-50/80 dark:from-gray-800/80 dark:to-gray-800/80 backdrop-blur-xl rounded-3xl p-6 border border-white/20 dark:border-gray-700/50 cursor-pointer hover:shadow-lg hover:-translate-y-1 transition-all duration-300 relative overflow-hidden shadow-sm"
        @click="router.push('/lendings')"
      >
        <div class="absolute right-0 top-0 w-32 h-32 bg-amber-100 dark:bg-amber-900/20 rounded-full blur-3xl -translate-y-1/2 translate-x-1/2"></div>

        <div class="relative">
          <div class="flex items-center justify-between mb-3">
            <h3 class="font-bold text-gray-900 dark:text-white flex items-center gap-2">
              <span>💰 借款往来</span>
            </h3>
            <span class="text-xs font-bold px-2 py-1 rounded-lg bg-white dark:bg-gray-700 shadow-sm"
              :class="lendingSummary.net_lending >= 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'">
              {{ lendingSummary.net_lending >= 0 ? '+' : '' }}{{ formatMoney(lendingSummary.net_lending) }}
            </span>
          </div>

          <div class="grid grid-cols-2 gap-4 mb-3">
            <div class="bg-white/60 dark:bg-gray-700/50 rounded-xl p-3">
              <div class="text-xs text-gray-500 dark:text-gray-400 mb-1">应收（别人欠我）</div>
              <div class="font-bold text-orange-600 dark:text-orange-400">{{ formatMoney(lendingSummary.total_receivable) }}</div>
              <div class="text-xs text-gray-400 mt-1">{{ lendingSummary.active_lend_out }} 笔进行中</div>
            </div>
            <div class="bg-white/60 dark:bg-gray-700/50 rounded-xl p-3">
              <div class="text-xs text-gray-500 dark:text-gray-400 mb-1">应付（我欠别人）</div>
              <div class="font-bold text-blue-600 dark:text-blue-400">{{ formatMoney(lendingSummary.total_payable) }}</div>
              <div class="text-xs text-gray-400 mt-1">{{ lendingSummary.active_borrow_in }} 笔进行中</div>
            </div>
          </div>

          <div class="flex items-center justify-between text-xs text-gray-500">
            <span>已结清 {{ lendingSummary.settled_lend_out + lendingSummary.settled_borrow_in }} 笔</span>
            <span class="flex items-center gap-1">
              查看详情 <ChevronRight :size="14" />
            </span>
          </div>
        </div>
      </div>

      <!-- Content Area -->
      <div>
        <!-- View Switcher Tabs -->
        <div class="flex items-center justify-between mb-4">
          <div class="bg-gray-100 dark:bg-gray-800 p-1 rounded-xl inline-flex">
            <button
              class="px-4 py-2 rounded-lg text-sm font-medium transition-all flex items-center gap-2"
              :class="viewMode === 'list' ? 'bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm' : 'text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white'"
              @click="viewMode = 'list'"
            >
              <LayoutList :size="16" />
              <span>列表</span>
            </button>
            <button
              class="px-4 py-2 rounded-lg text-sm font-medium transition-all flex items-center gap-2"
              :class="viewMode === 'calendar' ? 'bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm' : 'text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white'"
              @click="viewMode = 'calendar'"
            >
              <CalendarIcon :size="16" />
              <span>日历</span>
            </button>
          </div>
          
          <button 
            v-if="viewMode === 'list'"
            class="text-sm text-primary flex items-center hover:underline" 
            @click="goToTransactions"
          >
            查看全部 <ChevronRight :size="16" />
          </button>
        </div>

        <!-- List View -->
        <div v-if="viewMode === 'list'" class="bg-white/60 dark:bg-gray-800/60 backdrop-blur-xl rounded-3xl p-4 md:p-6 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-white/20 dark:border-gray-700/50 min-h-[300px]">
          <h3 class="font-bold text-lg mb-4 text-gray-900 dark:text-white">最近交易</h3>
          <div v-if="recentTransactions.length === 0" class="flex flex-col items-center justify-center py-20 text-gray-400">
            <div class="w-20 h-20 bg-gray-50 dark:bg-gray-700 rounded-full flex items-center justify-center mb-4">
              <LayoutList :size="32" class="opacity-50" />
            </div>
            <p>暂无交易记录</p>
          </div>
          <div v-else class="space-y-3">
            <div
              v-for="item in recentTransactions"
              :key="item.id"
              class="flex items-center p-3 rounded-2xl hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer transition border border-transparent hover:border-gray-100 dark:hover:border-gray-600 group"
              @click="editTransaction(item.id)"
            >
              <div
                class="w-12 h-12 rounded-2xl flex items-center justify-center text-2xl mr-4 transition-transform group-hover:scale-110"
                :style="{ backgroundColor: (item.type === 'transfer' ? '#6366F1' : (item.category?.color || '#007AFF')) + '15' }"
              >
                {{ item.type === 'transfer' ? '↔️' : getCategoryIcon(item.category?.icon || '', item.category?.name || '') }}
              </div>
              <div class="flex-1 min-w-0">
                <div class="font-bold text-gray-900 dark:text-white truncate mb-0.5">{{ item.type === 'transfer' ? '转账' : (item.category?.name || '未分类') }}</div>
                <div class="text-xs text-gray-400 truncate flex items-center gap-2">
                  <span>{{ dayjs(item.transaction_date).format('MM-DD HH:mm') }}</span>
                  <span v-if="item.remark" class="w-1 h-1 rounded-full bg-gray-300"></span>
                  <span v-if="item.remark">{{ item.remark }}</span>
                </div>
              </div>
              <div
                class="font-bold text-lg font-nums ml-4"
                :class="item.type === 'transfer' ? AMOUNT_COLORS.transfer : (item.type === 'income' ? AMOUNT_COLORS.income : AMOUNT_COLORS.expense)"
              >
                {{ item.type === 'income' ? '+' : item.type === 'expense' ? '-' : '' }}{{ formatMoney(item.amount) }}
              </div>
            </div>
          </div>
        </div>

        <!-- Calendar View -->
        <div v-else class="space-y-6">
          <CalendarView 
            ref="calendarRef"
            @select="handleDateSelect"
            @month-change="() => {}"
          />

          <!-- Selected Date Transactions -->
          <div class="bg-white/60 dark:bg-gray-800/60 backdrop-blur-xl rounded-3xl p-4 md:p-6 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-white/20 dark:border-gray-700/50">
            <div class="flex items-center justify-between mb-4">
              <h3 class="font-bold text-lg text-gray-800 dark:text-white">
                {{ dayjs(selectedDate).format('M月D日') }}
                <span v-if="isToday" class="text-sm font-normal text-gray-400 ml-2">(今天)</span>
              </h3>
              <div v-if="dateTransactions.length > 0" class="text-sm text-gray-500">
                {{ dateTransactions.length }} 笔交易
              </div>
            </div>

            <div v-if="dateTransactions.length === 0" class="flex flex-col items-center justify-center py-8 text-gray-400">
              <p>该日无交易记录</p>
              <button 
                class="mt-3 text-primary text-sm font-medium hover:underline"
                @click="addTransaction"
              >
                记一笔
              </button>
            </div>

            <div v-else class="space-y-3">
              <div
                v-for="item in dateTransactions"
                :key="item.id"
                class="flex items-center p-3 rounded-2xl hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer transition border border-transparent hover:border-gray-100 dark:hover:border-gray-600"
                @click="editTransaction(item.id)"
              >
                <div
                  class="w-10 h-10 rounded-2xl flex items-center justify-center text-xl mr-3"
                  :style="{ backgroundColor: (item.type === 'transfer' ? '#6366F1' : (item.category?.color || '#007AFF')) + '15' }"
                >
                  {{ item.type === 'transfer' ? '↔️' : getCategoryIcon(item.category?.icon || '', item.category?.name || '') }}
                </div>
                <div class="flex-1 min-w-0">
                  <div class="font-medium text-gray-900 dark:text-white">{{ item.type === 'transfer' ? '转账' : (item.category?.name || '未分类') }}</div>
                  <div class="text-xs text-gray-400">{{ item.remark || item.account?.name }}</div>
                </div>
                <div
                  class="font-bold font-nums"
                  :class="item.type === 'transfer' ? AMOUNT_COLORS.transfer : (item.type === 'income' ? AMOUNT_COLORS.income : AMOUNT_COLORS.expense)"
                >
                  {{ item.type === 'income' ? '+' : item.type === 'expense' ? '-' : '' }}{{ formatMoney(item.amount) }}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Transaction Dialog -->
    <TransactionDialog
      v-model:visible="showDialog"
      :edit-id="editingId"
      @success="onTransactionSuccess"
    />
  </div>
</template>
