<script setup lang="ts">
import { computed, ref, watch, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChevronLeft, Layers, Plus, RefreshCw, ArrowUpRight, ReceiptText, RotateCcw } from '@lucide/vue'
import OptionPicker from '@/components/ui/OptionPicker.vue'
import DebtModal from '@/components/debt/DebtModal.vue'
import FinanceListFooter from '@/components/ui/FinanceListFooter.vue'
import DebtAllocationFields from '@/components/debt/DebtAllocationFields.vue'
import { useDebtWorkspace } from '@/composables/useDebtWorkspace'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { debtApi, type DebtPlan, type DebtOperation, type DebtCommand, type DebtOperationDetails } from '@/api/debt'
import { buildDebtAllocation, buildDebtParts, buildDebtPayment, debtAmount, debtCents, formatDebtMoney, sumDebtCents,
  type DebtPartInput, type DebtPaymentInput } from '@/utils/debtAmounts'
import dayjs from 'dayjs'

const props = defineProps<{ embedded?: boolean; active?: boolean }>()
const route = useRoute()
const router = useRouter()
const workspace = useDebtWorkspace()
const { capabilities, accounts, plans, operations, loading, hasLoaded, loadError, pending, journalError,
  saving, writeError, detail, detailLoading, detailError, supported, canWrite,
  hasMoreOperations, historyLoading, historyError } = workspace
const scope = ref(typeof route.query.account_id === 'string' ? route.query.account_id : 'all')
const operationPlanId = ref('')
const historyRegion = ref<HTMLElement | null>(null)
const revision = useLedgerMutationRevision()
const managedAccounts = computed(() => accounts.value.filter(account => account.debt_tracking_mode === 'managed'))
const currentAccount = computed(() => accounts.value.find(account => account.id === scope.value))
const scopeOptions = computed(() => [
  { value: 'all', label: '全部计划' },
  ...managedAccounts.value.map(account => ({ value: account.id, label: `${account.name}${account.is_archived ? '（已归档）' : ''}`, detail: `账户欠款 ¥${formatDebtMoney(account.current_balance)}` })),
  ...(currentAccount.value && currentAccount.value.debt_tracking_mode !== 'managed' ? [{ value: scope.value, label: `${currentAccount.value.name}（旧模式）` }] : []),
  { value: 'standalone', label: '独立计划', detail: '不关联账户的计划' },
])
const legacyScope = computed(() => currentAccount.value && currentAccount.value.debt_tracking_mode !== 'managed')
const reviewNeeded = computed(() => (currentAccount.value?.debt_unclassified ?? 0) !== 0)
const accountUsable = computed(() => currentAccount.value?.debt_tracking_mode === 'managed' &&
  !currentAccount.value.is_archived && !reviewNeeded.value)
const visiblePlans = computed(() => plans.value.filter(plan =>
  scope.value === 'all' || (scope.value === 'standalone' ? !plan.account_id : plan.account_id === scope.value)))
const visibleOperations = computed(() => operations.value.filter(op => scope.value !== 'standalone' || op.standalone_plan_id))
const totals = computed(() => visiblePlans.value.reduce((sum, plan) => ({
  principal: sum.principal + plan.principal_balance, interest: sum.interest + plan.interest_balance,
  paid: sum.paid + plan.principal_paid + plan.interest_paid,
}), { principal: 0, interest: 0, paid: 0 }))
const sourceAccounts = computed(() => accounts.value.filter(account => !account.is_archived && account.id !== currentAccount.value?.id))
const dialog = ref<'' | 'plan' | 'payment' | 'allocation' | 'interest' | 'reverse'>('')
const showOperation = ref(false)
const dialogTrigger = ref<HTMLElement | null>(null)
const workspaceHeading = ref<HTMLElement | null>(null)
const actionError = ref('')
const targetedPlan = ref<DebtPlan | null>(null)
const actionOperation = ref<DebtOperationDetails | null>(null)
const replacing = ref<DebtOperationDetails | null>(null)
const allocationLoading = ref(false)
const allocationReady = ref(false)
let allocationGeneration = 0
const planForm = ref({ name: '', target: '', original: '', principal: '', booked: '', estimated: '' })
const paymentForm = ref<DebtPaymentInput>({ amount: '', source_kind: 'account', source_account_id: '', unplanned_amount: '', unapplied_amount: '', occurred_at: '' })
const parts = ref<DebtPartInput[]>([])
const interestForm = ref({ amount: '', occurred_at: '' })
const allocationUnplanned = ref('')
const activeFormPlans = ref<DebtPlan[]>([])
const availableCents = computed(() => {
  const amount = actionOperation.value?.unallocated_amount
  if (typeof amount !== 'number' || !Number.isFinite(amount) || amount < 0) return null
  return sumDebtCents(Math.round(amount * 100), Math.round((replacing.value?.operation.amount ?? 0) * 100))
})
const partSummary = computed(() => {
  try {
    return formatDebtMoney(debtAmount(sumDebtCents(buildDebtParts(parts.value).totalCents,
      debtCents(dialog.value === 'allocation' ? allocationUnplanned.value : paymentForm.value.unplanned_amount),
      dialog.value === 'payment' ? debtCents(paymentForm.value.unapplied_amount) : 0)))
  } catch { return '金额待核对' }
})
const allocationDifference = computed(() => {
  if (dialog.value !== 'payment') return null
  try {
    return sumDebtCents(buildDebtParts(parts.value).totalCents,
      debtCents(paymentForm.value.unplanned_amount), debtCents(paymentForm.value.unapplied_amount)) - debtCents(paymentForm.value.amount, '付款金额')
  } catch { return null }
})
const paymentReady = computed(() => {
  if (dialog.value !== 'payment') return true
  try { return allocationDifference.value === 0 && debtCents(paymentForm.value.amount) > 0 } catch { return false }
})
const dialogTitle = computed(() => ({ plan: '新建分期计划', payment: '登记付款', allocation: replacing.value ? '重新分配' : '分配付款',
  interest: '登记已入账利息', reverse: '撤销分期操作', '': '' })[dialog.value])

