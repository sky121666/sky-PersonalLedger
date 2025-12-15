<script setup lang="ts">
import { ref, onMounted, watch, computed } from 'vue'
import { Search, Trash2, ChevronDown, Calendar, X, List } from 'lucide-vue-next'
import { transactionApi, type Transaction } from '@/api/transaction'
import TransactionDialog from '@/components/TransactionDialog.vue'
import { toast } from '@/composables/useToast'
import { getCategoryEmoji } from '@/utils/constants'
import dayjs from 'dayjs'
import 'dayjs/locale/zh-cn'

dayjs.locale('zh-cn')

const transactions = ref<Transaction[]>([])
const loading = ref(false)
const page = ref(1)
const hasMore = ref(true)
const total = ref(0)

const showDialog = ref(false)
const editingId = ref<string | null>(null)
const showDeleteModal = ref(false)
const deletingId = ref<string | null>(null)

// Filters & Search
const showFilter = ref(false)
const filters = ref({
  type: '' as string,
  startDate: '',
  endDate: '',
  keyword: ''
})

// Grouped Data Logic
interface DailyGroup {
  date: string
  dayLabel: string
  weekLabel: string
  totalIncome: number
  totalExpense: number
  items: Transaction[]
}

const groupedTransactions = computed(() => {
  const groups: DailyGroup[] = []
  const map = new Map<string, DailyGroup>()

  transactions.value.forEach(t => {
    const dateStr = dayjs(t.transaction_date).format('YYYY-MM-DD')
    
    if (!map.has(dateStr)) {
      const dateObj = dayjs(dateStr)
      let dayLabel = ''
      if (dateObj.isSame(dayjs(), 'day')) dayLabel = '今天'
      else if (dateObj.isSame(dayjs().subtract(1, 'day'), 'day')) dayLabel = '昨天'
      else dayLabel = dateObj.format('MM月DD日')

      const group: DailyGroup = {
        date: dateStr,
        dayLabel,
        weekLabel: dateObj.format('dddd'),
        totalIncome: 0,
        totalExpense: 0,
        items: []
      }
      groups.push(group)
      map.set(dateStr, group)
    }

    const group = map.get(dateStr)!
    group.items.push(t)
    if (t.type === 'income') group.totalIncome += t.amount
    else if (t.type === 'expense') group.totalExpense += t.amount
  })

  // Sort items within each group by time DESC
  groups.forEach(g => {
    g.items.sort((a, b) => dayjs(b.transaction_date).valueOf() - dayjs(a.transaction_date).valueOf())
  })

  return groups
})

onMounted(() => {
  loadTransactions()
})

function openEdit(id: string) {
  editingId.value = id
  showDialog.value = true
}

function confirmDelete(id: string) {
  deletingId.value = id
  showDeleteModal.value = true
}

async function handleDelete() {
  if (!deletingId.value) return
  try {
    await transactionApi.delete(deletingId.value)
    showDeleteModal.value = false
    deletingId.value = null
    toast.success('删除成功')
    loadTransactions()
  } catch (e: any) {
    toast.error(e.message || '删除失败')
  }
}

async function loadTransactions() {
  loading.value = true
  try {
    const params: any = { 
      page: 1, 
      page_size: 20,
      ...filters.value
    }
    // Remove empty filters
    Object.keys(params).forEach(key => {
      if (params[key] === '') delete params[key]
    })

    const data = await transactionApi.getList(params)
    transactions.value = data.list
    total.value = data.total
    hasMore.value = data.list.length >= 20
    page.value = 1
  } catch (e) {
    console.error('Load transactions failed:', e)
  } finally {
    loading.value = false
  }
}

async function loadMore() {
  if (!hasMore.value || loading.value) return
  loading.value = true
  try {
    page.value++
    const params: any = { 
      page: page.value, 
      page_size: 20,
      ...filters.value
    }
    Object.keys(params).forEach(key => {
      if (params[key] === '') delete params[key]
    })

    const data = await transactionApi.getList(params)
    transactions.value.push(...data.list)
    hasMore.value = data.list.length >= 20
  } finally {
    loading.value = false
  }
}

function formatTime(date: string) {
  return dayjs(date).format('HH:mm')
}

