<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import dayjs from 'dayjs'
import 'dayjs/locale/zh-cn'
import { ChevronLeft, ChevronRight } from 'lucide-vue-next'
import { statisticsApi, type TrendItem } from '@/api/statistics'

dayjs.locale('zh-cn')

const props = defineProps<{
  initialDate?: string // YYYY-MM
}>()

const emit = defineEmits<{
  (e: 'select', date: string): void
  (e: 'month-change', month: string): void
}>()

const currentDate = ref(dayjs(props.initialDate || undefined))
const trendData = ref<TrendItem[]>([])
const loading = ref(false)
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

async function loadData() {
  loading.value = true
  try {
    const res = await statisticsApi.getTrend(currentDate.value.format('YYYY-MM'))
    trendData.value = res.items
  } catch (e) {
    console.error(e)
  } finally {
    loading.value = false
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
        <h2 class="text-xl font-bold text-gray-900 dark:text-white">{{ currentDate.format('YYYY年M月') }}</h2>
      </div>
      <div class="flex items-center gap-2">
        <button 
          class="w-8 h-8 flex items-center justify-center rounded-full hover:bg-gray-100/50 dark:hover:bg-gray-700/50 text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white transition-all" 
          @click="prevMonth"
        >
          <ChevronLeft :size="20" />
        </button>
        <button 
          class="w-8 h-8 flex items-center justify-center rounded-full hover:bg-gray-100/50 dark:hover:bg-gray-700/50 text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white transition-all" 
          @click="nextMonth"
        >
          <ChevronRight :size="20" />
        </button>
      </div>
    </div>

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
        class="py-2 flex flex-col items-center cursor-pointer transition-colors rounded-xl hover:bg-white/40 dark:hover:bg-gray-700/40"
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
            v-if="day.data.income > 0" 
            class="text-[10px] font-medium text-green-600 dark:text-green-400"
          >
            +{{ formatMoney(day.data.income) }}
          </div>
          <div 
            v-if="day.data.expense > 0" 
            class="text-[10px] font-medium text-red-500 dark:text-red-400"
          >
            -{{ formatMoney(day.data.expense) }}
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