async function loadData() {
  await workspace.loadData(!['all', 'standalone'].includes(scope.value) ? scope.value : '', {
    ...(operationPlanId.value ? { plan_id: operationPlanId.value } : {}),
    ...(scope.value === 'standalone' ? { standalone_only: true } : {}),
  })
}
watch(scope, () => {
  operationPlanId.value = ''
  closeDialog()
  const routeScope = typeof route.query.account_id === 'string' ? route.query.account_id : 'all'
  if (scope.value !== routeScope) {
    closeDetails()
    void router.replace({ path: '/reminders', query: scope.value === 'all' ? {} : { account_id: scope.value } })
  } else if (typeof route.query.operation_id !== 'string') closeDetails()
  void loadData()
})
watch(operationPlanId, () => void loadData())
watch(revision, () => void loadData())
watch(() => props.active, active => {
  if (active !== false) return
  closeDialog()
  closeDetails()
})
watch(() => route.query.account_id, id => {
  const value = typeof id === 'string' ? id : 'all'
  if (value !== scope.value) scope.value = value
})
watch(() => route.query.operation_id, id => { if (typeof id === 'string') void openOperation(id) })
void loadData().then(() => { if (typeof route.query.operation_id === 'string' && supported.value) void openOperation(route.query.operation_id) })

function scopeName(id: string | null) { return id ? accounts.value.find(account => account.id === id)?.name || '关联账户' : '独立计划' }
function planName(id: string) { return plans.value.find(plan => plan.id === id)?.name || '分期计划' }
async function showPlanHistory(plan: DebtPlan) {
  operationPlanId.value = plan.id
  await nextTick()
  historyRegion.value?.scrollIntoView({ block: 'start' })
}
function operationName(op: DebtOperation) {
  return ({ account_open: '账户期初', plan_open: '建立计划', payment: '登记付款', transfer_payment: '转账待分配',
    allocation: '付款分配', interest_charge: '利息入账', account_change: '账户变动', reversal: '纠错撤销' } as Record<string, string>)[op.kind] || '财务操作'
}
function planStatus(plan: DebtPlan) { return ({ active: '还款中', cleared: '当前余额已还清', cancelled: '已取消' })[plan.status] }
function emptyParts(items: DebtPlan[]) { return items.map(plan => ({ plan_id: plan.id, principal: '', booked_interest: '', cash_interest: '' })) }
function resetAction() { actionError.value = ''; writeError.value = ''; replacing.value = null }
function closeDialog() {
  if (saving.value) return
  allocationGeneration += 1
  dialog.value = ''
  allocationLoading.value = false
  actionError.value = ''
}
function rememberTrigger(event?: Event) {
  if (!event) return
  const target = event.currentTarget
  // Pointer clicks do not focus buttons in every browser. Keep the page
  // trigger when moving from a receipt to an action dialog.
  if (target instanceof HTMLElement && !target.closest('[role="dialog"]')) dialogTrigger.value = target
}
function openPlan(event?: Event) {
  if (!canWrite.value) return
  rememberTrigger(event)
  resetAction()
  planForm.value = { name: '', target: accountUsable.value ? scope.value : 'standalone', original: '', principal: '', booked: '', estimated: '' }
  dialog.value = 'plan'
}
function openPayment(plan?: DebtPlan, event?: Event) {
  if (!canWrite.value || (plan?.account_id ? !accountUsable.value : !plan && !accountUsable.value)) return
  rememberTrigger(event)
  resetAction()
  targetedPlan.value = plan?.account_id ? null : plan ?? null
  const items = plan && !plan.account_id ? [plan] : plans.value.filter(item => item.account_id === currentAccount.value?.id && item.status !== 'cancelled')
  activeFormPlans.value = items
  parts.value = emptyParts(items)
  paymentForm.value = { amount: '', source_kind: 'account', source_account_id: '', unplanned_amount: '', unapplied_amount: '', occurred_at: dayjs().format('YYYY-MM-DDTHH:mm') }
  dialog.value = 'payment'
}
function openInterest(plan: DebtPlan, event?: Event) {
  if (!canWrite.value || plan.status === 'cancelled') return
  rememberTrigger(event)
  resetAction()
  targetedPlan.value = plan
  interestForm.value = { amount: '', occurred_at: dayjs().format('YYYY-MM-DDTHH:mm') }
  dialog.value = 'interest'
}
async function openOperation(id: string, event?: Event) {
  rememberTrigger(event)
  showOperation.value = true
  await workspace.openOperation(id)
}
function closeDetails() { showOperation.value = false; workspace.closeOperation() }

