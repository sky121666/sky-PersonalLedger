<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronLeft, Download } from 'lucide-vue-next'
import { exportApi, type YearlyReport } from '@/api/export'
import { statisticsApi, type AssetTrendItem } from '@/api/statistics'
import { toast } from '@/composables/useToast'
import DynamicIcon from '@/components/DynamicIcon.vue'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { createRequestGeneration } from '@/utils/requestGeneration'

const router = useRouter()

const loading = ref(false)
const exporting = ref(false)
const selectedYear = ref(new Date().getFullYear())
const availableYears = ref<number[]>([])
const report = ref<YearlyReport | null>(null)
const assetTrendData = ref<AssetTrendItem[]>([])
const currentNetWorth = ref(0)
const ledgerMutationRevision = useLedgerMutationRevision()
const reportRequests = createRequestGeneration()

onMounted(async () => {
  await loadYears()
  await loadReport()
})

watch(ledgerMutationRevision, () => void loadReport())

async function loadYears() {
  try {
    const years = await exportApi.getAvailableYears()
    availableYears.value = years.length > 0 ? years : [new Date().getFullYear()]
  } catch (e) {
    availableYears.value = [new Date().getFullYear()]
  }
}

async function loadReport() {
  const requestGeneration = reportRequests.begin()
  const requestedYear = selectedYear.value
  loading.value = true
  try {
    const [reportData, assetTrend] = await Promise.all([
      exportApi.getYearlyReport(requestedYear),
      statisticsApi.getAssetTrend(12)
    ])
    if (
      !reportRequests.isLatest(requestGeneration)
      || selectedYear.value !== requestedYear
    ) return
    report.value = reportData
    assetTrendData.value = assetTrend.items
    currentNetWorth.value = assetTrend.current_net_worth
  } catch (e: any) {
    if (reportRequests.isLatest(requestGeneration)) {
      toast.error('加载报告失败')
    }
  } finally {
    if (reportRequests.isLatest(requestGeneration)) {
      loading.value = false
    }
  }
}

async function handleExportCSV() {
  exporting.value = true
  try {
    await exportApi.downloadCSV({
      start_date: `${selectedYear.value}-01-01`,
      end_date: `${selectedYear.value}-12-31`
    })
    toast.success('导出成功')
  } catch (e: any) {
    toast.error('导出失败')
  } finally {
    exporting.value = false
  }
}

function formatMoney(value: number | undefined) {
  if (value === undefined) return '0'
  return value.toLocaleString('zh-CN', { minimumFractionDigits: 0, maximumFractionDigits: 0 })
}

const maxMonthlyAmount = computed(() => {
  if (!report.value) return 1
  return Math.max(...report.value.monthly_data.map(m => Math.max(m.expense, m.income)), 1)
})

const maxNetWorth = computed(() => {
  if (assetTrendData.value.length === 0) return 0
  const nonZeroValues = assetTrendData.value.filter(item => Math.abs(item.net_worth) > 0.01)
  if (nonZeroValues.length === 0) return 0
  return Math.max(...nonZeroValues.map(item => Math.abs(item.net_worth)))
})

function getNetWorthHeight(value: number) {
  if (Math.abs(value) < 0.01) return 0
  if (maxNetWorth.value === 0) return 0
  return (Math.abs(value) / maxNetWorth.value) * 100
}

function getMonthLabel(monthStr: string) {
  const month = parseInt(monthStr.split('-')[1])
  return month + '月'
}
</script>

