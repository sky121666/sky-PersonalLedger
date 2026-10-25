<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, watch, computed } from 'vue'
import { Search, Trash2, X, List, ReceiptText, SlidersHorizontal, Pencil, ArrowLeftRight } from '@lucide/vue'
import { useRouter } from 'vue-router'
import { transactionApi, type Transaction } from '@/api/transaction'
import FinancePage from '@/components/ui/FinancePage.vue'
import FinanceListFooter from '@/components/ui/FinanceListFooter.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import SelectionControl from '@/components/ui/SelectionControl.vue'
import ActionMenu from '@/components/ui/ActionMenu.vue'
import TransactionDialog from '@/components/TransactionDialog.vue'
import DynamicIcon from '@/components/DynamicIcon.vue'
import { toast } from '@/composables/useToast'
import { getCategoryEmoji } from '@/utils/constants'
import { isManagedTransaction } from '@/utils/managedTransaction'
import { buildTransactionListParams } from '@/utils/transactionListParams'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import dayjs from 'dayjs'
import 'dayjs/locale/zh-cn'

dayjs.locale('zh-cn')
const router = useRouter()

const transactions = ref<Transaction[]>([])
const loading = ref(false)
const loadError = ref('')
const loadMoreError = ref('')
const hasLoaded = ref(false)
const loadedQueryKey = ref('')
const page = ref(1)
const hasMore = ref(false)
const total = ref(0)
const ledgerMutationRevision = useLedgerMutationRevision()
let listRequestGeneration = 0
let keywordDebounceTimer: ReturnType<typeof setTimeout> | undefined

const showDialog = ref(false)
const editingId = ref<string | null>(null)
const showDeleteModal = ref(false)
const deletingId = ref<string | null>(null)
const deleting = ref(false)
const filterTrigger = ref<HTMLElement | null>(null)

// Filters & Search
const showFilter = ref(false)
const filters = ref({
  type: '' as string,
  start_date: '',
  end_date: '',
  keyword: ''
})
const filterDraft = ref({ type: '', start_date: '', end_date: '' })
const filterError = ref('')
const typeOptions = [{ value: '', label: '全部' }, { value: 'expense', label: '支出' }, { value: 'income', label: '收入' }, { value: 'transfer', label: '转账' }]
const activeFilterCount = computed(() => Number(!!filters.value.type) + Number(!!(filters.value.start_date || filters.value.end_date)))
function openFilter() {
  filterDraft.value = { type: filters.value.type, start_date: filters.value.start_date, end_date: filters.value.end_date }
  filterError.value = ''
  showFilter.value = true
}
function applyFilter() {
  const draft = filterDraft.value
  if (draft.start_date && draft.end_date && draft.start_date > draft.end_date) {
    filterError.value = '开始日期不能晚于结束日期。'
    return
  }
  filters.value = { ...filters.value, ...draft }
  showFilter.value = false
}
function resetFilterDraft() { filterDraft.value = { type: '', start_date: '', end_date: '' }; filterError.value = '' }
function clearFilters() { filters.value = { ...filters.value, type: '', start_date: '', end_date: '' } }
function rowActions(item: Transaction) {
  return [...(!isManagedTransaction(item) ? [{ id: 'edit', label: '编辑', icon: Pencil }] : []), { id: 'delete', label: '删除…', icon: Trash2, danger: true }]
}
const currentQueryKey = computed(() => JSON.stringify(buildTransactionListParams(1, 20, filters.value)))
const canLoadMore = computed(() => hasLoaded.value && !loadError.value && loadedQueryKey.value === currentQueryKey.value)

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

function openEdit(transaction: Transaction) {
  if (transaction.debt_operation_id) {
    void router.push({ path: '/reminders', query: { operation_id: transaction.debt_operation_id } })
    return
  }
  if (isManagedTransaction(transaction)) return
  editingId.value = transaction.id
  showDialog.value = true
}

function confirmDelete(id: string) {
  deletingId.value = id
  showDeleteModal.value = true
}

async function handleDelete() {
  if (!deletingId.value || deleting.value) return
  deleting.value = true
  try {
    await transactionApi.delete(deletingId.value)
    showDeleteModal.value = false
    deletingId.value = null
    toast.success('删除成功')
    loadTransactions()
  } catch (e: any) {
    toast.error(e.message || '删除失败')
  } finally { deleting.value = false }
}