async function openAllocation(parent: DebtOperationDetails, replacement?: DebtOperation) {
  if (!canWrite.value || parent.operation.reversed_by) return
  const generation = ++allocationGeneration
  resetAction()
  actionOperation.value = parent
  dialog.value = 'allocation'
  showOperation.value = false
  allocationLoading.value = true
  allocationReady.value = false
  try {
    const current = await debtApi.details(parent.operation.id)
    const prior = replacement ? await debtApi.details(replacement.id) : null
    if (generation !== allocationGeneration) return
    if (current.operation.reversed_by || (prior && (prior.operation.reversed_by || prior.operation.payment_id !== current.operation.id))) throw Error('该付款或分配已变更，请重新打开凭证')
    actionOperation.value = current
    replacing.value = prior
    activeFormPlans.value = plans.value.filter(plan => plan.account_id === current.operation.account_id && plan.status !== 'cancelled')
    parts.value = emptyParts(activeFormPlans.value).map(row => {
      const old = prior?.allocations?.find(item => item.plan_id === row.plan_id)
      return old ? { ...row, principal: String(old.principal_paid_delta), booked_interest: String(old.interest_paid_delta), cash_interest: '' } : row
    })
    allocationUnplanned.value = prior ? String(prior.operation.unplanned_payment) : ''
    if (availableCents.value === null || !Array.isArray(current.active_allocations)) throw Error('后端尚未提供完整的付款额度，请更新后端后再分配')
    allocationReady.value = true
  } catch (error) { if (generation === allocationGeneration) actionError.value = (error as Error).message }
  finally { if (generation === allocationGeneration) allocationLoading.value = false }
}

function openReverse(value: DebtOperationDetails) {
  if (!canWrite.value || value.operation.reversed_by || ['account_open', 'reversal'].includes(value.operation.kind)) return
  resetAction()
  actionOperation.value = value
  showOperation.value = false
  dialog.value = 'reverse'
}

async function submitDialog() {
  if (saving.value || !canWrite.value || allocationLoading.value) return
  actionError.value = ''
  try {
    let command: DebtCommand
    if (dialog.value === 'plan') {
      const form = planForm.value
      const original = debtCents(form.original, '原始本金'), principal = debtCents(form.principal, '开始追踪时本金')
      if (!form.name.trim() || [...form.name.trim()].length > 100 || principal > original) throw Error('请输入有效计划名称，开始追踪时本金不能超过原始本金')
      const account = managedAccounts.value.find(item => item.id === form.target)
      if (form.target !== 'standalone' && (!account || account.is_archived || account.debt_unclassified)) throw Error('请选择可使用的多分期账户')
      const booked = debtCents(form.booked, '已入账利息')
      if (account && sumDebtCents(principal, booked) > Math.round((account.unplanned_debt ?? 0) * 100)) throw Error('计划本金与已入账利息不能超过未归计划欠款')
      command = { kind: 'plan', target: form.target, payload: {
        name: form.name.trim(), scope: account ? 'account' : 'standalone', ...(account ? { account_id: account.id } : {}),
        original_principal: debtAmount(original), opening_principal: debtAmount(principal), booked_interest: debtAmount(booked),
        ...(form.estimated.trim() ? { estimated_interest: debtAmount(debtCents(form.estimated, '预计利息')) } : {}),
      } }
    } else if (dialog.value === 'payment') {
      const independent = targetedPlan.value
      if (!independent && !accountUsable.value) throw Error('当前账户不可付款，请重新加载核对')
      if (paymentForm.value.source_kind === 'account' && !sourceAccounts.value.some(account => account.id === paymentForm.value.source_account_id)) throw Error('请选择有效付款账户')
      command = { kind: 'payment', target: independent?.id || scope.value,
        payload: buildDebtPayment(paymentForm.value, parts.value, independent ? { standalone_plan_id: independent.id } : { account_id: scope.value }, capabilities.value?.external_cash_interest === true) }
    } else if (dialog.value === 'allocation') {
      if (!allocationReady.value || availableCents.value === null || !actionOperation.value) throw Error('付款额度不可用，请重新加载凭证')
      command = { kind: 'allocation', target: actionOperation.value.operation.id,
        payload: buildDebtAllocation(parts.value, allocationUnplanned.value, availableCents.value, replacing.value?.operation.id) }
    } else if (dialog.value === 'interest') {
      const amount = debtCents(interestForm.value.amount, '入账利息')
      if (!amount || !targetedPlan.value) throw Error('入账利息须大于零')
      command = { kind: 'interest', target: targetedPlan.value.id, payload: { amount: debtAmount(amount),
        ...(interestForm.value.occurred_at ? { occurred_at: new Date(interestForm.value.occurred_at).toISOString() } : {}) } }
    } else if (dialog.value === 'reverse' && actionOperation.value) {
      command = { kind: 'reversal', target: actionOperation.value.operation.id, payload: {} }
    } else return
    if (await workspace.execute(command)) {
      dialog.value = ''
      closeDetails()
      await loadData()
    }
  } catch (error) { actionError.value = (error as Error).message }
}

async function confirmPending() {
  if (await workspace.execute()) { dialog.value = ''; closeDetails(); await loadData() }
}
defineExpose({ refresh: loadData, loading, saving })
</script>

