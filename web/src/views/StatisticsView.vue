<script setup lang="ts">
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue'
import { ChevronLeft, ChevronRight, PieChart } from '@lucide/vue'
import { useRouter } from 'vue-router'
import FinancePage from '@/components/ui/FinancePage.vue'
import SelectionControl from '@/components/ui/SelectionControl.vue'
import { chartAxisLimit, chartBarPercent } from '@/utils/chartScale'
import { statisticsApi, type OverviewResponse, type CategoryStatItem, type TrendItem } from '@/api/statistics'
import { toast } from '@/composables/useToast'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { getCategoryEmoji } from '@/utils/constants'
import { createRequestGeneration } from '@/utils/requestGeneration'
import DynamicIcon from '@/components/DynamicIcon.vue'
import dayjs from 'dayjs'

const router = useRouter()
const overview = ref<OverviewResponse | null>(null)
const categoryStats = ref<CategoryStatItem[]>([])
const trendData = ref<TrendItem[]>([])
const trendChart = ref<HTMLElement | null>(null)
const activeTrend = ref<TrendItem | null>(null)
const trendTooltipLeft = ref(0)
let trendAnchor: HTMLElement | null = null
const selectedMonth = ref(dayjs().format('YYYY-MM'))
const statsType = ref<'expense' | 'income'>('expense')
const loading = ref(false)
const dataQueryKey = ref('')
const loadFailed = ref(false)
const ledgerMutationRevision = useLedgerMutationRevision()
const dataRequests = createRequestGeneration()

const currentMonthDisplay = computed(() => {
  return dayjs(selectedMonth.value).format('YYYY年M月')
})

const maxTrendAmount = computed(() => {
  if (trendData.value.length === 0) return 0
  return Math.max(...trendData.value.map(item => Math.max(item.expense, item.income)))
})

const dailyTrend = computed<TrendItem[]>(() => {
  if (!dataQueryKey.value) return []
  const month = dayjs(selectedMonth.value)
  const recorded = new Map(trendData.value.map(item => [item.date, item]))
  const lastRecorded = Math.max(0, ...trendData.value.map(item => dayjs(item.date).date()))
  const days = selectedMonth.value === dayjs().format('YYYY-MM')
    ? Math.min(month.daysInMonth(), Math.max(dayjs().date(), lastRecorded))
    : month.daysInMonth()
  // The API returns grouped recorded days only; an absent day has no recorded cash flow.
  return Array.from({ length: days }, (_, index) => {
    const date = month.date(index + 1).format('YYYY-MM-DD')
    return recorded.get(date) ?? { date, income: 0, expense: 0, balance: 0 }
  })
})
const trendAxis = computed(() => chartAxisLimit(maxTrendAmount.value))
const trendTicks = computed(() => [1, .75, .5, .25, 0].map(ratio => ratio * trendAxis.value))
const statisticsOptions = [{ value: 'month', label: '本月' }, { value: 'year', label: '年度' }]
const categoryOptions = [{ value: 'expense', label: '支出' }, { value: 'income', label: '收入' }]
let trendObserver: ResizeObserver | undefined
let trendPointer: number | null = null

// The optional legacy ring retains its bounded gradient representation.
const pieGradient = computed(() => {
  if (categoryStats.value.length === 0) return 'conic-gradient(#e5e7eb 0% 100%)'
  const sectors: { color: string; start: number; end: number }[] = []
  let accumulated = 0
  categoryStats.value.forEach(item => {
    const start = accumulated
    accumulated += item.percentage
    const color = item.color || '#94a3b8'
    const previous = sectors[sectors.length - 1]
    // Adjacent equal colors have no visible boundary. Avoid thousands of
    // redundant gradient stops, which can crash Firefox, without merging rows.
    if (previous?.color === color) previous.end = accumulated
    else sectors.push({ color, start, end: accumulated })
  })
  return `conic-gradient(${sectors.map(sector => `${sector.color} ${sector.start}% ${sector.end}%`).join(', ')})`
})

const categoryTotal = computed(() => {
  return categoryStats.value.reduce((s, i) => s + i.amount, 0)
})

onMounted(() => {
  loadData()
  trendObserver = new ResizeObserver(() => positionTrendDetails())
  if (trendChart.value) trendObserver.observe(trendChart.value)
})

watch([selectedMonth, statsType], () => {
  loadData()
})

