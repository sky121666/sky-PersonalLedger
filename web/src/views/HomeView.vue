<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, computed, watch, defineAsyncComponent, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { RefreshCw, Eye, EyeOff, SlidersHorizontal, Plus, Undo2, Ellipsis } from '@lucide/vue'
import { transactionApi, type Transaction } from '@/api/transaction'
import { isManagedTransaction } from '@/utils/managedTransaction'
import TransactionDialog from '@/components/TransactionDialog.vue'
import { toast } from '@/composables/useToast'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { createRequestGeneration } from '@/utils/requestGeneration'
import dayjs from 'dayjs'
import HomeWidget from '@/components/home/HomeWidget.vue'
import { createHomeReadModels, getTransactionPresentation } from '@/components/home/readModels'
import { getColumnCount } from '@/components/home/layout'
import WidgetGrid from '@/components/home/WidgetGrid.vue'
import { useWorkspacePreferencesStore } from '@/stores/workspacePreferences'
import { useHomeOverview } from '@/composables/useHomeOverview'
import { useAuthStore } from '@/stores/auth'
import { type WidgetKind, type WidgetSize } from '@/components/home/model'
const WidgetGallery = defineAsyncComponent(() => import('@/components/home/WidgetGallery.vue'))

const router = useRouter()
const ledgerMutationRevision = useLedgerMutationRevision()
const dateTransactionsRequestGeneration = createRequestGeneration()
const refreshRequests = createRequestGeneration()

const dateTransactionsFailed = ref(false)
const showAmount = ref(true)
const viewMode = ref<'list' | 'calendar'>('list')
const selectedDate = ref(dayjs().format('YYYY-MM-DD'))
const calendarRef = ref<{ loadData: () => Promise<'success' | 'failed' | 'stale'> } | null>(null)
const dateTransactionsLoading = ref(false)
const dateTransactionsTotal = ref(0)
const dateTransactionsPage = ref(1)
const dateFailedPage = ref(1)