<template>
  <div class="text-gray-900 dark:text-white" :class="props.embedded ? '' : 'min-h-full bg-[#F2F2F7] pb-10 dark:bg-black'">
    <header v-if="!props.embedded" class="sticky top-0 z-30 border-b border-gray-200/50 bg-white/70 px-4 py-4 backdrop-blur-xl dark:border-white/10 dark:bg-[#1C1C1E]/70 md:px-8">
      <div class="mx-auto flex max-w-3xl items-center justify-between gap-3">
        <div class="flex min-w-0 items-center gap-3">
          <button aria-label="返回我的钱包" class="-ml-2 flex h-11 w-11 shrink-0 items-center justify-center rounded-xl text-gray-500 hover:bg-black/5 dark:hover:bg-white/10" @click="router.push('/accounts')"><ChevronLeft :size="20" /></button>
          <div class="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-blue-500 to-blue-600 text-white shadow-lg shadow-blue-500/20"><Layers :size="24" /></div>
          <div class="min-w-0"><h1 ref="workspaceHeading" tabindex="-1" class="text-xl font-bold">分期管理</h1><p class="mt-0.5 text-xs leading-relaxed text-gray-500">每笔计划清楚，每次付款有据</p></div>
        </div>
        <button aria-label="刷新分期数据" :disabled="loading || saving" class="debt-icon" @click="loadData"><RefreshCw :size="19" :class="{ 'animate-spin': loading }" /></button>
      </div>
    </header>

    <div class="mx-auto max-w-3xl space-y-5" :class="props.embedded ? '' : 'px-4 py-6 md:px-8'">
      <h2 v-if="props.embedded" ref="workspaceHeading" tabindex="-1" class="sr-only">账户与分期</h2>
      <div v-if="loadError" role="alert" class="debt-warning">
        <p>{{ loadError }}</p><p v-if="hasLoaded" class="mt-1">以下保留上次加载结果，新的财务操作暂已停用。</p>
        <button class="debt-text-button mt-2" :disabled="loading" @click="loadData">重新加载</button>
      </div>
      <p v-else-if="loading" role="status" class="text-sm text-gray-500">{{ hasLoaded ? '分期数据更新中…' : '正在加载分期…' }}</p>
      <div v-if="hasLoaded && !supported && !loadError" class="debt-panel p-6">
        <h2 class="font-bold">当前后端尚未开放多分期管理</h2>
        <p class="mt-2 text-sm leading-relaxed text-gray-500">现有账户和旧模式还款继续使用。更新后端后，可为新负债账户启用多分期。</p>
        <button class="debt-primary mt-4" @click="router.push('/accounts')">返回我的钱包</button>
      </div>
      <template v-if="supported && hasLoaded">
        <div v-if="journalError" role="alert" class="debt-warning">{{ journalError }}<button class="debt-text-button ml-2" @click="loadData">重试读取</button></div>
        <div v-if="pending" role="alert" class="debt-warning space-y-2">
          <h2 class="font-bold">上次操作结果尚未确认</h2>
          <p class="text-sm leading-relaxed">原金额、目标和请求已保留。确认结果会重发同一请求，不会新建一笔付款。确认前暂停新的财务操作。</p>
          <p class="break-all text-xs">操作：{{ pending.kind === 'payment' ? '登记付款' : pending.kind === 'allocation' ? '付款分配' : pending.kind === 'plan' ? '新建计划' : pending.kind === 'interest' ? '利息入账' : '纠错撤销' }}<span v-if="'amount' in pending.payload"> · ¥{{ formatDebtMoney(Number(pending.payload.amount)) }}</span></p>
          <button :disabled="saving" class="debt-primary" @click="confirmPending">{{ saving ? '正在确认…' : '确认上次操作结果' }}</button>
        </div>
        <p v-if="writeError && !dialog" role="alert" class="debt-warning">{{ writeError }}</p>

        <div v-if="!managedAccounts.some(account => !account.is_archived)" class="debt-panel p-5 text-sm leading-relaxed">
          <p class="font-semibold">为一个账户管理多笔计划</p>
          <p class="mt-1 text-xs text-gray-500">在我的钱包新建信用卡或贷款账户，选择“多分期”管理方式。已有旧模式账户与还款提醒继续保留，不自动转换。</p>
          <RouterLink to="/accounts" class="debt-text-button mt-2">前往钱包添加账户</RouterLink>
        </div>
        <div class="flex flex-wrap items-end justify-between gap-3">
          <div class="debt-scope"><span class="debt-caption">查看范围</span><OptionPicker v-model="scope" :options="scopeOptions" label="分期账户范围" :disabled="saving" /></div>
          <button class="debt-primary" :disabled="!canWrite" @click="openPlan($event)"><Plus :size="17" />新建计划</button>
        </div>
        <div v-if="legacyScope" class="debt-panel p-5 text-sm leading-relaxed">
          此账户保持旧模式，已有还款和历史余额没有转换。
          <RouterLink :to="{ path: '/reminders', query: { account_id: scope, view: 'reminders' } }" class="debt-text-button ml-1">查看还款提醒</RouterLink>
        </div>
        <div v-if="reviewNeeded" role="alert" class="debt-warning">此账户有 ¥{{ formatDebtMoney(currentAccount?.debt_unclassified ?? 0) }} 待核对差量，新的付款与分配已停用。可查看原凭证并按原影响撤销。</div>
        <div v-if="currentAccount?.is_archived" class="debt-warning">此账户已归档。请先在我的钱包恢复账户，再登记新的付款。</div>

        <section class="debt-panel overflow-hidden" aria-label="分期余额概览">
          <div class="debt-overview-metrics">
            <div><p class="debt-caption">待还本金</p><p class="debt-figure">¥{{ formatDebtMoney(totals.principal) }}</p></div>
            <div><p class="debt-caption">已入账未付利息</p><p class="debt-figure debt-muted-amount">¥{{ formatDebtMoney(totals.interest) }}</p></div>
            <div ><p class="debt-caption">累计分配已付</p><p class="debt-figure text-blue-500">¥{{ formatDebtMoney(totals.paid) }}</p></div>
          </div>
          <div v-if="currentAccount?.debt_tracking_mode === 'managed'" class="space-y-3 border-t border-gray-100/80 bg-blue-50/40 p-5 dark:border-white/10 dark:bg-blue-500/5">
            <div class="flex flex-wrap justify-between gap-3 text-sm">
              <span>账户欠款 <strong class="font-nums">¥{{ formatDebtMoney(currentAccount.current_balance) }}</strong></span>
              <span class="text-gray-500">未归计划 ¥{{ formatDebtMoney(currentAccount.unplanned_debt ?? 0) }} · 未分配付款 ¥{{ formatDebtMoney(currentAccount.unapplied_payment ?? 0) }}</span>
            </div>
            <div class="flex flex-wrap items-center justify-between gap-3"><details class="debt-balance-explainer"><summary>余额说明</summary><p>计划本金与已入账未付利息，加上未归计划欠款，再减去未分配付款，构成账户当前欠款。建立计划只划分已有欠款；预计利息不计入当前欠款。还清当前余额不代表银行已出具合同结清证明。</p></details>
              <button class="debt-primary" :disabled="!canWrite || !accountUsable" @click="openPayment(undefined, $event)"><ArrowUpRight :size="17" />登记付款</button>
            </div>
          </div>
          <p v-else class="border-t border-gray-100/80 p-4 text-xs text-gray-500 dark:border-white/10">选择一个多分期账户可登记跨计划付款；独立计划从各自卡片进入。</p>
        </section>

        <section aria-label="分期计划">
          <div class="mb-3 flex items-center justify-between"><h2 class="text-sm font-bold">分期计划</h2><span class="text-xs text-gray-500">{{ visiblePlans.length }} 笔</span></div>
          <div v-if="!visiblePlans.length" class="debt-panel px-5 py-10 text-center text-sm text-gray-500">暂无分期计划。可将未归计划欠款拆分为多笔计划，或建立独立计划。</div>
          <div class="grid gap-4">
            <article v-for="plan in visiblePlans" :key="plan.id" class="debt-panel debt-plan-card min-w-0 p-5" :aria-label="`分期 ${plan.name}`">
              <div class="flex items-start justify-between gap-3"><div class="min-w-0"><h3 class="break-words font-bold">{{ plan.name }}</h3><p class="mt-1 break-words text-xs text-gray-500">{{ scopeName(plan.account_id) }}</p></div>
                <span class="shrink-0 rounded-full bg-blue-50 px-2.5 py-1 text-[11px] text-blue-600 dark:bg-blue-500/10 dark:text-blue-300">{{ planStatus(plan) }}</span></div>
              <div class="mt-5 grid grid-cols-2 gap-3 text-sm"><div><p class="debt-caption">待还本金</p><p class="mt-1 font-nums font-bold">¥{{ formatDebtMoney(plan.principal_balance) }}</p></div><div><p class="debt-caption">已入账未付利息</p><p class="mt-1 font-nums font-bold">¥{{ formatDebtMoney(plan.interest_balance) }}</p></div></div>
              <p class="mt-3 text-xs leading-relaxed text-gray-500">已付本金 ¥{{ formatDebtMoney(plan.principal_paid) }} · 已付利息 ¥{{ formatDebtMoney(plan.interest_paid) }}</p>
              <p v-if="plan.estimated_interest !== null" class="mt-1 text-xs text-gray-500">预计未来利息 ¥{{ formatDebtMoney(plan.estimated_interest) }}（不计入欠款）</p>
              <div class="mt-4 flex flex-wrap gap-2 border-t border-gray-100 pt-3 dark:border-white/10">
                <template v-if="plan.status !== 'cancelled'">
                  <button v-if="!plan.account_id" class="debt-secondary" :disabled="!canWrite" @click="openPayment(plan, $event)">登记付款</button>
                  <button v-else class="debt-secondary" @click="scope = plan.account_id!">查看所属账户</button>
                  <button class="debt-secondary" :disabled="!canWrite" @click="openInterest(plan, $event)">利息入账</button>
                </template>
                <button v-if="capabilities?.operation_history" class="debt-secondary" @click="showPlanHistory(plan)">操作凭证</button>
              </div>
            </article>
          </div>
        </section>

        <section ref="historyRegion" aria-label="分期操作记录" class="scroll-mt-28">
          <div class="mb-3 flex flex-wrap items-center justify-between gap-2"><h2 class="text-sm font-bold">操作记录</h2><span class="text-xs text-gray-500">{{ capabilities?.operation_history ? '已加载' : '最近' }} {{ visibleOperations.length }} 条</span></div>
          <label v-if="capabilities?.operation_history" class="debt-label mb-3">凭证范围
            <select v-model="operationPlanId" aria-label="分期凭证范围" class="debt-input" :disabled="loading || saving">
              <option value="">当前查看范围的全部凭证</option>
              <option v-for="plan in visiblePlans" :key="plan.id" :value="plan.id">{{ plan.name }}</option>
            </select>
          </label>
          <p v-else class="mb-3 text-xs leading-relaxed text-gray-500">当前后端仅返回最近 100 条全局或账户凭证。更新后端后可按计划查询并加载更早记录。</p>
          <div class="debt-panel divide-y divide-gray-100/70 overflow-hidden dark:divide-white/10">
            <p v-if="!visibleOperations.length" class="p-8 text-center text-sm text-gray-500">暂无操作记录</p>
            <button v-for="op in visibleOperations" :key="op.id" class="flex min-h-20 w-full items-center gap-3 px-4 py-4 text-left hover:bg-blue-50/50 dark:hover:bg-blue-500/5"
              :aria-label="`查看凭证 ${operationName(op)} ${op.id}`" @click="openOperation(op.id, $event)">
              <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-blue-50 text-blue-500 dark:bg-blue-500/10"><RotateCcw v-if="op.kind === 'reversal'" :size="19" /><ReceiptText v-else :size="19" /></div>
              <div class="min-w-0 flex-1"><p class="text-sm font-semibold">{{ operationName(op) }} <span v-if="op.reversed_by" class="ml-1 text-xs font-normal text-gray-500">已撤销</span></p><p class="mt-1 break-words text-xs text-gray-500">{{ scopeName(op.account_id) }} · {{ dayjs(op.occurred_at).format('MM-DD HH:mm') }}</p></div>
              <span v-if="op.amount" class="shrink-0 font-nums text-sm font-bold">¥{{ formatDebtMoney(op.amount) }}</span>
            </button>
          </div>
          <FinanceListFooter v-if="capabilities?.operation_history && visibleOperations.length > 0"
            label="分期凭证列表加载" :count="visibleOperations.length" :has-more="hasMoreOperations"
            :loading="historyLoading || loading" :error="historyError" more-label="加载更早凭证"
            retry-label="重试加载更早凭证" @more="workspace.loadMoreOperations" />
        </section>
      </template>
    </div>

    <DebtModal v-if="props.active !== false && showOperation" title="分期操作凭证" :return-focus="dialogTrigger" :fallback-focus="workspaceHeading" @close="closeDetails">
      <p v-if="detailLoading" role="status" class="text-sm text-gray-500">正在加载凭证…</p>
      <div v-else-if="detailError" role="alert" class="debt-warning">{{ detailError }}</div>
      <template v-else-if="detail">
        <div class="space-y-4">
          <div><h3 class="text-lg font-bold">{{ operationName(detail.operation) }}<span v-if="detail.operation.reversed_by" class="ml-2 text-sm font-normal text-gray-500">已撤销</span></h3><p class="mt-1 break-all text-xs text-gray-500">凭证号 {{ detail.operation.id }}</p><p class="mt-1 text-xs text-gray-500">{{ dayjs(detail.operation.occurred_at).format('YYYY-MM-DD HH:mm') }}</p></div>
          <p v-if="detail.operation.amount" class="font-nums text-2xl font-bold">¥{{ formatDebtMoney(detail.operation.amount) }}</p>
          <div v-if="['payment', 'transfer_payment'].includes(detail.operation.kind)" class="rounded-2xl bg-blue-50 p-4 text-sm dark:bg-blue-500/10">
            <p>当前可分配 <strong class="font-nums">{{ typeof detail.unallocated_amount === 'number' ? `¥${formatDebtMoney(detail.unallocated_amount)}` : '后端未提供' }}</strong></p>
            <p class="mt-1 text-xs text-gray-500">后续分配只改变债务归属，不再次扣款。</p>
          </div>
          <div v-for="part in detail.allocations || []" :key="part.id" class="rounded-xl bg-gray-50 p-3 text-sm dark:bg-white/5"><p class="break-words font-semibold">{{ planName(part.plan_id) }}</p><p class="mt-1 text-xs leading-relaxed text-gray-500">本金变化 ¥{{ formatDebtMoney(part.principal_delta) }} · 未付利息变化 ¥{{ formatDebtMoney(part.interest_delta) }}</p></div>
          <div v-for="effect in detail.account_effects || []" :key="effect.id" class="text-sm"><p class="break-words font-medium">{{ scopeName(effect.account_id) }}</p><p class="mt-1 font-nums text-xs text-gray-500">¥{{ formatDebtMoney(effect.balance_before) }} → ¥{{ formatDebtMoney(effect.balance_after) }}</p></div>
          <div v-if="detail.active_allocations?.length" class="space-y-2">
            <h3 class="text-sm font-bold">有效后续分配</h3>
            <div v-for="child in detail.active_allocations" :key="child.id" class="flex items-center justify-between gap-2 rounded-xl border border-gray-100 p-3 dark:border-white/10"><span class="font-nums text-sm">¥{{ formatDebtMoney(child.amount) }}</span><button class="debt-secondary" :disabled="!canWrite" @click="openAllocation(detail!, child)">重新分配</button></div>
          </div>
          <div v-if="detail.operation.kind === 'allocation' && detail.operation.payment_id">
            <button class="debt-text-button" @click="openOperation(detail!.operation.payment_id!)">查看原付款与其他分配</button>
          </div>
          <RouterLink v-if="detail.operation.account_id" :to="`/account-logs/${detail.operation.account_id}`" class="debt-text-button" @click="closeDetails">查看账户流水</RouterLink>
        </div>
      </template>
      <template #footer>
        <button v-if="detail && !detail.operation.reversed_by && ['payment', 'transfer_payment'].includes(detail.operation.kind)" class="debt-primary"
          :disabled="!canWrite || !(detail.unallocated_amount! > 0)" @click="openAllocation(detail)">分配付款</button>
        <button v-if="detail && !detail.operation.reversed_by && !['account_open', 'reversal'].includes(detail.operation.kind)" class="debt-secondary text-red-500" :disabled="!canWrite" @click="openReverse(detail)">撤销此操作</button>
        <button class="debt-secondary" @click="closeDetails">关闭</button>
      </template>
    </DebtModal>

    <DebtModal v-if="props.active !== false && dialog" :title="dialogTitle" :busy="saving" :return-focus="dialogTrigger" :fallback-focus="workspaceHeading" @close="closeDialog">
      <form id="debt-action-form" class="space-y-4" @submit.prevent="submitDialog">
        <p v-if="actionError || writeError" role="alert" class="debt-warning">{{ actionError || writeError }}</p>
        <p v-if="pending" role="status" class="debt-warning">此次操作结果尚未确认。关闭表单后，请使用页面上的“确认上次操作结果”，原请求已锁定保留。</p>
        <fieldset :disabled="saving || !!pending" class="min-w-0 space-y-4 disabled:opacity-70">
          <template v-if="dialog === 'plan'">
            <label class="debt-label">计划名称<input v-model="planForm.name" aria-label="计划名称" maxlength="100" class="debt-input" placeholder="例如：家电分期"></label>
            <label class="debt-label">所属账户<select v-model="planForm.target" aria-label="计划所属账户" class="debt-input"><option value="standalone">独立计划（不关联账户）</option><option v-for="account in managedAccounts.filter(item => !item.is_archived)" :key="account.id" :value="account.id">{{ account.name }}</option></select></label>
            <p class="text-xs leading-relaxed text-gray-500">关联计划只划分已有欠款，不增加账户负债；历史已还金额不会由这两个本金字段反推。</p>
            <div class="grid grid-cols-2 gap-3">
              <label class="debt-label">原始本金<input v-model="planForm.original" aria-label="原始本金" inputmode="decimal" class="debt-input" placeholder="0.00"></label>
              <label class="debt-label">开始追踪时本金<input v-model="planForm.principal" aria-label="开始追踪时本金" inputmode="decimal" class="debt-input" placeholder="0.00"></label>
              <label class="debt-label">已入账未付利息<input v-model="planForm.booked" aria-label="计划已入账利息" inputmode="decimal" class="debt-input" placeholder="0.00"></label>
              <label class="debt-label">预计未来利息（可选）<input v-model="planForm.estimated" aria-label="预计未来利息" inputmode="decimal" class="debt-input" placeholder="不计入欠款"></label>
            </div>
          </template>
          <template v-if="dialog === 'payment'">
            <p class="text-sm text-gray-500">付款目标：{{ targetedPlan?.name || currentAccount?.name }}</p>
            <label class="debt-label">本次付款金额<input v-model="paymentForm.amount" aria-label="本次付款金额" inputmode="decimal" class="debt-input" placeholder="0.00"></label>
            <div class="grid gap-3 sm:grid-cols-2">
              <label class="debt-label">付款来源<select v-model="paymentForm.source_kind" aria-label="付款来源" class="debt-input"><option value="account">账本中的真实账户</option><option value="external">外部来源（不扣账本资金）</option></select></label>
              <label v-if="paymentForm.source_kind === 'account'" class="debt-label">付款账户<select v-model="paymentForm.source_account_id" aria-label="付款账户" class="debt-input"><option value="" disabled>请选择付款账户</option><option v-for="account in sourceAccounts" :key="account.id" :value="account.id">{{ account.name }}</option></select></label>
            </div>
            <p class="text-xs leading-relaxed text-gray-500">已入账利息付款不重复记费用；当次利息是本次新发生的费用，外部来源暂不支持。</p>
            <DebtAllocationFields v-model="parts" :plans="activeFormPlans" cash-interest />
            <div v-if="!targetedPlan" class="grid grid-cols-2 gap-3">
              <label class="debt-label">偿还未归计划欠款<input v-model="paymentForm.unplanned_amount" aria-label="偿还未归计划欠款" inputmode="decimal" class="debt-input" placeholder="0.00"></label>
              <label class="debt-label">暂不分配<input v-model="paymentForm.unapplied_amount" aria-label="暂不分配金额" inputmode="decimal" class="debt-input" placeholder="0.00"></label>
            </div>
            <label class="debt-label">付款时间<input v-model="paymentForm.occurred_at" aria-label="付款时间" type="datetime-local" class="debt-input"></label>

          </template>
          <template v-if="dialog === 'allocation'">
            <p v-if="allocationLoading" role="status" class="text-sm text-gray-500">正在核对原付款与剩余额度…</p>
            <template v-else>
              <p class="rounded-xl bg-blue-50 p-3 text-sm dark:bg-blue-500/10">本次可分配额度 <strong class="font-nums">{{ availableCents === null ? '暂不可用' : `¥${formatDebtMoney(debtAmount(availableCents))}` }}</strong></p>
              <p class="text-xs leading-relaxed text-gray-500">{{ replacing ? '保存时原子撤销选中的旧分配，再应用下面的新分配。' : '本次只分配该付款的剩余额度。' }}付款账户不会再次扣款，不能改成当次新发生的利息。</p>
              <DebtAllocationFields v-model="parts" :plans="activeFormPlans" />
              <label class="debt-label">偿还未归计划欠款<input v-model="allocationUnplanned" aria-label="分配到未归计划欠款" inputmode="decimal" class="debt-input" placeholder="0.00"></label>
              <p class="text-sm text-gray-500">分配合计 ¥{{ partSummary }}</p>
            </template>
          </template>
          <template v-if="dialog === 'interest'">
            <p class="text-sm text-gray-500">{{ targetedPlan?.name }}：登记实际已经入账的利息。预计未来利息不在这里登记。</p>
            <label class="debt-label">本次入账利息<input v-model="interestForm.amount" aria-label="本次入账利息" inputmode="decimal" class="debt-input" placeholder="0.00"></label>
            <label class="debt-label">入账时间<input v-model="interestForm.occurred_at" aria-label="入账时间" type="datetime-local" class="debt-input"></label>
          </template>
          <template v-if="dialog === 'reverse' && actionOperation">
            <p class="text-sm leading-relaxed">将撤销“{{ operationName(actionOperation.operation) }}”<span v-if="actionOperation.operation.amount"> ¥{{ formatDebtMoney(actionOperation.operation.amount) }}</span>。</p>
            <div class="debt-warning text-sm leading-relaxed">付款的有效后续分配会一起撤销。系统按原实际影响反向处理，并保留凭证；之后的其他交易不会被覆盖。建立计划仍有有效后续操作时，撤销会被拒绝。</div>
            <p class="break-all text-xs text-gray-500">凭证号 {{ actionOperation.operation.id }}</p>
          </template>
        </fieldset>
      </form>
      <template #footer>
        <div v-if="dialog === 'payment'" class="debt-allocation-summary" aria-live="polite" aria-atomic="true"><span>分配合计 <strong class="font-nums">{{ partSummary === '金额待核对' ? partSummary : `¥${partSummary}` }}</strong></span><span>差额 <strong class="font-nums" :class="{ 'text-red-500': allocationDifference !== 0 }">{{ allocationDifference === null ? '待核对' : `${allocationDifference < 0 ? '−' : ''}¥${formatDebtMoney(Math.abs(allocationDifference) / 100)}` }}</strong></span></div>
        <button class="debt-secondary" :disabled="saving" @click="closeDialog">{{ pending ? '关闭并保留待确认请求' : '取消' }}</button>
        <button class="debt-primary" :class="{ 'debt-danger': dialog === 'reverse' }" type="submit" form="debt-action-form"
          :disabled="!canWrite || !paymentReady || allocationLoading || (dialog === 'allocation' && (!allocationReady || availableCents === null))">
          {{ saving ? '正在确认…' : dialog === 'reverse' ? '确认撤销' : dialog === 'plan' ? '保存计划' : dialog === 'payment' ? '确认付款' : dialog === 'interest' ? '确认入账' : '确认分配' }}
        </button>
      </template>
    </DebtModal>
  </div>
