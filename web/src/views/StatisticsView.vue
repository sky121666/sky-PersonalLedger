<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { ChevronLeft, ChevronRight, PieChart } from 'lucide-vue-next'
import { statisticsApi, type OverviewResponse, type CategoryStatItem, type TrendItem } from '@/api/statistics'
import { toast } from '@/composables/useToast'
import { getCategoryEmoji } from '@/utils/constants'
import dayjs from 'dayjs'

const overview = ref<OverviewResponse | null>(null)
const categoryStats = ref<CategoryStatItem[]>([])
const trendData = ref<TrendItem[]>([])
const selectedMonth = ref(dayjs().format('YYYY-MM'))
const statsType = ref<'expense' | 'income'>('expense')
const loading = ref(false)

const currentMonthDisplay = computed(() => {
  return dayjs(selectedMonth.value).format('YYYY年M月')
})

const maxTrendAmount = computed(() => {
  if (trendData.value.length === 0) return 0
  return Math.max(...trendData.value.map(item => Math.max(item.expense, item.income)))
})

// Pie chart gradient for CSS
const pieGradient = computed(() => {
  if (categoryStats.value.length === 0) return 'conic-gradient(#e5e7eb 0% 100%)'
  let gradient = 'conic-gradient('
  let accumulated = 0
  categoryStats.value.forEach((item, index) => {
    const start = accumulated
    accumulated += item.percentage
    const color = item.color || '#94a3b8'
    if (index > 0) gradient += ', '
    gradient += `${color} ${start}% ${accumulated}%`
  })
  gradient += ')'
  return gradient
})

const categoryTotal = computed(() => {
  return categoryStats.value.reduce((s, i) => s + i.amount, 0)
})

onMounted(() => {
  loadData()
})

watch([selectedMonth, statsType], () => {
  loadData()
})

async function loadData() {
  loading.value = true
  try {
    const [ov, stats, trend] = await Promise.all([
      statisticsApi.getOverview(selectedMonth.value),
      statisticsApi.getCategoryStats(selectedMonth.value, statsType.value),
      statisticsApi.getTrend(selectedMonth.value)
    ])
    overview.value = ov
    categoryStats.value = stats.items
    trendData.value = trend.items
  } catch (e: any) {
    toast.error('加载统计数据失败')
  } finally {
    loading.value = false
  }
}

function prevMonth() {
  selectedMonth.value = dayjs(selectedMonth.value).subtract(1, 'month').format('YYYY-MM')
}

function nextMonth() {
  const next = dayjs(selectedMonth.value).add(1, 'month')
  if (next.isBefore(dayjs().add(1, 'month'), 'month')) {
    selectedMonth.value = next.format('YYYY-MM')
  }
}

