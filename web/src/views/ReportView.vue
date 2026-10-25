<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { Download, BarChart3, TrendingUp, ReceiptText, CalendarDays, Award } from '@lucide/vue'
import FinancePage from '@/components/ui/FinancePage.vue'
import SelectionControl from '@/components/ui/SelectionControl.vue'
import { chartAxisLimit, chartBarPercent } from '@/utils/chartScale'
import { exportApi, type YearlyReport } from '@/api/export'
import { statisticsApi, type AssetTrendItem } from '@/api/statistics'
import { toast } from '@/composables/useToast'
import DynamicIcon from '@/components/DynamicIcon.vue'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { createRequestGeneration } from '@/utils/requestGeneration'

const router = useRouter()

const loading = ref(false)
const exporting = ref(false)
const loadFailed = ref(false)
const yearsFailed = ref(false)
const selectedYear = ref(new Date().getFullYear())
const availableYears = ref<number[]>([])
const report = ref<YearlyReport | null>(null)
const assetTrendData = ref<AssetTrendItem[]>([])
const currentNetWorth = ref(0)
const activeAsset = ref<AssetTrendItem | null>(null)
const statisticsOptions = [{ value: 'month', label: '本月' }, { value: 'year', label: '年度' }]
const ledgerMutationRevision = useLedgerMutationRevision()
const reportRequests = createRequestGeneration()
const yearRequests = createRequestGeneration()
onBeforeUnmount(() => { reportRequests.begin(); yearRequests.begin() })

onMounted(async () => {
  await loadYears()
  await loadReport()
})

watch(ledgerMutationRevision, () => { void loadYears(); void loadReport() })

async function loadYears() {
  const generation = yearRequests.begin()
  try {
    const years = await exportApi.getAvailableYears()
    if (!yearRequests.isLatest(generation)) return
    yearsFailed.value = false
    availableYears.value = [...new Set([...years, selectedYear.value])].sort((a, b) => b - a)
  } catch (e) {
    if (!yearRequests.isLatest(generation)) return
    yearsFailed.value = true
    if (!availableYears.value.length) availableYears.value = [selectedYear.value]
  }
}