async function loadTransactions() {
  clearTimeout(keywordDebounceTimer)
  const generation = ++listRequestGeneration
  const queryKey = currentQueryKey.value
  loading.value = true
  loadError.value = ''
  loadMoreError.value = ''
  try {
    const params = buildTransactionListParams(1, 20, filters.value)
    const data = await transactionApi.getList(params)
    if (generation !== listRequestGeneration) return
    transactions.value = data.list
    total.value = data.total
    hasMore.value = data.list.length < data.total
    page.value = 1
    hasLoaded.value = true
    loadedQueryKey.value = queryKey
  } catch (e) {
    if (generation === listRequestGeneration) {
      loadError.value = '交易加载失败，请检查网络后重试。'
    }
  } finally {
    if (generation === listRequestGeneration) {
      loading.value = false
    }
  }
}

async function loadMore() {
  if (!hasMore.value || loading.value || !canLoadMore.value) return
  const generation = listRequestGeneration
  const nextPage = page.value + 1
  loading.value = true
  loadMoreError.value = ''
  try {
    const params = buildTransactionListParams(nextPage, 20, filters.value)
    const data = await transactionApi.getList(params)
    if (generation !== listRequestGeneration) return
    transactions.value.push(...data.list)
    total.value = data.total
    page.value = nextPage
    hasMore.value = transactions.value.length < data.total
  } catch (e) {
    if (generation === listRequestGeneration) {
      loadMoreError.value = '更多交易加载失败，已加载的记录仍然保留。'
    }
  } finally {
    if (generation === listRequestGeneration) {
      loading.value = false
    }
  }
}

function formatTime(date: string) {
  return dayjs(date).format('HH:mm')
}