function formatMoney(value: number | undefined) {
  if (value === undefined) return '0.00'
  return value.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

function getDayLabel(dateStr: string) {
  return dayjs(dateStr).format('D')
}
</script>

<template>
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black pb-8">
    <!-- Header -->
    <div class="bg-white/70 dark:bg-[#1C1C1E]/70 pt-4 pb-4 px-4 md:px-8 sticky top-0 z-30 backdrop-blur-xl border-b border-gray-200/50 dark:border-white/10">
      <div class="max-w-3xl mx-auto flex items-center justify-between">
        <div class="flex items-center gap-4">
          <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-cyan-500 to-cyan-600 flex items-center justify-center shadow-lg shadow-cyan-500/20">
            <PieChart class="text-white" :size="28" />
          </div>
          <div>
            <h1 class="text-xl font-bold text-gray-900 dark:text-white">统计分析</h1>
            <div class="text-sm text-gray-500 dark:text-gray-400 mt-0.5">{{ currentMonthDisplay }}</div>
          </div>
        </div>
        <!-- Month Selector -->
        <div class="flex items-center gap-1 bg-gray-100/50 dark:bg-white/5 p-0.5 rounded-full">
          <button
            class="w-8 h-8 flex items-center justify-center rounded-full hover:bg-white dark:hover:bg-gray-600 hover:shadow-sm transition-all text-gray-500 hover:text-gray-900 dark:hover:text-white"
            @click="prevMonth"
          >
            <ChevronLeft :size="16" />
          </button>
          <button
            class="w-8 h-8 flex items-center justify-center rounded-full hover:bg-white dark:hover:bg-gray-600 hover:shadow-sm transition-all text-gray-500 hover:text-gray-900 dark:hover:text-white"
            @click="nextMonth"
          >
            <ChevronRight :size="16" />
          </button>
        </div>
      </div>
    </div>

    <div class="max-w-3xl mx-auto px-4 md:px-8 py-6 space-y-6">
      <!-- Main Summary Card -->
      <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-[24px] p-6 shadow-sm border border-white/40 dark:border-white/5">
        <div class="flex flex-col items-center justify-center text-center py-2">
          <div class="text-sm text-gray-500 dark:text-gray-400 mb-2 font-medium">本月总支出</div>
          <div class="text-[40px] font-bold text-gray-900 dark:text-white font-nums tracking-tight leading-none mb-8">
            <span class="text-2xl align-top opacity-60 mr-1">¥</span>{{ formatMoney(overview?.expense) }}
          </div>
          
          <div class="flex items-center gap-12 w-full justify-center">
            <div class="text-center">
              <div class="text-xs text-gray-400 mb-1">本月收入</div>
              <div class="text-lg font-semibold font-nums text-red-500">
                <span class="text-xs opacity-60">¥</span> {{ formatMoney(overview?.income) }}
              </div>
            </div>
            <div class="w-px h-8 bg-gray-200 dark:bg-gray-700"></div>
            <div class="text-center">
              <div class="text-xs text-gray-400 mb-1">本月结余</div>
              <div class="text-lg font-semibold font-nums text-gray-900 dark:text-white">
                <span class="text-xs opacity-60">¥</span> {{ formatMoney(overview?.balance) }}
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Trend Chart -->
      <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-[24px] p-5 shadow-sm border border-white/40 dark:border-white/5 overflow-hidden">
        <div class="flex items-center gap-2 mb-6 px-1">
          <div class="w-1 h-4 bg-primary rounded-full"></div>
          <h3 class="font-bold text-gray-900 dark:text-white text-sm">收支趋势</h3>
        </div>
        
        <div class="h-40 flex items-end gap-2 overflow-x-auto pb-2 scrollbar-hide px-1">
          <div 
            v-for="item in trendData" 
            :key="item.date" 
            class="flex flex-col items-center gap-2 flex-shrink-0 group"
            style="width: 20px"
          >
            <div class="relative w-full h-32 flex items-end rounded-full bg-gray-100/50 dark:bg-gray-800/50">
              <!-- Expense Bar (Green) -->
              <div 
                v-if="item.expense > 0"
                class="absolute bottom-0 inset-x-0 mx-auto w-full bg-black dark:bg-white rounded-t-full opacity-80"
                :style="{ height: `${(item.expense / maxTrendAmount) * 100}%` }"
              ></div>
              <!-- Income Bar (Red - Optional, overlay or separate? Standard is usually separate bars or overlay. Let's stick to expense focus for now or overlay income lightly) -->
            </div>
            <span class="text-[9px] text-gray-400 font-nums">{{ getDayLabel(item.date) }}</span>
          </div>
        </div>
      </div>

      <!-- Category Analysis -->
      <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-[24px] p-6 shadow-sm border border-white/40 dark:border-white/5">
        <div class="flex items-center justify-between mb-8">
          <div class="flex items-center gap-2">
            <div class="w-1 h-4 bg-primary rounded-full"></div>
            <h3 class="font-bold text-gray-900 dark:text-white text-sm">分类排行</h3>
          </div>
          
          <div class="flex bg-gray-100 dark:bg-gray-800 p-0.5 rounded-lg">
            <button
              class="px-3 py-1 text-xs font-medium rounded-[6px] transition-all"
              :class="statsType === 'expense' ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-white shadow-sm' : 'text-gray-500'"
              @click="statsType = 'expense'"
            >
              支出
            </button>
            <button
              class="px-3 py-1 text-xs font-medium rounded-[6px] transition-all"
              :class="statsType === 'income' ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-white shadow-sm' : 'text-gray-500'"
              @click="statsType = 'income'"
            >
              收入
            </button>
          </div>
        </div>

        <div v-if="categoryStats.length === 0" class="py-10 text-center text-gray-400">
          <p class="text-xs">本月暂无数据</p>
        </div>

        <div v-else class="flex flex-col gap-8">
          <!-- Donut Chart -->
          <div class="flex justify-center relative">
             <!-- Outer Ring -->
            <div 
              class="w-48 h-48 rounded-full shadow-lg relative transition-all duration-500"
              :style="{ background: pieGradient }"
            >
              <!-- Inner Hole -->
              <div class="absolute inset-5 bg-white dark:bg-[#2C2C2E] rounded-full flex items-center justify-center flex-col shadow-inner">
                <div class="text-xs text-gray-400 mb-1">总计</div>
                <div class="text-xl font-bold text-gray-900 dark:text-white font-nums">
                  ¥{{ formatMoney(categoryTotal) }}
                </div>
              </div>
            </div>
          </div>

          <!-- List -->
          <div class="space-y-4">
            <div v-for="item in categoryStats" :key="item.category_id" class="group">
              <div class="flex items-center justify-between mb-2">
                <div class="flex items-center gap-3">
                  <div 
                    class="w-9 h-9 rounded-full flex items-center justify-center text-lg bg-gray-50 dark:bg-gray-800"
                    :style="{ color: item.color }"
                  >
                    {{ getCategoryEmoji(item.category_name, item.icon) }}
                  </div>
                  <div>
                    <div class="font-medium text-gray-900 dark:text-white text-sm">{{ item.category_name }}</div>
                    <div class="text-xs text-gray-400 font-nums">{{ item.percentage.toFixed(1) }}%</div>
                  </div>
                </div>
                <div class="font-bold text-gray-900 dark:text-white font-nums">
                  ¥{{ formatMoney(item.amount) }}
                </div>
              </div>
              <!-- Progress Bar -->
              <div class="h-1.5 w-full bg-gray-100 dark:bg-gray-800 rounded-full overflow-hidden">
                <div 
                  class="h-full rounded-full transition-all duration-700 ease-out"
                  :style="{ 
                    width: `${item.percentage}%`,
                    backgroundColor: item.color || '#94a3b8'
                  }"
                ></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
</style>