function formatMoney(value: number) {
  return value.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

watch(filters, () => {
  loadTransactions()
}, { deep: true })
</script>

<template>
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black pb-8">
    <!-- Header -->
    <div class="bg-white/70 dark:bg-[#1C1C1E]/70 pt-4 pb-4 px-4 md:px-8 sticky top-0 z-30 backdrop-blur-xl border-b border-gray-200/50 dark:border-white/10">
      <div class="max-w-3xl mx-auto flex items-center justify-between">
        <div class="flex items-center gap-4">
          <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-amber-500 to-amber-600 flex items-center justify-center shadow-lg shadow-amber-500/20">
            <List class="text-white" :size="28" />
          </div>
          <div>
            <h1 class="text-xl font-bold text-gray-900 dark:text-white">账单明细</h1>
            <div class="text-sm text-gray-500 dark:text-gray-400 mt-0.5">{{ total }} 条记录</div>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <!-- Filter Trigger -->
          <button 
            class="flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-medium transition-all"
            :class="showFilter ? 'bg-black text-white dark:bg-white dark:text-black' : 'bg-gray-100/50 dark:bg-white/5 text-gray-600 dark:text-gray-300'"
            @click="showFilter = !showFilter"
          >
            <span v-if="filters.type">{{ filters.type === 'expense' ? '支出' : (filters.type === 'income' ? '收入' : '转账') }}</span>
            <span v-else>全部类型</span>
            <ChevronDown :size="12" />
          </button>

          <!-- Search Trigger -->
          <div class="relative group">
             <input
              v-model="filters.keyword"
              type="text"
              placeholder="搜索"
              class="w-24 focus:w-40 transition-all duration-300 h-8 pl-8 pr-3 bg-gray-100/50 dark:bg-white/5 rounded-full text-xs outline-none focus:ring-2 focus:ring-primary/20 dark:text-white"
            />
            <Search class="absolute left-2.5 top-1/2 -translate-y-1/2 text-gray-400" :size="14" />
          </div>
        </div>
      </div>

      <!-- Filter Panel -->
      <div v-if="showFilter" class="border-t border-gray-200/50 dark:border-white/10 bg-gray-50/90 dark:bg-[#1C1C1E]/90 backdrop-blur-xl">
        <div class="max-w-3xl mx-auto px-4 py-3 space-y-3">
          <!-- Type Filter -->
          <div class="flex gap-2">
            <button 
              v-for="t in [{v:'', l:'全部'}, {v:'expense', l:'支出'}, {v:'income', l:'收入'}, {v:'transfer', l:'转账'}]" 
              :key="t.v"
              class="px-4 py-1.5 rounded-full text-xs font-medium transition-all"
              :class="filters.type === t.v ? 'bg-primary text-white shadow-lg shadow-primary/20' : 'bg-white dark:bg-gray-700 text-gray-600 dark:text-gray-300 border border-gray-200 dark:border-gray-600'"
              @click="filters.type = t.v"
            >
              {{ t.l }}
            </button>
          </div>
          <!-- Date Filter -->
          <div class="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
             <div class="relative">
                <input v-model="filters.startDate" type="date" class="pl-8 pr-2 py-1 bg-white dark:bg-gray-700 rounded-lg text-xs border border-gray-200 dark:border-gray-600 outline-none" />
                <Calendar class="absolute left-2 top-1/2 -translate-y-1/2 text-gray-400" :size="14" />
             </div>
             <span>至</span>
             <div class="relative">
                <input v-model="filters.endDate" type="date" class="pl-8 pr-2 py-1 bg-white dark:bg-gray-700 rounded-lg text-xs border border-gray-200 dark:border-gray-600 outline-none" />
                <Calendar class="absolute left-2 top-1/2 -translate-y-1/2 text-gray-400" :size="14" />
             </div>
             <button v-if="filters.startDate || filters.endDate" @click="{ filters.startDate=''; filters.endDate='' }" class="p-1 hover:bg-gray-200 dark:hover:bg-gray-600 rounded-full">
               <X :size="14" />
             </button>
          </div>
        </div>
      </div>
    </div>

    <div class="max-w-3xl mx-auto px-4 md:px-8 py-4 space-y-6">
      
      <!-- Empty State -->
      <div v-if="transactions.length === 0 && !loading" class="py-20 text-center">
        <div class="w-20 h-20 bg-gray-100 dark:bg-gray-800 rounded-full flex items-center justify-center mx-auto mb-4 text-gray-400">
          <Search :size="32" />
        </div>
        <p class="text-gray-500 text-sm">暂无交易记录</p>
      </div>

      <!-- Grouped List -->
      <div v-else class="space-y-4">
        <div 
          v-for="group in groupedTransactions" 
          :key="group.date"
          class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-2xl shadow-[0_4px_20px_rgb(0,0,0,0.02)] overflow-hidden border border-white/20 dark:border-white/5"
        >
          <!-- Daily Header -->
          <div class="bg-gray-50/50 dark:bg-white/5 px-4 py-2.5 flex items-center justify-between text-xs text-gray-500 dark:text-gray-400 border-b border-gray-100/50 dark:border-white/5">
            <div class="flex items-center gap-2">
              <span class="font-medium text-gray-900 dark:text-white">{{ group.dayLabel }}</span>
              <span>{{ group.weekLabel }}</span>
            </div>
            <div class="flex items-center gap-3">
              <span v-if="group.totalIncome > 0">收入 <span class="font-nums text-gray-900 dark:text-white">{{ formatMoney(group.totalIncome) }}</span></span>
              <span v-if="group.totalExpense > 0">支出 <span class="font-nums text-gray-900 dark:text-white">{{ formatMoney(group.totalExpense) }}</span></span>
            </div>
          </div>

          <!-- Items -->
          <div class="divide-y divide-gray-100/50 dark:divide-white/5">
            <div
              v-for="item in group.items"
              :key="item.id"
              class="px-4 py-4 flex items-center justify-between active:bg-gray-50 dark:active:bg-white/5 transition-colors cursor-pointer group"
              @click="openEdit(item.id)"
            >
              <div class="flex items-center gap-3.5">
                <!-- Icon -->
                <div
                  class="w-10 h-10 rounded-full flex items-center justify-center text-xl shadow-sm border border-gray-100/50 dark:border-white/10"
                  :style="{ backgroundColor: (item.type === 'transfer' ? '#6366F1' : (item.category?.color || '#94a3b8')) + '15' }"
                >
                  {{ item.type === 'transfer' ? '↔️' : getCategoryEmoji(item.category?.name || '', item.category?.icon || '') }}
                </div>
                
                <!-- Content -->
                <div class="flex flex-col gap-0.5">
                  <div class="text-[15px] font-medium text-gray-900 dark:text-white flex items-center gap-2">
                    {{ item.type === 'transfer' ? '转账' : (item.category?.name || '未分类') }}
                    <span v-if="item.remark" class="text-xs font-normal text-gray-400 bg-gray-100 dark:bg-white/10 px-1.5 py-0.5 rounded text-truncate max-w-[120px]">{{ item.remark }}</span>
                  </div>
                  <div class="text-xs text-gray-400 flex items-center gap-1.5">
                    <span>{{ formatTime(item.transaction_date) }}</span>
                    <span>·</span>
                    <span>{{ item.account?.name || '账户' }}</span>
                  </div>
                </div>
              </div>

              <!-- Amount & Delete -->
              <div class="flex items-center gap-2">
                <div 
                  class="text-[17px] font-bold font-nums tracking-tight text-right"
                  :class="item.type === 'income' ? 'text-emerald-500' : (item.type === 'expense' ? 'text-red-500' : 'text-gray-500 dark:text-gray-400')"
                >
                  {{ item.type === 'income' ? '+' : item.type === 'expense' ? '-' : '' }}{{ formatMoney(item.amount) }}
                </div>
                <!-- Delete Button (Desktop Hover) -->
                <button
                  class="md:flex hidden w-8 h-8 items-center justify-center opacity-0 group-hover:opacity-100 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition-all flex-shrink-0"
                  @click.stop="confirmDelete(item.id)"
                >
                  <Trash2 :size="16" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Load More -->
      <div v-if="hasMore" class="py-4 text-center">
        <button 
          class="px-6 py-2 bg-white/50 dark:bg-white/10 rounded-full text-xs text-gray-500 dark:text-gray-400 hover:bg-white/80 dark:hover:bg-white/20 transition-all"
          @click="loadMore"
        >
          {{ loading ? '加载中...' : '点击加载更多' }}
        </button>
      </div>
      <div v-else-if="transactions.length > 0" class="py-6 text-center text-xs text-gray-300 dark:text-gray-700">
        - 到底了 -
      </div>
    </div>

    <!-- Transaction Dialog -->
    <TransactionDialog
      v-model:visible="showDialog"
      :edit-id="editingId"
      @success="loadTransactions"
    />

    <!-- Delete Confirm Modal -->
    <Teleport to="body">
      <div v-if="showDeleteModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showDeleteModal = false"></div>
        <div class="relative bg-white/90 dark:bg-[#1C1C1E]/90 backdrop-blur-xl rounded-[20px] p-6 w-[280px] shadow-2xl animate-in zoom-in-95 duration-200 text-center">
          <h3 class="text-lg font-bold text-gray-900 dark:text-white mb-2">确认删除</h3>
          <p class="text-[13px] text-gray-500 dark:text-gray-400 mb-6 leading-relaxed">删除后无法恢复，确定要删除这条记录吗？</p>
          <div class="flex gap-3 justify-center border-t border-gray-200/50 dark:border-white/10 pt-4 -mx-6 -mb-2">
            <button
              class="flex-1 py-2 text-[17px] text-blue-500 font-medium active:opacity-70 transition"
              @click="showDeleteModal = false"
            >
              取消
            </button>
            <div class="w-px bg-gray-200/50 dark:bg-white/10"></div>
            <button
              class="flex-1 py-2 text-[17px] text-red-500 font-medium active:opacity-70 transition"
              @click="handleDelete"
            >
              删除
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
/* Mobile Optimizations */
input[type="date"]::-webkit-calendar-picker-indicator {
  opacity: 0;
  position: absolute;
  left: 0;
  top: 0;
  width: 100%;
  height: 100%;
  cursor: pointer;
}
</style>

<style scoped>
</style>