async function loadReport() {
  const requestGeneration = reportRequests.begin()
  const requestedYear = selectedYear.value
  loading.value = true
  loadFailed.value = false
  activeAsset.value = null
  if (report.value?.year !== requestedYear) {
    report.value = null
    assetTrendData.value = []
  }
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
      loadFailed.value = true
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
  if (value === undefined) return '—'
  return value.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
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

const assetAxis = computed(() => chartAxisLimit(maxNetWorth.value))
const monthlyAxis = computed(() => chartAxisLimit(maxMonthlyAmount.value))

function getNetWorthHeight(value: number) {
  if (Math.abs(value) < 0.01) return 0
  if (maxNetWorth.value === 0) return 0
  return chartBarPercent(Math.abs(value), assetAxis.value) / 2
}

function getMonthLabel(monthStr: string) {
  const month = parseInt(monthStr.split('-')[1])
  return month + '月'
}


function assetKeyboard(event: KeyboardEvent, index: number) {
  if (event.key === 'Escape') { activeAsset.value = null; return }
  if (!['ArrowLeft','ArrowRight','Home','End'].includes(event.key)) return
  event.preventDefault()
  const buttons = (event.currentTarget as HTMLElement).parentElement?.querySelectorAll<HTMLButtonElement>('button')
  if (!buttons?.length) return
  const next = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1 :
    (index + (event.key === 'ArrowRight' ? 1 : -1) + buttons.length) % buttons.length
  buttons[next]?.focus({ preventScroll: true })
}
</script>

<template>
  <FinancePage title="年度报告" :context="`${selectedYear} 年`" :icon="BarChart3" tone="cyan">
    <template #actions><SelectionControl model-value="year" label="统计范围" :options="statisticsOptions" @update:model-value="$event === 'month' && router.push('/statistics')" /></template>
    <div class="report-controls"><label class="finance-muted">报告年份<select v-model="selectedYear" aria-label="报告年份" class="finance-input" @change="loadReport"><option v-for="year in availableYears" :key="year" :value="year">{{ year }}年</option></select></label><button class="finance-icon-button" aria-label="导出年度 CSV" :disabled="exporting" @click="handleExportCSV"><Download :size="18" /></button></div>
    <div v-if="yearsFailed" role="alert" class="finance-card finance-card-padding text-sm text-amber-700">年份列表加载失败，当前年份仍可查询。<button class="underline" @click="loadYears">重新加载年份</button></div>
    <div v-if="loadFailed" role="alert" class="finance-card finance-card-padding text-sm text-amber-700">{{ selectedYear }} 年报告加载失败。{{ report ? '显示该年上次成功结果。' : '尚无可用结果。' }}<button class="underline" @click="loadReport">重新加载报告</button></div>
    <p v-if="loading" role="status" class="finance-muted py-8 text-center">正在加载 {{ selectedYear }} 年报告…</p>
    <template v-else-if="report">
      <section class="finance-card finance-card-padding report-summary"><p class="finance-muted">{{ report.year }} 年结余</p><strong class="report-savings font-nums">{{ report.net_savings < 0 ? '−' : '' }}¥{{ formatMoney(Math.abs(report.net_savings)) }}</strong><span class="finance-muted">年度财务总结</span><div class="report-summary-parts"><span>收入 <strong class="income font-nums">¥{{ formatMoney(report.total_income) }}</strong></span><span>支出 <strong class="expense font-nums">¥{{ formatMoney(report.total_expense) }}</strong></span></div></section>
      <section class="finance-card finance-card-padding"><div class="finance-card-heading"><div><h2>净资产走势</h2><p class="finance-muted mt-1">最近 12 个月 · 独立于报告年份</p></div><TrendingUp :size="18" class="finance-muted" aria-hidden="true" /></div>
        <p v-if="!assetTrendData.length" class="finance-muted py-8 text-center">暂无数据</p>
        <div v-else class="report-signed-chart"><div class="report-signed-axis" aria-hidden="true"><span>{{ formatMoney(assetAxis) }}</span><span>0</span><span>−{{ formatMoney(assetAxis) }}</span></div><div class="report-signed-bars" role="group" aria-label="净资产走势，正值向上，负值向下">
          <button v-for="(item,index) in assetTrendData" :key="item.month" class="report-signed-slot" :data-asset-month="item.month" :aria-label="`${item.month} 净资产 ${formatMoney(item.net_worth)} 元`" :tabindex="activeAsset ? activeAsset.month === item.month ? 0 : -1 : index === assetTrendData.length - 1 ? 0 : -1" @focus="activeAsset = item" @click="activeAsset = item" @pointerenter="$event.pointerType === 'mouse' && (activeAsset = item)" @keydown="assetKeyboard($event,index)"><i v-if="item.net_worth !== 0" class="report-signed-bar" :class="item.net_worth < 0 ? 'is-negative' : 'is-positive'" :style="{ height: `${getNetWorthHeight(item.net_worth)}%`, [item.net_worth < 0 ? 'top' : 'bottom']: '50%' }"></i><span>{{ getMonthLabel(item.month) }}</span></button>
        </div></div>
        <div class="report-asset-value" role="status"><span class="finance-muted">{{ activeAsset ? `${activeAsset.month} 净资产` : '当前净资产' }}</span><strong class="font-nums" :class="(activeAsset?.net_worth ?? currentNetWorth) < 0 ? 'expense' : ''">{{ (activeAsset?.net_worth ?? currentNetWorth) < 0 ? '−' : '' }}¥{{ formatMoney(Math.abs(activeAsset?.net_worth ?? currentNetWorth)) }}</strong></div>
      </section>
      <section class="finance-card finance-card-padding"><div class="finance-card-heading"><h2>月度收支</h2><span class="finance-muted">单位：元</span></div><div v-for="month in report.monthly_data" :key="month.month" class="report-month-row"><span>{{ month.month }}</span><div><div class="report-month-series"><i class="income" :style="{ width: `${chartBarPercent(month.income,monthlyAxis)}%` }"></i><span>收入 ¥{{ formatMoney(month.income) }}</span></div><div class="report-month-series"><i class="expense" :style="{ width: `${chartBarPercent(month.expense,monthlyAxis)}%` }"></i><span>支出 ¥{{ formatMoney(month.expense) }}</span></div></div></div></section>
      <div class="report-category-grid"><section v-for="group in [{ title: '支出分类', items: report.top_expenses, income: false }, { title: '收入来源', items: report.top_incomes, income: true }]" :key="group.title" class="finance-card finance-card-padding"><div class="finance-card-heading"><h2>{{ group.title }}</h2></div><p v-if="!group.items.length" class="finance-muted py-6 text-center">暂无数据</p><div v-for="cat in group.items.slice(0,5)" :key="cat.category_id" class="report-category-row"><span class="report-category-icon"><DynamicIcon :icon="cat.category_icon || 'wallet'" :size="18" /></span><span>{{ cat.category_name }}</span><strong class="font-nums">¥{{ formatMoney(cat.amount) }}</strong></div></section></div>
      <section class="finance-card finance-card-padding report-metrics"><div><ReceiptText :size="17" aria-hidden="true" /><strong>{{ report.transaction_count }}</strong><span>笔交易</span></div><div><CalendarDays :size="17" aria-hidden="true" /><strong>{{ report.active_days }}</strong><span>活跃天数</span></div><div><strong class="font-nums">¥{{ formatMoney(report.average_expense) }}</strong><span>月均支出</span></div><div><strong class="font-nums">¥{{ formatMoney(report.average_income) }}</strong><span>月均收入</span></div></section>
      <section class="finance-card finance-card-padding"><div class="finance-card-heading"><h2>年度亮点</h2><Award :size="18" class="finance-muted" aria-hidden="true" /></div><div class="report-highlights"><div><strong>{{ report.max_expense_month || '—' }}</strong><span>支出最多月份</span></div><div><strong>{{ report.min_expense_month || '—' }}</strong><span>支出最少月份</span></div><div><strong>{{ report.best_savings_month || '—' }}</strong><span>最佳结余月份</span></div><div v-if="report.max_single_expense > 0"><strong class="font-nums">¥{{ formatMoney(report.max_single_expense) }}</strong><span>最大单笔支出</span></div></div></section>
    </template>
  </FinancePage>
</template>

<style scoped>
.report-controls { display: flex; justify-content: flex-end; align-items: flex-end; gap: 10px; }
.report-controls label { display: flex; align-items: center; gap: 8px; }
.report-controls select { width: 120px; }
.report-savings { display: block; margin: 8px 0 7px; font-size: 36px; font-weight: 600; letter-spacing: -.025em; overflow-wrap: anywhere; }
.report-summary-parts { display: flex; flex-wrap: wrap; gap: 12px 28px; margin-top: 20px; font-size: 13px; color: var(--fp-secondary); }
.report-summary-parts strong { font-weight: 550; margin-left: 6px; }
.income { color: var(--fp-green); }
.expense { color: var(--fp-red); }
.report-signed-chart { display: grid; grid-template-columns: 72px minmax(0,1fr); gap: 8px; margin-top: 24px; padding-bottom: 28px; }
.report-signed-axis { display: flex; flex-direction: column; justify-content: space-between; text-align: right; height: 260px; color: var(--fp-secondary); font-size: 10px; }
.report-signed-bars { height: 260px; position: relative; display: flex; gap: 10px; border-top: 1px solid var(--fp-line); border-bottom: 1px solid var(--fp-line); background: linear-gradient(to bottom,transparent calc(50% - .5px),var(--fp-line) 50%,transparent calc(50% + .5px)); }
.report-signed-slot { position: relative; flex: 1; min-width: 0; height: 100%; background: none; }
.report-signed-slot:focus-visible { outline-offset: -2px; }
.report-signed-bar { position: absolute; left: 20%; width: 60%; max-width: 32px; border-radius: 4px; background: var(--fp-blue); }
.report-signed-bar.is-negative { background: var(--fp-red); }
.report-signed-slot > span { position: absolute; left: 50%; top: calc(100% + 8px); transform: translateX(-50%); color: var(--fp-secondary); font-size: 10px; white-space: nowrap; }
.report-asset-value { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 8px; padding-top: 18px; margin-top: 18px; border-top: 1px solid var(--fp-line); }
.report-asset-value strong { font-size: 21px; font-weight: 600; }
.report-month-row { display: grid; grid-template-columns: 36px minmax(0,1fr); gap: 12px; align-items: center; padding: 12px 0; border-top: 1px solid var(--fp-line); font-size: 12px; }
.report-month-row > span { color: var(--fp-secondary); }
.report-month-series { display: flex; flex-wrap: wrap; gap: 6px 12px; align-items: center; min-height: 24px; }
.report-month-series i { display: block; height: 5px; border-radius: 3px; flex: none; max-width: 100%; }
.report-month-series i.income { background: var(--fp-green); }
.report-month-series i.expense { background: var(--fp-red); }
.report-month-series span { font-size: 11px; color: var(--fp-secondary); }
.report-category-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }
.report-category-row { display: flex; align-items: center; gap: 10px; min-height: 54px; border-top: 1px solid var(--fp-line); font-size: 13px; }
.report-category-row > span:nth-child(2) { flex: 1; min-width: 0; overflow-wrap: anywhere; }
.report-category-row strong { font-weight: 500; white-space: nowrap; }
.report-category-icon { width: 28px; height: 28px; flex: none; border-radius: 10px; background: var(--fp-soft); display: grid; place-items: center; color: var(--fp-blue); }
.report-metrics,.report-highlights { display: grid; grid-template-columns: repeat(4,minmax(0,1fr)); gap: 20px; }
.report-metrics > div,.report-highlights > div { min-width: 0; display: flex; flex-wrap: wrap; align-items: center; gap: 7px; }
.report-metrics svg { color: var(--fp-secondary); }
.report-metrics strong,.report-highlights strong { font-size: 18px; font-weight: 550; overflow-wrap: anywhere; }
.report-metrics span,.report-highlights span { flex: 1 0 100%; color: var(--fp-secondary); font-size: 12px; }
@media (max-width:767px) { .report-savings { font-size: 32px; } .report-signed-chart { grid-template-columns: 58px minmax(0,1fr); gap: 6px; } .report-signed-bars { gap: 3px; } .report-category-grid { grid-template-columns: 1fr; } .report-metrics,.report-highlights { grid-template-columns: repeat(2,minmax(0,1fr)); gap: 20px 12px; } }
</style>
