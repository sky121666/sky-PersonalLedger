<script setup lang="ts">
import { ref, computed, watch, onBeforeUnmount } from 'vue'
import dayjs from 'dayjs'
import 'dayjs/locale/zh-cn'
import { ChevronLeft, ChevronRight } from '@lucide/vue'
import { statisticsApi, type TrendItem } from '@/api/statistics'

import { createRequestGeneration } from '@/utils/requestGeneration'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'

dayjs.locale('zh-cn')

const props = defineProps<{
  hideAmounts?: boolean
  initialDate?: string // YYYY-MM
  preview?: boolean
}>()

const emit = defineEmits<{
  (e: 'select', date: string): void
  (e: 'month-change', month: string): void
}>()

const currentDate = ref(dayjs(props.initialDate || undefined))
const trendData = ref<TrendItem[]>([])
const loading = ref(false)
const loadFailed = ref(false)
const loadedMonth = ref('')
const requests = createRequestGeneration()
const ledgerMutationRevision = useLedgerMutationRevision()
onBeforeUnmount(() => requests.begin())
const selectedDate = ref(dayjs().format('YYYY-MM-DD'))

const weekDays = ['日', '一', '二', '三', '四', '五', '六']

const calendarDays = computed(() => {
  const startOfMonth = currentDate.value.startOf('month')
  const endOfMonth = currentDate.value.endOf('month')
  const startDayOfWeek = startOfMonth.day()
  
  const days = []
  
  // Previous month days
  for (let i = startDayOfWeek; i > 0; i--) {
    const d = startOfMonth.subtract(i, 'day')
    const dateStr = d.format('YYYY-MM-DD')
    days.push({
      date: d,
      dateStr,
      isCurrentMonth: false,
      isToday: d.isSame(dayjs(), 'day'),
      isSelected: dateStr === selectedDate.value,
      data: getDayData(dateStr)
    })
  }
  
  // Current month days
  for (let i = 0; i < endOfMonth.date(); i++) {
    const d = startOfMonth.add(i, 'day')
    const dateStr = d.format('YYYY-MM-DD')
    days.push({
      date: d,
      dateStr,
      isCurrentMonth: true,
      isToday: d.isSame(dayjs(), 'day'),
      isSelected: dateStr === selectedDate.value,
      data: getDayData(dateStr)
    })
  }
  
  // Next month days to fill grid (42 cells for 6 rows)
  const remaining = 42 - days.length
  for (let i = 1; i <= remaining; i++) {
    const d = endOfMonth.add(i, 'day')
    const dateStr = d.format('YYYY-MM-DD')
    days.push({
      date: d,
      dateStr,
      isCurrentMonth: false,
      isToday: d.isSame(dayjs(), 'day'),
      isSelected: dateStr === selectedDate.value,
      data: getDayData(dateStr)
    })
  }
  
  return days
})

function getDayData(dateStr: string) {
  return trendData.value.find(item => item.date === dateStr)
}

async function loadData(): Promise<'success' | 'failed' | 'stale'> {
  const month = currentDate.value.format('YYYY-MM')
  if (props.preview) {
    trendData.value = [
      { date: `${month}-20`, income: 8000, expense: 36, balance: 7964 },
      { date: `${month}-18`, income: 0, expense: 128, balance: -128 },
    ]
    loadedMonth.value = month
    return 'success'
  }
  const generation = requests.begin()
  loading.value = true
  loadFailed.value = false
  if (loadedMonth.value !== month) trendData.value = []
  try {
    const res = await statisticsApi.getTrend(month)
    if (!requests.isLatest(generation) || currentDate.value.format('YYYY-MM') !== month) return 'stale'
    trendData.value = res.items
    loadedMonth.value = month
    return 'success'
  } catch {
    if (!requests.isLatest(generation)) return 'stale'
    loadFailed.value = true
    return 'failed'
  } finally {
    if (requests.isLatest(generation)) loading.value = false
  }
}

function prevMonth() {
  currentDate.value = currentDate.value.subtract(1, 'month')
  emit('month-change', currentDate.value.format('YYYY-MM'))
}

function nextMonth() {
  currentDate.value = currentDate.value.add(1, 'month')
  emit('month-change', currentDate.value.format('YYYY-MM'))
}

function previousMonthLabel() {
  return `上个月，${currentDate.value.subtract(1, 'month').format('YYYY年M月')}`
}

function nextMonthLabel() {
  return `下个月，${currentDate.value.add(1, 'month').format('YYYY年M月')}`
}

function selectDate(date: dayjs.Dayjs) {
  selectedDate.value = date.format('YYYY-MM-DD')
  emit('select', selectedDate.value)
  
  // Auto switch month if clicked on prev/next month day
  if (!date.isSame(currentDate.value, 'month')) {
    currentDate.value = date
    emit('month-change', currentDate.value.format('YYYY-MM'))
  }
}

function formatMoney(val: number) {
  if (val >= 10000) {
    return (val / 10000).toFixed(1) + 'w'
  }
  if (val >= 1000) {
    return (val / 1000).toFixed(1) + 'k'
  }
  return val.toFixed(0)
}