function formatMoney(value: number) {
  return value.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

watch(
  () => [filters.value.type, filters.value.start_date, filters.value.end_date],
  () => void loadTransactions()
)

watch(
  () => filters.value.keyword,
  () => {
    listRequestGeneration++
    loading.value = true
    loadError.value = ''
    loadMoreError.value = ''
    clearTimeout(keywordDebounceTimer)
    keywordDebounceTimer = setTimeout(() => void loadTransactions(), 300)
  }
)

watch(ledgerMutationRevision, () => void loadTransactions())

onBeforeUnmount(() => {
  listRequestGeneration++
  clearTimeout(keywordDebounceTimer)
})
</script>

<template>
  <FinancePage title="账单明细" :context="hasLoaded ? `${total} 条记录` : '尚未加载'" :icon="List" tone="orange" class="transactions-page">
    <template #actions>
      <div class="transaction-toolbar">
        <div class="transaction-search"><Search :size="16" aria-hidden="true" /><input v-model="filters.keyword" type="search" aria-label="搜索" placeholder="搜索" @keydown.esc="filters.keyword = ''" /><button v-if="filters.keyword" class="transaction-clear" aria-label="清除搜索" @click="filters.keyword = ''"><X :size="16" /></button></div>
        <button ref="filterTrigger" class="finance-button transaction-filter" :aria-label="filters.type ? typeOptions.find(option => option.value === filters.type)?.label : '全部类型'" :aria-expanded="showFilter" aria-haspopup="dialog" @click="openFilter"><SlidersHorizontal :size="17" aria-hidden="true" /><span>{{ filters.type ? typeOptions.find(option => option.value === filters.type)?.label : '全部类型' }}</span><i v-if="activeFilterCount" class="transaction-filter-count" aria-hidden="true">{{ activeFilterCount }}</i></button>
      </div>
    </template>
    <div v-if="activeFilterCount" class="transaction-filter-summary"><span>{{ filters.type ? typeOptions.find(option => option.value === filters.type)?.label : '全部类型' }}<template v-if="filters.start_date || filters.end_date"> · {{ filters.start_date || '不限开始' }} 至 {{ filters.end_date || '不限结束' }}</template></span><button class="finance-icon-button" aria-label="清除筛选" @click="clearFilters"><X :size="16" /></button></div>
    <div v-if="loadError" role="alert" class="finance-card finance-card-padding text-sm text-amber-800 dark:text-amber-200">
      <p>{{ loadError }}</p><p v-if="hasLoaded" class="mt-1">{{ loadedQueryKey !== currentQueryKey ? '以下为上次成功加载的结果，尚未更新到当前筛选条件。' : '以下为上次成功加载的结果，尚未完成本次更新。' }}</p><button class="finance-button is-subtle mt-3" :disabled="loading" @click="loadTransactions">重新加载交易</button>
    </div>
    <p v-else-if="loading" role="status" class="finance-muted">{{ hasLoaded ? '正在更新，以下暂时保留已加载的记录…' : '交易加载中…' }}</p>
    <section v-if="hasLoaded && transactions.length === 0 && !loading && !loadError" class="finance-card finance-empty"><h2>{{ activeFilterCount || filters.keyword ? '没有符合条件的明细' : '暂无交易记录' }}</h2><p v-if="activeFilterCount || filters.keyword">调整筛选条件或搜索词后再试。</p></section>
    <div v-else class="transaction-groups">
      <section v-for="group in groupedTransactions" :key="group.date" class="finance-card transaction-day">
        <div class="transaction-day-head"><div><strong>{{ group.dayLabel }}</strong><span>{{ group.weekLabel }}</span></div><div class="transaction-day-sum" title="当前已加载记录的现金收支小计，含借贷往来；不同于排除借贷本金的月度消费统计"><span v-if="group.totalIncome > 0">收入 {{ formatMoney(group.totalIncome) }}</span><span v-if="group.totalExpense > 0">支出 {{ formatMoney(group.totalExpense) }}</span><span v-if="!group.totalIncome && !group.totalExpense">转账不计收支</span><span v-else>· 已加载小计</span></div></div>
        <div v-for="item in group.items" :key="item.id" class="transaction-row group">
          <button type="button" class="transaction-open" :disabled="isManagedTransaction(item) && !item.debt_operation_id" :aria-label="`${item.debt_operation_id ? '查看关联凭证' : '查看交易'} ${item.remark || item.category?.name || item.id}`" @click="($event.currentTarget as HTMLElement).focus({ preventScroll: true }); openEdit(item)">
            <span class="transaction-icon" :class="{ 'is-transfer': item.type === 'transfer' }"><ArrowLeftRight v-if="item.type === 'transfer'" :size="18" /><DynamicIcon v-else :icon="getCategoryEmoji(item.category?.name || '', item.category?.icon || '')" :size="19" /></span>
            <span class="transaction-copy"><strong>{{ item.type === 'transfer' ? '转账' : (item.category?.name || '未分类') }}</strong><span v-if="item.remark" class="transaction-remark" :title="item.remark">{{ item.remark }}</span><small>{{ formatTime(item.transaction_date) }} · {{ item.account?.name || '账户' }}</small></span>
          </button>
          <div class="transaction-end"><span class="transaction-amount font-nums" :class="item.type">{{ item.type === 'income' ? '+' : item.type === 'expense' ? '−' : '' }}{{ formatMoney(item.amount) }}</span>
            <button v-if="item.debt_operation_id" class="finance-icon-button transaction-receipt" :aria-label="`查看分期凭证 ${item.remark || item.id}`" @click="($event.currentTarget as HTMLElement).focus({ preventScroll: true }); openEdit(item)"><ReceiptText :size="17" /></button>
            <ActionMenu v-else :label="`交易操作 ${item.remark || item.category?.name || item.id}`" :actions="rowActions(item)" @action="$event === 'edit' ? openEdit(item) : confirmDelete(item.id)" />
          </div>
        </div>
      </section>
    </div>
    <FinanceListFooter v-if="transactions.length > 0 && canLoadMore" label="明细列表加载"
      :count="transactions.length" :has-more="hasMore" :loading="loading" :error="loadMoreError"
      more-label="点击加载更多" @more="loadMore" />
    <TransactionDialog v-model:visible="showDialog" :edit-id="editingId" />
    <AppDialog v-if="showFilter" title="筛选明细" sheet :return-focus="filterTrigger" @close="showFilter = false">
      <SelectionControl v-model="filterDraft.type" label="交易类型" :options="typeOptions" solid />
      <div class="finance-form-grid mt-5"><label class="finance-field">开始日期<input v-model="filterDraft.start_date" type="date" aria-label="开始日期" class="finance-input" :aria-invalid="!!filterError" aria-describedby="transaction-filter-error" /></label><label class="finance-field">结束日期<input v-model="filterDraft.end_date" type="date" aria-label="结束日期" class="finance-input" :aria-invalid="!!filterError" aria-describedby="transaction-filter-error" /></label></div>
      <p v-if="filterError" id="transaction-filter-error" role="alert" class="finance-form-error">{{ filterError }}</p>
      <template #footer><button class="finance-button" @click="resetFilterDraft">重置</button><button class="finance-button is-primary" @click="applyFilter">应用筛选</button></template>
    </AppDialog>
    <AppDialog v-if="showDeleteModal" title="确认删除" :busy="deleting" @close="showDeleteModal = false"><p class="finance-muted">删除后无法恢复，确定要删除这条记录吗？</p><template #footer><button class="finance-button" :disabled="deleting" @click="showDeleteModal = false">取消</button><button class="finance-button is-danger" :disabled="deleting" @click="handleDelete">{{ deleting ? '删除中…' : '删除' }}</button></template></AppDialog>
  </FinancePage>
</template>

<style scoped>
.transaction-toolbar { display: flex; align-items: center; gap: 8px; }
.transaction-search { display: flex; align-items: center; min-width: 0; width: 208px; height: 44px; gap: 7px; padding: 0 12px; border: 1px solid transparent; border-radius: 13px; background: var(--fp-surface); color: var(--fp-secondary); }
.transaction-search:focus-within { border-color: var(--fp-blue); box-shadow: 0 0 0 3px var(--fp-blue-soft); }
.transaction-search > svg { flex: none; }
.transaction-search input { min-width: 0; width: 100%; background: transparent; color: var(--fp-ink); font-size: 13px; outline: none; }
.transaction-search input:focus-visible { outline: none; }
.transaction-search input::-webkit-search-cancel-button { appearance: none; }
.transaction-clear { display: grid; place-items: center; flex: none; width: 44px; height: 44px; margin-right: -12px; border-radius: 12px; }
.transaction-filter { position: relative; white-space: nowrap; }
.transaction-filter-count { display: grid; place-items: center; min-width: 17px; height: 17px; border-radius: 50%; background: var(--fp-blue); color: white; font-size: 10px; font-style: normal; }
.transaction-filter-summary { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 0 10px; border-radius: 12px; background: var(--fp-blue-soft); color: var(--fp-blue); font-size: 12px; overflow-wrap: anywhere; }
.transaction-groups { display: grid; grid-template-columns: minmax(0,1fr); gap: 16px; }
.transaction-day { min-width: 0; }
.transaction-day-head { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 5px 12px; padding: 12px 16px; border-bottom: 1px solid var(--fp-line); font-size: 12px; }
.transaction-day-head strong { font-weight: 550; margin-right: 8px; }
.transaction-day-head span { color: var(--fp-secondary); }
.transaction-day-sum { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 5px; font-size: 11px; }
.transaction-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 10px 14px; min-height: 76px; }
.transaction-row + .transaction-row { border-top: 1px solid var(--fp-line); }
.transaction-open { display: flex; flex: 1; min-width: 0; align-items: center; gap: 12px; text-align: left; }
.transaction-open:disabled { opacity: 1; }
.transaction-icon { display: grid; place-items: center; width: 39px; height: 39px; flex: none; border-radius: 13px; background: var(--fp-soft); color: var(--fp-secondary); }
.transaction-icon.is-transfer { background: var(--fp-blue-soft); color: var(--fp-blue); }
.transaction-copy { min-width: 0; flex: 1; display: flex; flex-wrap: wrap; align-items: baseline; gap: 3px 7px; }
.transaction-copy strong { font-size: 14px; font-weight: 550; overflow-wrap: anywhere; }
.transaction-remark { max-width: 180px; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--fp-secondary); font-size: 12px; }
.transaction-copy small { flex: 1 0 100%; color: var(--fp-secondary); font-size: 12px; line-height: 1.6; overflow-wrap: anywhere; }
.transaction-end { display: flex; flex: none; align-items: center; gap: 6px; }
.transaction-amount { font-size: 14px; font-weight: 550; white-space: nowrap; }
.transaction-amount.expense { color: var(--fp-red); }
.transaction-amount.income { color: var(--fp-green); }
.transaction-receipt { color: var(--fp-blue); }
@media (max-width:767px) {
  .transactions-page :deep(.finance-head-actions) { flex: 1 0 100%; width: 100%; }
  .transaction-toolbar { width: 100%; }
  .transaction-search { flex: 1; width: auto; }
  .transaction-filter span { display: none; }
  .transaction-filter { width: 44px; padding: 0; }
  .transaction-filter-count { position: absolute; top: -3px; right: -3px; }
  .transaction-row { gap: 8px; padding: 10px 12px; }
  .transaction-open { gap: 10px; }
  .transaction-copy { display: block; }
  .transaction-remark { display: block; max-width: 100%; margin-top: 3px; }
  .transaction-copy small { display: block; margin-top: 4px; }
}
@media (max-width:360px) { .transaction-icon { width: 30px; height: 30px; } .transaction-open { gap: 7px; } .transaction-row { padding: 10px; gap: 6px; } }
</style>