<template>
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black text-gray-900 dark:text-white">
    <!-- Header -->
    <div class="bg-white/80 dark:bg-[#1C1C1E]/80 pt-4 pb-4 px-4 md:px-8 sticky top-0 z-30 backdrop-blur-xl border-b border-gray-200/50 dark:border-white/10">
      <div class="max-w-3xl mx-auto flex items-center justify-between">
        <div class="flex items-center gap-2 min-w-0">
          <button @click="router.back()" class="p-2 -ml-2 text-gray-400 hover:text-gray-600 dark:hover:text-white rounded-xl transition flex-shrink-0">
            <ChevronLeft :size="20" />
          </button>
          <h1 class="text-lg font-semibold text-gray-900 dark:text-white truncate">年度报告</h1>
        </div>
        <div class="flex items-center gap-1 flex-shrink-0">
          <select 
            v-model="selectedYear" 
            @change="loadReport"
            class="px-2 py-1.5 bg-gray-100 dark:bg-white/10 rounded-lg text-sm font-medium border-0 outline-none"
          >
            <option v-for="year in availableYears" :key="year" :value="year" class="bg-white dark:bg-gray-900">{{ year }}年</option>
          </select>
          <button 
            @click="handleExportCSV" 
            :disabled="exporting"
            class="p-2 text-gray-400 hover:text-gray-600 dark:hover:text-white transition disabled:opacity-50"
          >
            <Download :size="18" />
          </button>
        </div>
      </div>
    </div>

    <div v-if="loading" class="flex items-center justify-center min-h-[60vh]">
      <div class="w-8 h-8 border-2 border-gray-200 dark:border-white/20 border-t-gray-900 dark:border-t-white rounded-full animate-spin"></div>
    </div>

    <div v-else-if="report" class="max-w-3xl mx-auto px-4 md:px-8 py-6 space-y-4">
      <!-- Hero Section -->
      <div class="relative bg-gradient-to-br from-indigo-500 via-purple-500 to-pink-500 rounded-3xl p-5 sm:p-8 text-white overflow-hidden">
        <div class="absolute top-0 right-0 w-64 h-64 bg-white/10 rounded-full -translate-y-1/2 translate-x-1/3 blur-3xl"></div>
        <div class="absolute bottom-0 left-0 w-48 h-48 bg-white/10 rounded-full translate-y-1/2 -translate-x-1/3 blur-3xl"></div>
        <div class="relative text-center">
          <div class="text-5xl sm:text-7xl font-black mb-2">{{ selectedYear }}</div>
          <div class="text-white/80 text-sm mb-4 sm:mb-6">年度财务总结</div>
          <div class="grid grid-cols-3 gap-2 sm:gap-4 mt-4 sm:mt-6">
            <div class="bg-white/10 backdrop-blur rounded-xl sm:rounded-2xl p-2.5 sm:p-4">
              <div class="text-white/60 text-[10px] sm:text-xs mb-0.5 sm:mb-1">总收入</div>
              <div class="text-sm sm:text-xl font-bold font-nums truncate">¥{{ formatMoney(report.total_income) }}</div>
            </div>
            <div class="bg-white/10 backdrop-blur rounded-xl sm:rounded-2xl p-2.5 sm:p-4">
              <div class="text-white/60 text-[10px] sm:text-xs mb-0.5 sm:mb-1">总支出</div>
              <div class="text-sm sm:text-xl font-bold font-nums truncate">¥{{ formatMoney(report.total_expense) }}</div>
            </div>
            <div class="bg-white/10 backdrop-blur rounded-xl sm:rounded-2xl p-2.5 sm:p-4">
              <div class="text-white/60 text-[10px] sm:text-xs mb-0.5 sm:mb-1">净结余</div>
              <div class="text-sm sm:text-xl font-bold font-nums truncate">{{ report.net_savings >= 0 ? '+' : '' }}¥{{ formatMoney(report.net_savings) }}</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Asset Trend -->
      <div class="bg-white dark:bg-[#1C1C1E] rounded-3xl p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-bold text-gray-900 dark:text-white">📈 资产趋势</h3>
          <div class="text-right">
            <div class="text-xs text-gray-400">当前净资产</div>
            <div class="text-lg font-bold font-nums" :class="currentNetWorth >= 0 ? 'text-emerald-500' : 'text-red-500'">
              ¥{{ formatMoney(currentNetWorth) }}
            </div>
          </div>
        </div>
        <div v-if="assetTrendData.length === 0" class="py-8 text-center text-gray-400 text-sm">
          暂无数据
        </div>
        <div v-else class="h-36 flex items-end gap-1.5">
          <div 
            v-for="item in assetTrendData" 
            :key="item.month" 
            class="flex-1 flex flex-col items-center gap-1 group relative"
          >
            <!-- Tooltip -->
            <div class="absolute -top-8 left-1/2 -translate-x-1/2 px-2 py-1 bg-gray-900 dark:bg-white text-white dark:text-gray-900 text-[10px] rounded opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap z-10 pointer-events-none font-medium">
              {{ item.net_worth >= 0 ? '' : '-' }}¥{{ formatMoney(Math.abs(item.net_worth)) }}
            </div>
            <div class="w-full h-28 flex items-end justify-center">
              <div 
                v-if="Math.abs(item.net_worth) > 0.01"
                class="w-full rounded-t transition-all duration-300 group-hover:scale-105 cursor-pointer"
                :class="item.net_worth > 0 ? 'bg-gradient-to-t from-emerald-500 to-emerald-400' : 'bg-gradient-to-t from-red-500 to-red-400'"
                :style="{ height: `${Math.max(getNetWorthHeight(item.net_worth), 8)}%` }"
              ></div>
              <div 
                v-else
                class="w-full h-0.5 bg-gray-300 dark:bg-gray-600 rounded"
              ></div>
            </div>
            <span class="text-[9px] text-gray-400 font-medium">{{ getMonthLabel(item.month) }}</span>
          </div>
        </div>
        <div class="flex items-center justify-center gap-4 mt-3 text-xs text-gray-500">
          <div class="flex items-center gap-1.5">
            <div class="w-3 h-3 bg-gradient-to-t from-emerald-500 to-emerald-400 rounded"></div>
            <span>正资产</span>
          </div>
          <div class="flex items-center gap-1.5">
            <div class="w-3 h-3 bg-gradient-to-t from-red-500 to-red-400 rounded"></div>
            <span>负资产</span>
          </div>
        </div>
      </div>

      <!-- Monthly Trend -->
      <div class="bg-white dark:bg-[#1C1C1E] rounded-3xl p-6">
        <h3 class="font-bold text-gray-900 dark:text-white mb-4">📊 月度收支</h3>
        <div class="space-y-3">
          <div v-for="(month, index) in report.monthly_data" :key="index" class="group">
            <div class="flex items-center gap-3">
              <div class="w-8 text-xs text-gray-500 font-medium">{{ month.month }}月</div>
              <div class="flex-1 h-7 flex gap-0.5 bg-gray-50 dark:bg-gray-800 rounded-lg overflow-hidden p-0.5">
                <div 
                  class="h-full bg-gradient-to-r from-blue-500 to-cyan-400 rounded transition-all"
                  :style="{ width: Math.max((month.income / maxMonthlyAmount * 100), 0) + '%' }"
                ></div>
                <div 
                  class="h-full bg-gradient-to-r from-orange-400 to-pink-500 rounded transition-all"
                  :style="{ width: Math.max((month.expense / maxMonthlyAmount * 100), 0) + '%' }"
                ></div>
              </div>
            </div>
          </div>
          <div class="flex items-center gap-4 pt-3 text-xs text-gray-500">
            <div class="flex items-center gap-1.5">
              <div class="w-3 h-3 bg-gradient-to-r from-blue-500 to-cyan-400 rounded"></div>
              <span>收入</span>
            </div>
            <div class="flex items-center gap-1.5">
              <div class="w-3 h-3 bg-gradient-to-r from-orange-400 to-pink-500 rounded"></div>
              <span>支出</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Categories Grid -->
      <div class="grid md:grid-cols-2 gap-4">
        <!-- Top Expenses -->
        <div class="bg-white dark:bg-[#1C1C1E] rounded-3xl p-6">
          <h3 class="font-bold text-gray-900 dark:text-white mb-4">💸 支出分类</h3>
          <div class="space-y-3">
            <div v-for="(cat, index) in report.top_expenses.slice(0, 5)" :key="cat.category_id" class="flex items-center gap-3">
              <div class="w-8 h-8 rounded-xl flex items-center justify-center text-lg" 
                :class="index === 0 ? 'bg-orange-100 dark:bg-orange-900/30' : 'bg-gray-100 dark:bg-gray-800'">
                <DynamicIcon :icon="cat.category_icon || '📦'" :size="18" />
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-center justify-between mb-1">
                  <span class="text-sm font-medium text-gray-700 dark:text-gray-300 truncate">{{ cat.category_name }}</span>
                  <span class="text-sm font-bold text-gray-900 dark:text-white ml-2">¥{{ formatMoney(cat.amount) }}</span>
                </div>
                <div class="h-1.5 bg-gray-100 dark:bg-gray-800 rounded-full overflow-hidden">
                  <div class="h-full bg-gradient-to-r from-orange-400 to-pink-500 rounded-full" :style="{ width: cat.percentage + '%' }"></div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Top Incomes -->
        <div class="bg-white dark:bg-[#1C1C1E] rounded-3xl p-6">
          <h3 class="font-bold text-gray-900 dark:text-white mb-4">💰 收入来源</h3>
          <div v-if="report.top_incomes.length === 0" class="flex items-center justify-center h-40 text-gray-400 text-sm">
            暂无收入数据
          </div>
          <div v-else class="space-y-3">
            <div v-for="(cat, index) in report.top_incomes.slice(0, 5)" :key="cat.category_id" class="flex items-center gap-3">
              <div class="w-8 h-8 rounded-xl flex items-center justify-center text-lg"
                :class="index === 0 ? 'bg-emerald-100 dark:bg-emerald-900/30' : 'bg-gray-100 dark:bg-gray-800'">
                <DynamicIcon :icon="cat.category_icon || '💵'" :size="18" />
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-center justify-between mb-1">
                  <span class="text-sm font-medium text-gray-700 dark:text-gray-300 truncate">{{ cat.category_name }}</span>
                  <span class="text-sm font-bold text-gray-900 dark:text-white ml-2">¥{{ formatMoney(cat.amount) }}</span>
                </div>
                <div class="h-1.5 bg-gray-100 dark:bg-gray-800 rounded-full overflow-hidden">
                  <div class="h-full bg-gradient-to-r from-emerald-400 to-cyan-500 rounded-full" :style="{ width: cat.percentage + '%' }"></div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Stats Cards -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div class="bg-gradient-to-br from-violet-500 to-purple-600 rounded-2xl p-4 text-white">
          <div class="text-3xl font-bold">{{ report.transaction_count }}</div>
          <div class="text-white/70 text-xs mt-1">笔交易</div>
        </div>
        <div class="bg-gradient-to-br from-cyan-500 to-blue-600 rounded-2xl p-4 text-white">
          <div class="text-3xl font-bold">{{ report.active_days }}</div>
          <div class="text-white/70 text-xs mt-1">活跃天数</div>
        </div>
        <div class="bg-gradient-to-br from-amber-500 to-orange-600 rounded-2xl p-4 text-white">
          <div class="text-xl font-bold font-nums">¥{{ formatMoney(report.average_expense) }}</div>
          <div class="text-white/70 text-xs mt-1">月均支出</div>
        </div>
        <div class="bg-gradient-to-br from-emerald-500 to-teal-600 rounded-2xl p-4 text-white">
          <div class="text-xl font-bold font-nums">¥{{ formatMoney(report.average_income) }}</div>
          <div class="text-white/70 text-xs mt-1">月均收入</div>
        </div>
      </div>

      <!-- Highlights -->
      <div class="bg-white dark:bg-[#1C1C1E] rounded-3xl p-6">
        <h3 class="font-bold text-gray-900 dark:text-white mb-4">🏆 年度亮点</h3>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div class="bg-red-50 dark:bg-red-900/20 rounded-2xl p-4 text-center">
            <div class="text-2xl mb-1">🔥</div>
            <div class="text-xl font-bold text-red-500">{{ report.max_expense_month || '-' }}</div>
            <div class="text-xs text-gray-500 mt-1">花钱最多</div>
          </div>
          <div class="bg-green-50 dark:bg-green-900/20 rounded-2xl p-4 text-center">
            <div class="text-2xl mb-1">💚</div>
            <div class="text-xl font-bold text-green-500">{{ report.min_expense_month || '-' }}</div>
            <div class="text-xs text-gray-500 mt-1">花钱最少</div>
          </div>
          <div class="bg-yellow-50 dark:bg-yellow-900/20 rounded-2xl p-4 text-center">
            <div class="text-2xl mb-1">⭐</div>
            <div class="text-xl font-bold text-yellow-500">{{ report.best_savings_month || '-' }}</div>
            <div class="text-xs text-gray-500 mt-1">最佳结余</div>
          </div>
          <div v-if="report.max_single_expense > 0" class="bg-purple-50 dark:bg-purple-900/20 rounded-2xl p-4 text-center">
            <div class="text-2xl mb-1">💎</div>
            <div class="text-lg font-bold text-purple-500 font-nums">¥{{ formatMoney(report.max_single_expense) }}</div>
            <div class="text-xs text-gray-500 mt-1">最大单笔</div>
          </div>
        </div>
      </div>

      <!-- Footer -->
      <div class="text-center py-8">
        <div class="text-xs text-gray-400 dark:text-gray-600">Personal Ledger · {{ selectedYear }}</div>
      </div>
    </div>
  </div>
</template>