watch(ledgerMutationRevision, () => void loadData())

watch(() => currentDate.value.format('YYYY-MM'), () => {
  loadData()
}, { immediate: true })

defineExpose({
  loadData
})
</script>

<template>
  <div class="bg-white/60 dark:bg-gray-800/60 backdrop-blur-xl rounded-3xl p-5 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-white/20 dark:border-gray-700/50">
    <!-- Header -->
    <div class="flex items-center justify-between mb-5">
      <div class="flex items-center gap-3">
        <h2 class="calendar-heading">{{ currentDate.format('YYYY年M月') }}</h2>
      </div>
      <div class="calendar-nav">
        <button
          type="button"
          class="calendar-nav-button"
          :aria-label="previousMonthLabel()"
          :title="previousMonthLabel()"
          @click="prevMonth"
        >
          <ChevronLeft :size="20" />
        </button>
        <button
          type="button"
          class="calendar-nav-button"
          :aria-label="nextMonthLabel()"
          :title="nextMonthLabel()"
          @click="nextMonth"
        >
          <ChevronRight :size="20" />
        </button>
      </div>
    </div>

    <div v-if="loadFailed" role="alert" class="mb-3 text-sm text-amber-700">
      {{ currentDate.format('YYYY年M月') }}金额加载失败，{{ loadedMonth === currentDate.format('YYYY-MM') ? '显示上次结果。' : '尚无可用结果。' }}
      <button class="underline" @click="loadData">重试</button>
    </div>
    <div v-if="loading" class="mb-3 text-sm text-gray-500">正在加载日历金额…</div>
    <!-- Week Header -->
    <div class="grid grid-cols-7 mb-3">
      <div 
        v-for="(day, index) in weekDays" 
        :key="day" 
        class="text-center text-xs font-semibold py-2"
        :class="index === 0 || index === 6 ? 'text-gray-400 dark:text-gray-500' : 'text-gray-500 dark:text-gray-400'"
      >
        {{ day }}
      </div>
    </div>

    <!-- Days Grid -->
    <div class="grid grid-cols-7">
      <div
        v-for="day in calendarDays"
        :key="day.dateStr"
        class="calendar-day py-2 flex flex-col items-center cursor-pointer transition-colors rounded-xl hover:bg-white/40 dark:hover:bg-gray-700/40"
        :class="[
          day.isCurrentMonth 
            ? 'text-gray-900 dark:text-white' 
            : 'text-gray-300 dark:text-gray-600',
        ]"
        @click="selectDate(day.date)"
      >
        <!-- Date number -->
        <span 
          class="w-8 h-8 flex items-center justify-center text-sm font-medium rounded-full transition-colors"
          :class="[
            day.isSelected 
              ? 'bg-primary text-white' 
              : '',
            day.isToday && !day.isSelected 
              ? 'bg-primary/15 text-primary font-semibold' 
              : ''
          ]"
        >
          {{ day.date.date() }}
        </span>
        
        <!-- Income/Expense amounts -->
        <div 
          v-if="day.data && day.isCurrentMonth && (day.data.income > 0 || day.data.expense > 0)" 
          class="flex flex-col items-center mt-1 space-y-0"
        >
          <div 
            v-if="!hideAmounts && day.data.income > 0"
            class="calendar-amount text-green-700 dark:text-green-300"
          >
            +{{ formatMoney(day.data.income) }}
          </div>
          <div 
            v-if="!hideAmounts && day.data.expense > 0"
            class="calendar-amount calendar-amount-expense"
          >
            -{{ formatMoney(day.data.expense) }}
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.calendar-nav { display: flex; align-items: center; gap: 2px; }
.calendar-nav-button { display: grid; place-items: center; width: 44px; height: 44px; flex: none; border-radius: 50%; color: #6e6e73; transition: background-color 150ms ease, color 150ms ease; }
.calendar-nav-button:hover { background: rgb(118 118 128 / 10%); color: #1c1c1e; }
.calendar-nav-button:focus-visible { outline: 2px solid #007aff; outline-offset: 2px; }
.calendar-heading { color: #1c1c1e; font-size: 20px; line-height: 1.35; font-weight: 650; letter-spacing: -.022em; }
.calendar-amount { min-height: 13px; font-size: 10px; line-height: 1.3; font-weight: 550; font-variant-numeric: tabular-nums; }
.calendar-amount-expense { color: #d33b40; }
:global(.dark) .calendar-nav-button { color: #aaaab2; }
:global(.dark) .calendar-nav-button:hover { background: rgb(255 255 255 / 9%); color: #f5f5f7; }
:global(.dark) .calendar-heading { color: #f5f5f7; }
:global(.dark) .calendar-amount-expense { color: #ffa1a5; }
@media (max-width: 380px) {
  .calendar-heading { font-size: 18px; }
  .calendar-nav-button { width: 44px; height: 44px; }
  .calendar-amount { letter-spacing: -.02em; }
}
@media (prefers-reduced-motion: reduce) {
  .calendar-nav-button { transition: none; }
}
</style>