watch(ledgerMutationRevision, () => {
  void loadData()
})

async function loadData() {
  const requestGeneration = dataRequests.begin()
  const requestedMonth = selectedMonth.value
  const requestedType = statsType.value
  const queryKey = `${requestedMonth}:${requestedType}`
  activeTrend.value = null
  // A different query cannot present a previous month's or category type's values.
  if (dataQueryKey.value !== queryKey) {
    overview.value = null
    categoryStats.value = []
    trendData.value = []
    dataQueryKey.value = ''
  }
  loadFailed.value = false
  loading.value = true
  try {
    const [ov, stats, trend] = await Promise.all([
      statisticsApi.getOverview(requestedMonth),
      statisticsApi.getCategoryStats(requestedMonth, requestedType),
      statisticsApi.getTrend(requestedMonth)
    ])
    if (
      !dataRequests.isLatest(requestGeneration)
      || selectedMonth.value !== requestedMonth
      || statsType.value !== requestedType
    ) return
    dataQueryKey.value = queryKey
    overview.value = ov
    categoryStats.value = [...stats.items].sort((a, b) => b.amount - a.amount)
    trendData.value = trend.items
  } catch (e: any) {
    if (dataRequests.isLatest(requestGeneration)) {
      loadFailed.value = true
      toast.error('加载统计数据失败')
    }
  } finally {
    if (dataRequests.isLatest(requestGeneration)) {
      loading.value = false
    }
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
  if (value === undefined) return '—'
  return value.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}
const largeSummary = computed(() => overview.value
  ? [overview.value.expense, overview.value.income, overview.value.balance].some(value => formatMoney(value).length > 9)
  : false)

function getDayLabel(dateStr: string) {
  return dayjs(dateStr).format('D')
}

function showTrendDetails(item: TrendItem, event: Event) {
  if (!(event.currentTarget instanceof HTMLElement)) return
  trendAnchor = event.currentTarget
  activeTrend.value = item
  positionTrendDetails()
}

function positionTrendDetails() {
  if (!activeTrend.value || !trendChart.value || !trendAnchor) return
  const chart = trendChart.value.getBoundingClientRect()
  const day = trendAnchor.getBoundingClientRect()
  const tooltipWidth = Math.min(144, chart.width)
  trendTooltipLeft.value = Math.max(0, Math.min(
    day.x + day.width / 2 - chart.x - tooltipWidth / 2,
    chart.width - tooltipWidth
  ))
}
function inspectTrendAt(x: number) {
  const buttons = [...(trendChart.value?.querySelectorAll<HTMLElement>('[data-trend-day]') ?? [])]
  const nearest = buttons.reduce<{ element: HTMLElement; distance: number } | null>((best, element) => {
    const rect = element.getBoundingClientRect()
    const distance = Math.abs(rect.left + rect.width / 2 - x)
    return !best || distance < best.distance ? { element, distance } : best
  }, null)
  if (!nearest) return
  const item = dailyTrend.value.find(row => row.date === nearest.element.dataset.trendDay)
  if (item) { trendAnchor = nearest.element; activeTrend.value = item; positionTrendDetails() }
}
function trendPointerDown(event: PointerEvent) {
  if (event.pointerType === 'mouse') return
  trendPointer = event.pointerId
  trendChart.value?.setPointerCapture(event.pointerId)
  inspectTrendAt(event.clientX)
}
function trendPointerMove(event: PointerEvent) { if (event.pointerId === trendPointer) inspectTrendAt(event.clientX) }
function trendPointerEnd(event: PointerEvent) {
  if (event.pointerId !== trendPointer) return
  if (trendChart.value?.hasPointerCapture(event.pointerId)) trendChart.value.releasePointerCapture(event.pointerId)
  trendPointer = null
}
function trendKeyboard(event: KeyboardEvent, index: number) {
  if (event.key === 'Escape') { activeTrend.value = null; return }
  if (!['ArrowLeft','ArrowRight','Home','End'].includes(event.key)) return
  event.preventDefault()
  const count = dailyTrend.value.length
  const next = event.key === 'Home' ? 0 : event.key === 'End' ? count - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + count) % count
  trendChart.value?.querySelectorAll<HTMLElement>('[data-trend-day]')[next]?.focus({ preventScroll: true })
}
function hideTrendOnLeave(event: PointerEvent) { if (event.pointerType === 'mouse' && !trendChart.value?.contains(document.activeElement)) activeTrend.value = null }
function showDayLabel(index: number) { return index === 0 || index === dailyTrend.value.length - 1 || (index + 1) % Math.max(5, Math.ceil(dailyTrend.value.length / 5)) === 0 }
watch(trendChart, element => { trendObserver?.disconnect(); if (element) trendObserver?.observe(element) })
onBeforeUnmount(() => { dataRequests.begin(); trendObserver?.disconnect() })
</script>