const preferences = useWorkspacePreferencesStore()
const auth = useAuthStore()
const homeLayout = computed(() => preferences.home)
const optionalSources = computed(() => {
  const widgets = homeLayout.value.widgets
  const enabled = (kind: WidgetKind) => widgets.some(widget => widget.kind === kind)
  return {
    lending: enabled('lending'), family: enabled('family'), ai: enabled('ai'),
    budgetDetails: widgets.some(widget => widget.kind === 'budget' && widget.sizes[preferences.viewport] === 'large'),
    accountIds: widgets.filter(widget => widget.kind === 'account' && widget.sizes[preferences.viewport] === 'medium').map(widget => widget.config.accountId),
  }
})
const homeData = useHomeOverview({ optional: () => optionalSources.value, sessionGeneration: () => auth.sessionGeneration })
const loading = homeData.loading
const loadFailures = homeData.failures
const accountData = computed(() => homeData.accounts.value.data)
const overview = computed(() => homeData.overview.value.data)
const recentTransactions = computed(() => homeData.recentTransactions.value.data ?? [])
const debtSummary = computed(() => homeData.debt.value.data)
const budgetSummary = computed(() => homeData.budget.value.data)
const lendingSummary = computed(() => homeData.lending.value.data)
const familySummary = computed(() => homeData.family.value.data)
const latestAIReport = computed(() => homeData.ai.value.data?.[0] ?? null)
const dateTransactions = ref<Transaction[]>([])
const dateTransactionsDate = ref('')
watch(optionalSources, () => { void homeData.loadOptional() })
watch(() => auth.sessionGeneration, () => {
  homeData.reset(); dateTransactionsRequestGeneration.begin(); refreshRequests.begin()
  dateTransactions.value = []; dateTransactionsDate.value = ''; dateTransactionsTotal.value = 0
  showDialog.value = false; showGallery.value = false
}, { flush: 'sync' })
const showGallery = ref(false)
const galleryReturnFocus = ref<HTMLElement | null>(null)
const configuringAccount = ref<string | undefined>()
const editingError = ref('')
const canUndo = computed(() => preferences.undoStack.length > 0)
function startEditing() {
  if (!preferences.ready) return toast.error('请先重试加载界面偏好')
  preferences.beginEdit(); preferences.setViewport(widgetViewport.value); editingError.value = ''
}
function cancelEditing() { preferences.cancelEdit(); editingError.value = ''; showGallery.value = false }
async function finishEditing() {
  const result = await preferences.commitEdit()
  if (result.status === 'conflict' && preferences.homeIssue) { editingError.value = preferences.homeIssue === 'unsupported' ? '首页布局来自更高版本，原配置已保留，当前草稿不能保存。' : '首页布局已损坏，请从更多恢复两端默认布局后完成。'; return }
  editingError.value = result.status === 'conflict' ? '布局已在其他标签更新或版本不兼容，草稿已保留。' : result.status === 'failed' ? '布局保存失败，草稿已保留，请重试。' : ''
}
function reloadLatestHome() { if (preferences.reloadHome()) editingError.value = ''; else toast.error('无法载入最新布局，当前草稿已保留') }
function openGallery(id?: string) {
  configuringAccount.value = id
  galleryReturnFocus.value = id
    ? Array.from(widgetGrid.value?.element?.querySelectorAll<HTMLElement>('[data-widget-id]') ?? []).find(el => el.dataset.widgetId === id)?.querySelector<HTMLElement>('.widget-menu-trigger') ?? null
    : document.querySelector<HTMLElement>('[aria-label="添加小组件"]')
  showGallery.value = true
}
function closeGallery(target: HTMLElement | null = galleryReturnFocus.value, reveal = false) {
  showGallery.value = false
  void nextTick(() => {
    const destination = target?.isConnected ? target : document.querySelector<HTMLElement>('[aria-label="添加小组件"]')
    if (reveal) destination?.scrollIntoView({ block: 'nearest', behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' })
    destination?.focus({ preventScroll: true })
  })
}
function addWidget(kind: WidgetKind, size: WidgetSize, accountId?: string) {
  const existing = homeLayout.value.widgets.find(w => w.kind === kind && (w.kind !== 'account' || w.config.accountId === accountId))
  if (existing) {
    const target = Array.from(widgetGrid.value?.element?.querySelectorAll<HTMLElement>('[data-widget-id]') ?? []).find(el => el.dataset.widgetId === existing.id)?.querySelector<HTMLElement>('.widget-drag-handle') ?? null
    closeGallery(target, true)
    return
  }
  try {
    if (configuringAccount.value && kind === 'account' && accountId) { preferences.configureAccount(configuringAccount.value, accountId); closeGallery(); configuringAccount.value = undefined }
    else preferences.addWidget(kind, { accountId }, size)
  } catch { toast.error('组件配置无效，请检查账户是否重复') }
}
const widgetColumns = ref<4 | 2 | 1>(4)
const previewGridWidth = ref(928)
const widgetViewport = ref<'desktop' | 'mobile'>(typeof window !== 'undefined' && window.matchMedia('(max-width: 767px)').matches ? 'mobile' : 'desktop')
const widgetGrid = ref<{ element: HTMLElement | null; cancelDrag: () => void } | null>(null)
let widgetGridObserver: ResizeObserver | null = null
let widgetResizeFrame: number | null = null
let observedWidgetWidth = -1

// Dialog states
const showDialog = ref(false)
const editingId = ref<string | null>(null)

// Computed
const currentMonth = computed(() => dayjs().format('YYYY年M月'))
const isToday = computed(() => selectedDate.value === dayjs().format('YYYY-MM-DD'))
const homeReadModels = computed(() => createHomeReadModels({
  accounts: accountData.value, overview: overview.value, budget: budgetSummary.value, debt: debtSummary.value,
  lending: lendingSummary.value, family: familySummary.value, aiReport: latestAIReport.value,
  recentTransactions: recentTransactions.value, showAmounts: showAmount.value, failures: loadFailures.value,
  budgetDetails: homeData.budgetDetails.value, accountTransactions: homeData.accountTransactions.value,
}))
const transactionTypes = { income: '收入', expense: '支出', transfer: '转账' }
const dateTransactionItems = computed(() => dateTransactions.value.map(transaction => ({
  transaction, presentation: getTransactionPresentation(transaction, showAmount.value),
})))




onMounted(() => {
  loadData()
  if (homeLayout.value.widgets.some(widget => widget.kind === 'calendar')) loadDateTransactions(selectedDate.value)
  updateWidgetColumns()
  if (typeof ResizeObserver !== 'undefined' && widgetGrid.value?.element) {
    widgetGridObserver = new ResizeObserver(entries => {
      const width = entries[0]?.contentRect.width
      if (width === undefined || width === observedWidgetWidth) return
      observedWidgetWidth = width
      if (widgetResizeFrame !== null) return
      widgetResizeFrame = window.requestAnimationFrame(() => {
        widgetResizeFrame = null
        updateWidgetColumns()
      })
    })
    widgetGridObserver.observe(widgetGrid.value.element)
  }
  if (typeof window !== 'undefined') window.addEventListener('resize', updateWidgetColumns)
})

onBeforeUnmount(() => {
  widgetGridObserver?.disconnect()
  if (widgetResizeFrame !== null) window.cancelAnimationFrame(widgetResizeFrame)
  if (typeof window !== 'undefined') window.removeEventListener('resize', updateWidgetColumns)
})

function updateWidgetColumns() {
  if (typeof window === 'undefined') return
  const width = widgetGrid.value?.element?.clientWidth ?? (window.innerWidth - 32)
  previewGridWidth.value = width
  widgetColumns.value = getColumnCount(width)
  const next = window.matchMedia('(max-width: 767px)').matches ? 'mobile' : 'desktop'
  if (next !== widgetViewport.value) widgetGrid.value?.cancelDrag()
  widgetViewport.value = next
  preferences.setViewport(next)
}

watch(ledgerMutationRevision, () => {
  void refreshLedgerData()
})

async function loadData(): Promise<'success' | 'partial' | 'failed' | 'stale'> {
  const result = await homeData.load()
  if (result === 'failed') toast.error('部分核心数据加载失败，请重试')
  return result
}

async function loadDateTransactions(date: string, requestedPage = 1): Promise<'success' | 'failed' | 'stale'> {
  if (selectedDate.value !== date) return 'stale'
  const requestGeneration = dateTransactionsRequestGeneration.begin()
  const ownerGeneration = auth.sessionGeneration
  if (dateTransactionsDate.value !== date) {
    dateTransactions.value = []
    dateTransactionsDate.value = ''
    dateTransactionsTotal.value = 0
    dateTransactionsPage.value = 1
  }
  dateTransactionsLoading.value = true
  dateTransactionsFailed.value = false
  try {
    const res = await transactionApi.getList({
      start_date: date,
      end_date: date,
      page: requestedPage,
      page_size: 100
    })
    if (
      !dateTransactionsRequestGeneration.isLatest(requestGeneration) || auth.sessionGeneration !== ownerGeneration ||
      selectedDate.value !== date
    ) return 'stale'
    dateTransactionsDate.value = date
    dateTransactionsFailed.value = false
    dateTransactionsPage.value = requestedPage
    dateTransactionsTotal.value = res.total ?? res.list.length
    const items = requestedPage === 1 ? res.list : [...dateTransactions.value, ...res.list]
    dateTransactions.value = [...new Map(items.map(item => [item.id, item])).values()].sort((a, b) =>
      new Date(b.transaction_date).getTime() - new Date(a.transaction_date).getTime()
    )
    return 'success'
  } catch {
    if (
      !dateTransactionsRequestGeneration.isLatest(requestGeneration) || auth.sessionGeneration !== ownerGeneration ||
      selectedDate.value !== date
    ) return 'stale'
    dateTransactionsFailed.value = true
    dateFailedPage.value = requestedPage
    return 'failed'
  } finally {
    if (dateTransactionsRequestGeneration.isLatest(requestGeneration)) dateTransactionsLoading.value = false
  }
}

function loadMoreDateTransactions() {
  if (dateTransactionsLoading.value || dateTransactions.value.length >= dateTransactionsTotal.value) return
  void loadDateTransactions(selectedDate.value, dateTransactionsPage.value + 1)
}

async function refresh() {
  const generation = refreshRequests.begin()
  const refreshDate = selectedDate.value
  const refreshCalendar = viewMode.value === 'calendar' || homeLayout.value.widgets.some(widget => widget.kind === 'calendar')
  const result = await loadData()
  if (
    result === 'stale' || !refreshRequests.isLatest(generation)
    || (refreshCalendar && selectedDate.value !== refreshDate)
  ) return
  const [dateResult, calendarResult] = refreshCalendar
    ? await Promise.all([loadDateTransactions(refreshDate), calendarRef.value?.loadData() ?? Promise.resolve('success')])
    : ['success', 'success']
  if (
    !refreshRequests.isLatest(generation) || dateResult === 'stale'
    || (refreshCalendar && selectedDate.value !== refreshDate)
  ) return
  if (dateResult === 'failed') toast.error('所选日期交易刷新失败，请重试')
  else if (calendarResult === 'failed') toast.error('日历金额刷新失败，请重试')
  else if (calendarResult === 'stale') return
  else if (result === 'success') toast.success('刷新成功')
  else if (result === 'partial') toast.warning('核心数据已刷新，部分辅助数据加载失败')
}

function handleDateSelect(date: string) {
  viewMode.value = 'calendar'
  refreshRequests.begin()
  selectedDate.value = date
  loadDateTransactions(date)
}

function formatMoney(value: number | undefined) {
  if (value === undefined) return '—'
  return value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}



function setCalendarRef(kind: WidgetKind, instance: unknown) { if (kind === 'calendar') calendarRef.value = instance as typeof calendarRef.value }

function handleWidgetNavigate(kind: string, accountId?: string) {
  const routes: Record<string, string | { path: string; query?: Record<string, string> }> = {
    netAssets: '/accounts', monthlyFlow: '/statistics', budget: '/budgets',
    reminders: { path: '/reminders', query: { view: 'reminders' } }, transactions: '/transactions',
    accounts: '/accounts', account: accountId ? `/account-logs/${accountId}` : '/accounts',
    calendar: '/transactions', lending: '/lendings', family: '/family', ai: '/ai',
  }
  const destination = routes[kind] ?? '/'
  void router.push(destination)
}




function addTransaction() {
  editingId.value = null
  showDialog.value = true
}

function editTransaction(transaction: Transaction) {
  if (isManagedTransaction(transaction)) return
  editingId.value = transaction.id
  showDialog.value = true
}

async function refreshLedgerData() {
  await Promise.all([
    loadData(),
    homeLayout.value.widgets.some(widget => widget.kind === 'calendar') || viewMode.value === 'calendar'
      ? loadDateTransactions(selectedDate.value) : Promise.resolve('success'),
  ])
}
onBeforeUnmount(() => {
  homeData.invalidate()
  dateTransactionsRequestGeneration.begin()
  refreshRequests.begin()
})

defineExpose({ formatMoney, handleDateSelect, loadMoreDateTransactions, addTransaction, editTransaction, isToday })

</script>

<template>
  <div class="home-page min-h-full bg-[#F2F2F7] dark:bg-[#0B0B0D] pb-24 md:pb-8">
    <div class="home-content max-w-3xl mx-auto px-4 md:px-8">
      <div class="home-heading">
        <div class="home-heading-title"><h1>首页</h1><span>{{ currentMonth }}</span></div>
        <div class="home-heading-actions">
          <button v-if="!preferences.editing" type="button" class="home-edit-trigger" aria-label="编辑小组件" :disabled="!preferences.ready" @click="startEditing"><SlidersHorizontal :size="17" aria-hidden="true" /><span>编辑小组件</span></button>
          <button type="button" class="home-icon-action" :aria-label="showAmount ? '隐藏首页金额' : '显示首页金额'" :title="showAmount ? '隐藏金额' : '显示金额'" @click="showAmount = !showAmount"><component :is="showAmount ? Eye : EyeOff" :size="19" aria-hidden="true" /></button>
          <button type="button" class="home-icon-action" aria-label="刷新首页数据" title="刷新" :disabled="loading" @click="refresh"><RefreshCw :size="18" aria-hidden="true" :class="{ 'animate-spin': loading }" /></button>
        </div>
      </div>
      <div v-if="loadFailures.length" role="alert" class="rounded-xl bg-amber-50 dark:bg-amber-950/30 p-4 text-sm text-amber-800 dark:text-amber-200">
        {{ loadFailures.join('、') }}加载失败；对应数据为上次成功结果或尚未加载。
        <button type="button" class="ml-2 underline" @click="refresh">重试</button>
      </div>
      <div v-if="dateTransactionsFailed && viewMode === 'calendar'" role="alert" class="text-sm text-amber-700">所选日期交易加载失败。<button class="underline" @click="loadDateTransactions(selectedDate, dateFailedPage)">重试</button></div>
      <div v-if="preferences.editing" class="widget-editor-toolbar" role="toolbar" aria-label="首页布局编辑">
        <button type="button" class="widget-add-trigger" aria-label="添加小组件" @click="openGallery()"><Plus :size="18" aria-hidden="true" /><span>添加小组件</span></button>
        <button type="button" class="widget-toolbar-icon" aria-label="撤销布局操作" title="撤销" :disabled="!canUndo" @click="preferences.undoEdit()"><Undo2 :size="18" aria-hidden="true" /></button>
        <details><summary aria-label="更多布局操作" title="更多"><Ellipsis :size="18" aria-hidden="true" /></summary><button type="button" @click="preferences.restoreDefault()">恢复桌面与手机默认布局</button></details>
        <span class="widget-toolbar-spacer" />
        <button type="button" aria-label="取消编辑" @click="cancelEditing">取消</button>
        <button type="button" class="widget-primary" aria-label="完成编辑" @click="finishEditing">完成</button>
      </div>
      <div v-if="editingError" role="alert">{{ editingError }}<button type="button" @click="reloadLatestHome">载入最新布局（放弃当前草稿）</button><button type="button" @click="finishEditing">重试保存</button></div>
      <p v-if="!homeLayout.widgets.length" class="widget-empty">首页还没有小组件。{{ preferences.editing ? '添加小组件，或从更多恢复默认布局。' : '点击编辑小组件开始添加。' }}</p>
      <WidgetGrid :account-names="Object.fromEntries((accountData?.list ?? []).map(account => [account.id, account.name]))" ref="widgetGrid" :layout="homeLayout" :viewport="widgetViewport" :columns="widgetColumns" :editing="preferences.editing" :content-revision="homeReadModels" @move="preferences.moveWidget" @resize="preferences.resizeWidget" @remove="preferences.removeWidget" @configure="openGallery">
        <template #default="{ widget }"><HomeWidget :ref="component => setCalendarRef(widget.kind, component)" :show-amounts="showAmount" :instance="widget" :read-models="homeReadModels" :viewport="widgetViewport" @navigate="handleWidgetNavigate" @select-transaction="editTransaction" @select-date="handleDateSelect" /></template>
      </WidgetGrid>
      <section v-if="homeLayout.widgets.some(w => w.kind === 'calendar') && viewMode === 'calendar'" :inert="preferences.editing || undefined" aria-label="所选日期交易" class="home-widget">
        <h3>{{ selectedDate }} · {{ dateTransactionsTotal }} 笔</h3>
        <p v-if="dateTransactionsLoading">正在加载</p><p v-else-if="dateTransactionsFailed" role="alert">日期交易加载失败。<button type="button" @click="loadDateTransactions(selectedDate, dateFailedPage)">重试日期交易</button></p>
        <button v-for="{ transaction, presentation } in dateTransactionItems" :key="transaction.id" type="button" class="transaction-row" :aria-label="`${transactionTypes[transaction.type]} ${transaction.remark || presentation.title}`" @click="($event.currentTarget as HTMLElement).focus({ preventScroll: true }); editTransaction(transaction)">
          <span>{{ transactionTypes[transaction.type] }}</span>
          <span class="transaction-name">{{ transaction.remark || presentation.title }}</span>
          <strong :class="`amount-${presentation.tone}`">{{ presentation.displayAmount }}</strong>
        </button>
        <button v-if="dateTransactions.length < dateTransactionsTotal" type="button" :disabled="dateTransactionsLoading" @click="loadMoreDateTransactions">加载更多日期交易</button>
      </section>
      <WidgetGallery :show-amounts="showAmount" :columns="widgetColumns" :available-width="previewGridWidth" :initial-size="homeLayout.widgets.find(w => w.id === configuringAccount)?.sizes[widgetViewport]" v-if="showGallery && preferences.editing" :layout="homeLayout" :viewport="widgetViewport" :accounts="accountData?.list ?? []" :accounts-failed="!accountData || loadFailures.includes('账户资产')" :initial-account-id="homeLayout.widgets.find(w => w.id === configuringAccount && w.kind === 'account')?.config.accountId" @close="closeGallery()" @add="addWidget" />
      <!-- Legacy summary cards are replaced by HomeWidget; old semantic assertions remain in the test suite. -->

      <!-- Legacy lending card replaced by HomeWidget. -->

      <!-- The widget grid is the primary home surface; transaction list/calendar remain available from their business pages. -->
    </div>

    <!-- Transaction Dialog -->
    <TransactionDialog
      v-model:visible="showDialog"
      :edit-id="editingId"
    />
  </div>
</template>