</template>

<style scoped>
.debt-panel { border: 1px solid rgb(255 255 255 / .55); border-radius: 22px; background: var(--fp-surface, rgb(255 255 255 / .84)); box-shadow: 0 4px 20px rgb(15 23 42 / .035);  }
.debt-caption { font-size: 12px; line-height: 1.6; color: var(--fp-secondary, var(--color-gray-500)); }
.debt-figure { margin-top: 6px; font-size: clamp(17px, 2.4vw, 24px); line-height: 1.3; font-weight: 600; font-variant-numeric: tabular-nums; overflow-wrap: anywhere; }
.debt-label { display: flex; min-width: 0; flex-direction: column; gap: 7px; font-size: 12px; font-weight: 500; color: var(--color-gray-600); }
.debt-input { height: 46px; width: 100%; min-width: 0; border-radius: 12px; border: 1px solid transparent; background: var(--color-gray-100); padding: 0 12px; color: var(--color-gray-900); font-size: 14px; outline: none; }
.debt-input:focus-visible { border-color: var(--color-primary); box-shadow: 0 0 0 3px rgb(0 122 255 / .12); }
.debt-primary, .debt-secondary, .debt-icon { display: inline-flex; min-height: 44px; flex-shrink: 0; align-items: center; justify-content: center; gap: 6px; border-radius: 12px; padding: 0 16px; font-size: 13px; font-weight: 600; transition: background .15s; }
.debt-primary { background: var(--color-primary); color: white; }
.debt-primary.debt-danger { background: var(--color-red-500); }
.debt-secondary, .debt-icon { background: rgb(142 142 147 / .09); }
.debt-icon { width: 44px; padding: 0; color: var(--color-gray-500); }
.debt-text-button { display: inline-flex; min-height: 32px; align-items: center; font-weight: 600; color: var(--color-primary); }
.debt-warning { border: 1px solid rgb(245 158 11 / .25); border-radius: 14px; background: rgb(245 158 11 / .08); padding: 14px; font-size: 13px; line-height: 1.6; color: #92400e; overflow-wrap: anywhere; }
button:disabled { opacity: .45; cursor: default; }
:global(.dark .debt-panel) { border-color: rgb(255 255 255 / .035); background: var(--fp-surface, rgb(28 28 30 / .92)); }
:global(.dark .debt-input) { background: rgb(255 255 255 / .05); color: #f5f5f5; }
:global(.dark .debt-label) { color: #b3b3ba; }
:global(.dark .debt-warning) { color: #fcd34d; }
@media (prefers-reduced-motion: reduce) { .debt-primary, .debt-secondary, .debt-icon { transition: none; } }

.debt-plan-card h3 { font-size: 15px; font-weight: 600; }
.debt-plan-card .grid p.font-nums { font-size: 20px; font-weight: 600; }
.debt-scope { flex: 1; min-width: 0; }
.debt-scope > span { display: block; margin-bottom: 5px; }
.debt-overview-metrics { display: grid; grid-template-columns: repeat(3,minmax(0,1fr)); gap: 20px; padding: 22px; }
.debt-muted-amount { color: var(--fp-secondary); font-weight: 500; }
.debt-balance-explainer { font-size: 12px; color: var(--fp-secondary); max-width: 100%; }
.debt-balance-explainer summary { min-height: 36px; display: flex; align-items: center; cursor: pointer; list-style: none; }
.debt-balance-explainer summary::-webkit-details-marker { display: none; }
.debt-balance-explainer p { max-width: 520px; padding: 12px 0; line-height: 1.8; }
.debt-allocation-summary { flex: 1 0 100%; display: flex; justify-content: space-between; flex-wrap: wrap; gap: 8px 16px; font-size: 12px; color: var(--fp-secondary); }
.debt-allocation-summary strong { margin-left: 4px; color: var(--fp-ink); font-weight: 550; }
.debt-allocation-summary strong.text-red-500 { color: var(--fp-red); }
@media (max-width:767px) { .debt-overview-metrics { gap: 8px; padding: 18px 16px; } .debt-overview-metrics .debt-caption { font-size: 11px; } .debt-overview-metrics .debt-figure { font-size: 18px; } }
@media (max-width:360px) { .debt-overview-metrics .debt-caption { font-size: 10px; } .debt-overview-metrics .debt-figure { font-size: 16px; } }
</style>