<template>
  <FinancePage title="统计分析" :context="currentMonthDisplay" :icon="PieChart" tone="cyan">
    <template #actions><SelectionControl model-value="month" label="统计范围" :options="statisticsOptions" @update:model-value="$event === 'year' && router.push('/report')" /></template>
    <div v-if="loadFailed" role="alert" class="finance-card finance-card-padding text-sm text-amber-800 dark:text-amber-200">{{ currentMonthDisplay }}统计加载失败。{{ dataQueryKey ? '显示该月上次成功加载的结果。' : '尚无该查询的可用数据。' }}<button class="finance-button is-subtle mt-2" @click="loadData">重新加载统计</button></div>
    <section class="finance-card statistics-summary" :class="{ 'has-long-amount': largeSummary }" :aria-busy="loading">
      <div><p>本月总支出</p><strong class="font-nums">¥{{ formatMoney(overview?.expense) }}</strong></div><div><p><i class="statistics-dot income"></i>收入</p><strong class="font-nums income">¥{{ formatMoney(overview?.income) }}</strong></div><div><p>结余</p><strong class="font-nums">¥{{ formatMoney(overview?.balance) }}</strong></div>
    </section>
    <section class="finance-card finance-card-padding statistics-chart-card">
      <div class="finance-card-heading"><div><h2>收支趋势</h2><p class="finance-muted mt-1">{{ currentMonthDisplay }} · 单位：元</p></div><div class="statistics-period"><button class="finance-icon-button" aria-label="上个月" @click="prevMonth"><ChevronLeft :size="17" /></button><button class="finance-icon-button" aria-label="下个月" :disabled="selectedMonth >= dayjs().format('YYYY-MM')" @click="nextMonth"><ChevronRight :size="17" /></button></div></div>
      <p v-if="!dailyTrend.length" class="finance-muted py-8 text-center">{{ loading ? '统计加载中…' : '尚无可用数据' }}</p>
      <div v-else class="statistics-trend">
        <div class="statistics-yaxis" aria-hidden="true"><span v-for="tick in trendTicks" :key="tick">{{ tick.toLocaleString('zh-CN', { maximumFractionDigits: 2 }) }}</span></div>
        <div ref="trendChart" class="statistics-trend-plot" role="group" :aria-label="`${currentMonthDisplay}每日已记收支，同一金额刻度`" :style="{ gridTemplateColumns: `repeat(${dailyTrend.length},minmax(0,1fr))` }"
          @pointerdown="trendPointerDown" @pointermove="trendPointerMove" @pointerup="trendPointerEnd" @pointercancel="trendPointerEnd" @pointerleave="hideTrendOnLeave" @focusout="!trendChart?.contains($event.relatedTarget as Node) && (activeTrend = null)">
          <button v-for="(item, index) in dailyTrend" :key="item.date" type="button" :data-trend-day="item.date" :tabindex="activeTrend ? activeTrend.date === item.date ? 0 : -1 : index === dailyTrend.length - 1 ? 0 : -1"
            :aria-label="`${dayjs(item.date).format('M月D日')}，收入 ${formatMoney(item.income)}，支出 ${formatMoney(item.expense)}`" class="statistics-trend-day" :class="{ 'is-inspected': activeTrend?.date === item.date }"
            @pointerenter="$event.pointerType === 'mouse' && showTrendDetails(item, $event)" @focus="showTrendDetails(item, $event)" @click="showTrendDetails(item, $event)" @keydown="trendKeyboard($event, index)">
            <i v-if="item.income > 0" class="statistics-bar income" :style="{ height: `${chartBarPercent(item.income, trendAxis)}%` }"></i><i v-if="item.expense > 0" class="statistics-bar expense" :style="{ height: `${chartBarPercent(item.expense, trendAxis)}%` }"></i><span v-if="showDayLabel(index)" class="statistics-day-label">{{ getDayLabel(item.date) }}</span>
          </button>
          <div v-if="activeTrend" role="tooltip" class="statistics-tooltip" :style="{ left: `${trendTooltipLeft}px` }"><strong>{{ dayjs(activeTrend.date).format('M月D日') }}</strong><span class="income">收入 ¥{{ formatMoney(activeTrend.income) }}</span><span class="expense">支出 ¥{{ formatMoney(activeTrend.expense) }}</span></div>
        </div>
      </div>
      <p v-if="dataQueryKey && !trendData.length" class="finance-muted mb-3 text-center">本月暂无已记收支</p>
      <div class="statistics-legend"><span><i class="statistics-dot income"></i>收入</span><span><i class="statistics-dot expense"></i>支出</span></div>
    </section>
    <section class="finance-card finance-card-padding">
      <div class="finance-card-heading"><div><h2>分类排行</h2><p class="finance-muted mt-1">共 ¥{{ dataQueryKey ? formatMoney(categoryTotal) : '—' }}</p></div><SelectionControl :model-value="statsType" label="分类类型" :options="categoryOptions" @update:model-value="statsType = $event as 'expense' | 'income'" /></div>
      <p v-if="!categoryStats.length" class="finance-muted py-8 text-center">{{ loading ? '统计加载中' : dataQueryKey ? '本月暂无数据' : '统计尚未加载' }}</p>
      <div v-else class="statistics-category-list"><div v-for="item in categoryStats" :key="item.category_id" class="statistics-category-row"><span class="statistics-category-icon"><DynamicIcon :icon="getCategoryEmoji(item.category_name, item.icon)" :size="18" /></span><span class="statistics-category-name">{{ item.category_name }}</span><span class="statistics-category-track"><i :style="{ width: `${Math.max(0, Math.min(item.percentage,100))}%` }"></i></span><strong class="font-nums">¥{{ formatMoney(item.amount) }}</strong><span class="statistics-category-share">{{ item.percentage.toFixed(1) }}%</span></div></div>
      <details v-if="categoryStats.length" class="statistics-ring-details"><summary>环形图</summary><div class="statistics-ring" role="img" :aria-label="`${statsType === 'income' ? '收入' : '支出'}分类占比，详细金额见上方列表`" :style="{ background: pieGradient }"><div><span class="finance-muted">总计</span><strong class="font-nums">¥{{ formatMoney(categoryTotal) }}</strong></div></div></details>
    </section>
  </FinancePage>
</template>

<style scoped>
.statistics-summary { display: grid; grid-template-columns: 1.2fr 1fr 1fr; padding: 22px; gap: 0; }
.statistics-summary > div { min-width: 0; padding: 0 18px; }
.statistics-summary > div:first-child { padding-left: 0; }
.statistics-summary > div + div { border-left: 1px solid var(--fp-line); }
.statistics-summary p { color: var(--fp-secondary); font-size: 12px; }
.statistics-summary strong { display: block; margin-top: 10px; font-size: 22px; font-weight: 600; letter-spacing: -.025em; white-space: nowrap; }
.statistics-summary > div:first-child strong { font-size: 28px; }
.income { color: var(--fp-green); }
.expense { color: var(--fp-red); }
.statistics-period { display: flex; gap: 2px; }
.statistics-period .finance-icon-button { background: var(--fp-soft); border-radius: 12px; }
.statistics-trend { display: grid; grid-template-columns: 44px minmax(0,1fr); gap: 8px; padding: 12px 0 28px; }
.statistics-yaxis { display: flex; flex-direction: column; justify-content: space-between; height: 210px; text-align: right; color: var(--fp-secondary); font-size: 11px; font-variant-numeric: tabular-nums; }
.statistics-trend-plot { position: relative; height: 210px; display: grid; align-items: end; gap: 3px; border-bottom: 1px solid var(--fp-line); touch-action: pan-y; background: linear-gradient(to bottom,transparent calc(25% - .5px),var(--fp-line) 25%,transparent calc(25% + .5px),transparent calc(50% - .5px),var(--fp-line) 50%,transparent calc(50% + .5px),transparent calc(75% - .5px),var(--fp-line) 75%,transparent calc(75% + .5px)); }
.statistics-trend-day { position: relative; display: flex; align-items: flex-end; justify-content: center; gap: 1px; height: 100%; min-width: 0; background: transparent; }
.statistics-trend-day:focus-visible { outline-offset: -2px; }
.statistics-trend-day.is-inspected { background: var(--fp-blue-soft); }
.statistics-bar { width: 43%; min-height: 0; max-width: 16px; border-radius: 3px 3px 1px 1px; }
.statistics-bar.income,.statistics-dot.income { background: var(--fp-green); }
.statistics-bar.expense,.statistics-dot.expense { background: var(--fp-red); }
.statistics-day-label { position: absolute; top: calc(100% + 8px); left: 50%; transform: translateX(-50%); font-size: 10px; color: var(--fp-secondary); }
.statistics-dot { display: inline-block; width: 7px; height: 7px; border-radius: 2px; margin-right: 5px; vertical-align: middle; }
.statistics-legend { display: flex; justify-content: center; gap: 20px; color: var(--fp-secondary); font-size: 12px; }
.statistics-tooltip { position: absolute; top: 8px; z-index: 3; width: min(144px,100%); border: 1px solid var(--fp-line); border-radius: 12px; background: var(--fp-solid); box-shadow: 0 8px 22px #1628441a; padding: 10px; font-size: 12px; pointer-events: none; }
.statistics-tooltip > * { display: block; line-height: 1.65; }
.statistics-tooltip strong { font-weight: 550; }
.statistics-category-row { display: grid; grid-template-columns: 30px 70px minmax(30px,1fr) 100px 52px; gap: 10px; min-height: 54px; align-items: center; }
.statistics-category-row + .statistics-category-row { border-top: 1px solid var(--fp-line); }
.statistics-category-icon { display: grid; place-items: center; width: 28px; height: 28px; border-radius: 10px; color: var(--fp-blue); background: var(--fp-soft); }
.statistics-category-name { font-size: 13px; overflow-wrap: anywhere; }
.statistics-category-row strong { font-size: 13px; text-align: right; font-weight: 500; white-space: nowrap; }
.statistics-category-track { height: 5px; border-radius: 99px; overflow: hidden; background: var(--fp-line); }
.statistics-category-track i { display: block; height: 100%; border-radius: inherit; background: var(--fp-blue); opacity: .85; }
.statistics-category-share { text-align: right; font-size: 12px; color: var(--fp-secondary); }
.statistics-ring-details { margin-top: 18px; color: var(--fp-secondary); font-size: 12px; }
.statistics-ring-details summary { width: fit-content; min-height: 32px; cursor: pointer; }
.statistics-ring { position: relative; margin: 16px auto 0; width: 192px; height: 192px; border-radius: 50%; }
.statistics-ring > div { position: absolute; inset: 20px; border-radius: 50%; background: var(--fp-solid); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 6px; }
.statistics-ring strong { font-size: 18px; color: var(--fp-ink); }
@media (max-width:767px) {
  .statistics-summary { padding: 20px 14px; grid-template-columns: repeat(3,minmax(0,1fr)); }
  .statistics-summary > div { padding: 0 12px; }
  .statistics-summary > div:last-child { padding-right: 0; }
  .statistics-summary strong { font-size: 18px; }
  .statistics-summary > div:first-child strong { font-size: 22px; }
  .statistics-summary p { font-size: 11px; }
  .statistics-summary.has-long-amount { grid-template-columns: repeat(2,minmax(0,1fr)); row-gap: 18px; }
  .statistics-summary.has-long-amount > div:first-child { grid-column: 1 / -1; }
  .statistics-summary.has-long-amount > div:nth-child(2) { padding-left: 0; border-left: 0; }
  .statistics-summary.has-long-amount strong { white-space: normal; overflow-wrap: anywhere; }
  .statistics-trend { grid-template-columns: 34px minmax(0,1fr); gap: 4px; }
  .statistics-trend-plot,.statistics-yaxis { height: 180px; }
  .statistics-category-row { grid-template-columns: 28px minmax(45px,1fr) minmax(28px,1fr) auto; gap: 8px; }
  .statistics-category-share { display: none; }
}
@media (max-width:360px) {
  .statistics-summary > div { padding: 0 9px; }
  .statistics-summary strong { font-size: 16px; }
  .statistics-summary > div:first-child strong { font-size: 18px; }
}
</style>
