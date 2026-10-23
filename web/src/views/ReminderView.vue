<script setup lang="ts">
import AppDialog from '@/components/ui/AppDialog.vue'
import { ref, onMounted, onBeforeUnmount, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronLeft, Plus, Trash2, Edit2, Bell, BellOff, Calendar, CreditCard, Home, Car, Wallet, Target, Banknote, Paperclip } from '@lucide/vue'
import FileUpload from '@/components/FileUpload.vue'
import { reminderApi, type Reminder, type CreateReminderParams, type DebtSummary, type LoanType } from '@/api/reminder'
import { accountApi, type Account, isDebtAccount } from '@/api/account'
import { toast } from '@/composables/useToast'
import { deleteRemovedAttachments } from '@/utils/attachmentCleanup'
import { notifyLedgerMutation, useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { createRequestGeneration } from '@/utils/requestGeneration'
import { createFormSubmission } from '@/utils/formSubmission'
import { clearPendingRepayment, createPendingRepayment, isDefinitiveRepaymentRejection, pendingRepaymentMessage, readPendingRepayment, startPendingRepaymentAttempt, type PendingRepayment } from '@/utils/pendingRepayment'

const props = defineProps<{ embedded?: boolean; active?: boolean }>()
const router = useRouter()
const dialogTrigger = ref<HTMLElement | null>(null)
const dialogFallback = ref<HTMLElement | null>(null)
function captureDialogTrigger(event?: Event) {
  if (typeof document === 'undefined') return
  dialogTrigger.value = event?.currentTarget instanceof HTMLElement ? event.currentTarget : document.activeElement as HTMLElement | null
}


const reminders = ref<Reminder[]>([])
const accounts = ref<Account[]>([])
const debtSummary = ref<DebtSummary | null>(null)
const loading = ref(false)
const ledgerMutationRevision = useLedgerMutationRevision()
const dataRequests = createRequestGeneration()

const loanTypes: { value: LoanType; label: string; icon: any; color: string }[] = [
  { value: 'credit_card', label: '信用卡', icon: CreditCard, color: '#3B82F6' },
  { value: 'mortgage', label: '房贷', icon: Home, color: '#10B981' },
  { value: 'car_loan', label: '车贷', icon: Car, color: '#F59E0B' },
  { value: 'consumer_loan', label: '消费贷', icon: Wallet, color: '#8B5CF6' },
  { value: 'other', label: '其他', icon: Banknote, color: '#6B7280' }
]

const defaultForm = (): CreateReminderParams => ({
  name: '',
  account_id: undefined,
  loan_type: 'credit_card',
  payment_day: 1,
  billing_day: undefined,
  advance_days: 3,
  amount: undefined,
  principal: undefined,
  current_balance: undefined,
  interest_rate: undefined,
  total_interest: undefined,
  start_date: undefined,
  target_date: undefined,
  color: '#3B82F6',
  remark: '',
  evidence: ''
})

const showDialog = ref(false)
const editingReminder = ref<Reminder | null>(null)
const originalEvidence = ref('')
const form = ref<CreateReminderParams>(defaultForm())
const formSubmission = createFormSubmission()
const saving = formSubmission.saving
const attachmentsUploading = ref(false)

const showPaymentDialog = ref(false)
const payingReminder = ref<Reminder | null>(null)
const paymentAmount = ref<number>(0)
const paymentPrincipal = ref<number>(0)
const paymentInterest = ref<number>(0)
const paymentAccountId = ref<string>('')
const paymentSubmission = createFormSubmission()
const paying = paymentSubmission.saving
const paymentError = ref('')
type PaymentPayload = { amount: number; accountId: string; principal: number; interest: number }
const pendingPayment = ref<PendingRepayment<PaymentPayload> | null>(null)
const pendingRevision = ref(0)
const pendingPayments = computed(() => {
  void pendingRevision.value
  return reminders.value.filter(reminder => {
    try { return !!readPendingRepayment('reminder', reminder.id) } catch { return false }
  })
})

const showDeleteModal = ref(false)
const deletingId = ref<string | null>(null)
const deleting = ref(false)

const activeLoans = computed(() => reminders.value.filter(r => r.is_enabled && !r.paid_off_at))
const paidOffLoans = computed(() => reminders.value.filter(r => r.paid_off_at))
const inactiveLoans = computed(() => reminders.value.filter(r => !r.is_enabled && !r.paid_off_at))
const debtAccounts = computed(() => accounts.value.filter(a => isDebtAccount(a.type) &&
  (a.debt_tracking_mode !== 'managed' || a.id === editingReminder.value?.account_id)))
const sourceAccounts = computed(() => accounts.value.filter(a => !isDebtAccount(a.type)))

watch(() => props.active, active => {
  if (active !== false) return
  if (!saving.value) closeDialog()
  if (!paying.value) closePaymentDialog()
  if (!deleting.value) showDeleteModal.value = false
})

onMounted(() => {
  loadData()
})

watch(ledgerMutationRevision, () => void loadData())
onBeforeUnmount(() => {
  dataRequests.begin()
  formSubmission.reset()
  paymentSubmission.reset()
})

async function loadData() {
  const requestGeneration = dataRequests.begin()
  loading.value = true
  try {
    const [reminderList, accountData, summary] = await Promise.all([
      reminderApi.getList(),
      accountApi.getList(),
      reminderApi.getDebtSummary()
    ])
    if (!dataRequests.isLatest(requestGeneration)) return
    reminders.value = reminderList
    accounts.value = accountData.list
    debtSummary.value = summary
  } catch (e: any) {
    if (dataRequests.isLatest(requestGeneration)) {
      toast.error('加载数据失败')
    }
  } finally {
    if (dataRequests.isLatest(requestGeneration)) {
      loading.value = false
    }
  }
}

function goBack() {
  router.back()
}

function getLoanTypeInfo(type: LoanType) {
  return loanTypes.find(t => t.value === type) || loanTypes[4]
}

function getProgress(reminder: Reminder): number {
  if (!reminder.principal || reminder.principal === 0) return 0
  // Progress = (principal - current_balance) / principal * 100
  const remaining = reminder.current_balance ?? 0
  const paid = reminder.principal - remaining
  return Math.min(100, Math.max(0, (paid / reminder.principal) * 100))
}

function getDaysUntilPayment(day: number): number {
  const today = new Date()
  const currentDay = today.getDate()
  const daysInMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate()
  const paymentDay = Math.min(day, daysInMonth)
  if (paymentDay >= currentDay) return paymentDay - currentDay
  const daysInNextMonth = new Date(today.getFullYear(), today.getMonth() + 2, 0).getDate()
  return daysInMonth - currentDay + Math.min(day, daysInNextMonth)
}

function openCreate(event?: Event) {
  captureDialogTrigger(event)
  attachmentsUploading.value = false
  formSubmission.reset()
  editingReminder.value = null
  originalEvidence.value = ''
  form.value = defaultForm()
  showDialog.value = true
}

function openEdit(reminder: Reminder, event?: Event) {
  captureDialogTrigger(event)
  attachmentsUploading.value = false
  formSubmission.reset()
  editingReminder.value = reminder
  originalEvidence.value = reminder.evidence || ''
  form.value = {
    name: reminder.name,
    account_id: reminder.account_id,
    loan_type: reminder.loan_type,
    payment_day: reminder.payment_day,
    billing_day: reminder.billing_day,
    advance_days: reminder.advance_days,
    amount: reminder.amount,
    principal: reminder.principal,
    current_balance: reminder.current_balance,
    interest_rate: reminder.interest_rate,
    start_date: reminder.start_date?.split('T')[0],
    target_date: reminder.target_date?.split('T')[0],
    color: reminder.color || '#3B82F6',
    remark: reminder.remark,
    evidence: reminder.evidence || ''
  }
  showDialog.value = true
}

function closeDialog() {
  attachmentsUploading.value = false
  formSubmission.reset()
  showDialog.value = false
  editingReminder.value = null
  originalEvidence.value = ''
}

function openPayment(reminder: Reminder, event?: Event) {
  captureDialogTrigger(event)
  paymentSubmission.reset()
  paymentError.value = ''
  payingReminder.value = reminder
  paymentAmount.value = reminder.amount || 0
  paymentPrincipal.value = 0
  paymentInterest.value = 0
  paymentAccountId.value = ''
  pendingPayment.value = null
  try {
    const pending = readPendingRepayment<PaymentPayload>('reminder', reminder.id)
    if (pending) restorePendingPayment(pending)
  } catch (error: any) {
    paymentError.value = error.message
  }
  showPaymentDialog.value = true
}

function restorePendingPayment(pending: PendingRepayment<PaymentPayload>) {
  pendingPayment.value = pending
  paymentAmount.value = pending.payload.amount
  paymentPrincipal.value = pending.payload.principal
  paymentInterest.value = pending.payload.interest
  paymentAccountId.value = pending.payload.accountId
  paymentError.value = pendingRepaymentMessage
}

function closePaymentDialog() {
  paymentSubmission.reset()
  paymentError.value = ''
  showPaymentDialog.value = false
  payingReminder.value = null
  pendingPayment.value = null
}

async function submitPayment() {
  if (paying.value || !payingReminder.value) return
  const id = payingReminder.value.id
  let pending: PendingRepayment<PaymentPayload> | null
  try {
    pending = readPendingRepayment<PaymentPayload>('reminder', id) || pendingPayment.value
  } catch (error: any) {
    paymentError.value = error.message
    toast.error(paymentError.value)
    return
  }
  const confirmingPrevious = !!pending
  if (pending) {
    // A committed payment may already have reduced the balance to zero.
    restorePendingPayment(pending)
  } else {
    if (!paymentAccountId.value) {
      toast.warning('请选择还款账户')
      return
    }
    const amount = Math.round(paymentAmount.value * 100)
    let principal = Math.round(paymentPrincipal.value * 100)
    let interest = Math.round(paymentInterest.value * 100)
    if (![amount, principal, interest].every(Number.isFinite) || amount <= 0 || principal < 0 || interest < 0) {
      toast.warning('还款金额必须大于 0，本金和利息不能为负数')
      return
    }
    // Match the backend: an omitted split is all principal; one part infers the other.
    if (principal === 0 && interest === 0) principal = amount
    else if (principal === 0) principal = amount - interest
    else if (interest === 0) interest = amount - principal
    if (principal < 0 || interest < 0 || principal + interest !== amount) {
      toast.warning('本金+利息必须等于还款金额')
      return
    }
    const remaining = payingReminder.value.current_balance
    if (remaining != null && principal > Math.round(remaining * 100)) {
      toast.warning(`还款本金不能超过待还本金 ¥${remaining.toFixed(2)}`)
      return
    }
    try {
      pending = createPendingRepayment('reminder', id, { amount: amount / 100, accountId: paymentAccountId.value, principal: principal / 100, interest: interest / 100 })
      pendingPayment.value = pending
      pendingRevision.value += 1
    } catch (error: any) {
      paymentError.value = error.message
      toast.error(paymentError.value)
      return
    }
  }
  try {
    pending = startPendingRepaymentAttempt('reminder', id, pending)
    pendingPayment.value = pending
  } catch (error: any) {
    paymentError.value = error.message
    toast.error(paymentError.value)
    return
  }
  const payload = pending.payload
  const key = pending.key
  const submission = paymentSubmission.begin()
  if (!submission) return
  let confirmed = false
  try {
    await reminderApi.recordPayment(
      id, payload.amount, payload.accountId, payload.principal, payload.interest, key
    )
    confirmed = true
    notifyLedgerMutation()
    clearPendingRepayment('reminder', id, key)
    pendingRevision.value += 1
    if (!submission.isCurrent()) return
    toast.success('还款记录成功，已同步到明细')
    closePaymentDialog()
    paymentAmount.value = 0
    paymentPrincipal.value = 0
    paymentInterest.value = 0
    paymentAccountId.value = ''
  } catch (e: any) {
    let rejected = !confirmingPrevious && isDefinitiveRepaymentRejection(e)
    if (rejected) {
      try {
        rejected = clearPendingRepayment('reminder', id, key, pending.attempt)
        pendingRevision.value += 1
      } catch { rejected = false }
    }
    if (submission.isCurrent()) {
      if (rejected) pendingPayment.value = null
      else restorePendingPayment(pending)
      paymentError.value = rejected || confirmed ? e.message || '记录失败' : pendingRepaymentMessage
      toast.error(paymentError.value)
    } else if (rejected && !paying.value && pendingPayment.value?.key === key) {
      // A reopened confirmation can become editable when its only request was rejected.
      pendingPayment.value = null
      paymentError.value = e.message || '记录失败'
    }
  } finally {
    submission.finish()
  }
}

async function submitForm() {
  if (saving.value || attachmentsUploading.value) return
  if (!form.value.name) {
    toast.warning('请输入名称')
    return
  }

  const submission = formSubmission.begin()
  if (!submission) return
  const editingId = editingReminder.value?.id
  const payload = { ...form.value }
  const previousEvidence = originalEvidence.value
  try {
    if (editingId) {
      await reminderApi.update(editingId, payload)
      notifyLedgerMutation()
      if (!submission.isCurrent()) return
      const failedCleanupPaths = await deleteRemovedAttachments(previousEvidence, payload.evidence)
      if (!submission.isCurrent()) return
      toast.success(
        failedCleanupPaths.length > 0
          ? `更新成功，但有 ${failedCleanupPaths.length} 个旧附件清理失败`
          : '更新成功'
      )
    } else {
      await reminderApi.create(payload)
      notifyLedgerMutation()
      if (!submission.isCurrent()) return
      toast.success('创建成功')
    }
    closeDialog()
  } catch (e: any) {
    if (submission.isCurrent()) toast.error(e.message || '保存失败')
  } finally {
    submission.finish()
  }
}

async function toggleReminder(id: string) {
  try {
    await reminderApi.toggle(id)
    loadData()
  } catch (e: any) {
    toast.error('操作失败')
  }
}

function confirmDelete(id: string, event?: Event) {
  captureDialogTrigger(event)
  deletingId.value = id
  showDeleteModal.value = true
}

async function handleDelete() {
  if (!deletingId.value || deleting.value) return
  deleting.value = true
  try {
    await reminderApi.delete(deletingId.value)
    showDeleteModal.value = false
    deletingId.value = null
    toast.success('删除成功')
    loadData()
  } catch (e: any) {
    toast.error(e.message || '删除失败')
  } finally {
    deleting.value = false
  }
}

function formatMoney(val: number | null | undefined) {
  if (val == null) return '¥0.00'
  return '¥' + val.toLocaleString('zh-CN', { minimumFractionDigits: 2 })
}

function selectLoanType(type: LoanType) {
  form.value.loan_type = type
  form.value.color = loanTypes.find(t => t.value === type)?.color || '#3B82F6'
}

function selectAccount(accountId: string | undefined) {
  form.value.account_id = accountId
  if (!accountId) return
  
  const account = accounts.value.find(a => a.id === accountId)
  if (!account) return
  
  // Auto-populate from account data
  if (!form.value.name) form.value.name = account.name
  if (account.payment_day) form.value.payment_day = account.payment_day
  if (account.billing_day) form.value.billing_day = account.billing_day
  if (account.credit_limit) form.value.principal = account.credit_limit
  if (account.current_balance) form.value.current_balance = Math.abs(account.current_balance)
  if (account.interest_rate) form.value.interest_rate = account.interest_rate
  if (account.color) form.value.color = account.color
}
</script>

<template>
  <div :class="props.embedded ? '' : 'min-h-full bg-[#F2F2F7] dark:bg-black pb-8'">
    <!-- Header -->
    <div v-if="!props.embedded" class="bg-white/70 dark:bg-[#1C1C1E]/70 pt-4 pb-4 px-4 md:px-8 sticky top-0 z-30 backdrop-blur-xl border-b border-gray-200/50 dark:border-white/10">
      <div class="max-w-3xl mx-auto flex items-center justify-between">
        <div class="flex items-center gap-4">
          <button @click="goBack" class="p-2 -ml-2 text-gray-500 hover:bg-gray-100 dark:hover:bg-white/10 rounded-xl transition">
            <ChevronLeft :size="20" />
          </button>
          <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-orange-500 to-orange-600 flex items-center justify-center shadow-lg shadow-orange-500/20">
            <Calendar class="text-white" :size="28" />
          </div>
          <div>
            <h1 ref="dialogFallback" tabindex="-1" class="text-xl font-bold text-gray-900 dark:text-white">负债管理</h1>
            <div class="text-sm text-gray-500 dark:text-gray-400 mt-0.5">{{ reminders.length }} 笔负债</div>
          </div>
        </div>
        <button
          class="p-2.5 bg-gray-100/50 dark:bg-white/5 text-gray-400 hover:text-orange-500 hover:bg-orange-50 dark:hover:bg-orange-900/20 rounded-full transition"
          @click="openCreate"
        >
          <Plus :size="20" />
        </button>
      </div>
    </div>

    <div class="mx-auto space-y-6" :class="props.embedded ? '' : 'max-w-3xl px-4 md:px-8 py-6'">
      <div v-if="props.embedded" class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 ref="dialogFallback" tabindex="-1" class="text-base font-bold text-gray-900 dark:text-white">还款提醒</h2>
          <p class="mt-1 text-xs text-gray-500">{{ reminders.length }} 笔提醒 · 按原有规则继续管理</p>
        </div>
        <button class="flex min-h-11 items-center gap-1.5 rounded-xl bg-primary px-4 text-sm font-semibold text-white" @click="openCreate"><Plus :size="17" />添加提醒</button>
      </div>
      <p v-if="props.embedded" class="rounded-2xl border border-blue-100/70 bg-blue-50/50 p-4 text-xs leading-relaxed text-gray-600 dark:border-blue-500/15 dark:bg-blue-500/5 dark:text-gray-400">
        原有提醒和还款记录继续保留。一个账户下的多笔提醒，请在“账户与分期”中管理；此处的提醒进度不与分期余额相加。
      </p>
      <div v-for="reminder in pendingPayments" :key="`pending-${reminder.id}`" role="alert" class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
        <p>{{ reminder.name }} 有一笔未确认还款，请先确认上次结果。</p>
        <button class="mt-2 rounded-lg border border-current px-3 py-1.5 font-medium" @click="openPayment(reminder, $event)">确认上次还款结果</button>
      </div>
      <!-- Debt Summary Card -->
      <div v-if="debtSummary && (debtSummary.total_principal > 0 || activeLoans.length > 0)" class="bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl rounded-2xl p-5 border border-gray-200/50 dark:border-gray-700/50 shadow-sm">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2 text-gray-500 dark:text-gray-400 text-sm">
            <Target :size="16" />
            <span>上岸进度</span>
          </div>
          <div class="text-2xl font-bold text-gray-900 dark:text-white">{{ debtSummary.progress.toFixed(1) }}%</div>
        </div>
        <div class="h-1.5 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden mb-4">
          <div class="h-full bg-primary rounded-full transition-all duration-500" :style="{ width: debtSummary.progress + '%' }"></div>
        </div>
        <div class="grid grid-cols-3 gap-3">
          <div class="bg-gray-50 dark:bg-gray-700/50 rounded-xl p-3">
            <div class="text-xs text-gray-400 mb-1">待还</div>
            <div class="text-base font-bold text-gray-900 dark:text-white font-nums">{{ formatMoney(debtSummary.total_debt) }}</div>
          </div>
          <div class="bg-gray-50 dark:bg-gray-700/50 rounded-xl p-3">
            <div class="text-xs text-gray-400 mb-1">已还</div>
            <div class="text-base font-bold text-teal-600 dark:text-teal-400 font-nums">{{ formatMoney(debtSummary.total_paid) }}</div>
          </div>
          <div class="bg-gray-50 dark:bg-gray-700/50 rounded-xl p-3">
            <div class="text-xs text-gray-400 mb-1">共需还</div>
            <div class="text-base font-bold text-blue-600 dark:text-blue-400 font-nums">{{ formatMoney(debtSummary.total_principal) }}</div>
          </div>
        </div>
        <div v-if="paidOffLoans.length > 0" class="mt-4 pt-4 border-t border-gray-100 dark:border-gray-700 flex items-center gap-2 text-teal-600 dark:text-teal-400 text-sm">
          <span>🎉</span>
          <span>已还清 {{ paidOffLoans.length }} 笔提醒</span>
        </div>
      </div>

      <!-- Active Loans -->
      <div v-if="activeLoans.length > 0">
        <h2 class="text-sm font-bold text-gray-400 uppercase tracking-wider mb-3">进行中 ({{ activeLoans.length }})</h2>
        <div class="space-y-3">
          <div 
            v-for="loan in activeLoans" 
            :key="loan.id"
            class="bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl rounded-2xl p-4 border border-gray-200/50 dark:border-gray-700/50 shadow-sm hover:shadow-md transition-all duration-200 group"
          >
            <div class="flex justify-between items-start mb-3">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl flex items-center justify-center" :style="{ backgroundColor: (loan.color || '#3B82F6') + '15' }">
                  <component :is="getLoanTypeInfo(loan.loan_type).icon" :size="20" :style="{ color: loan.color || '#3B82F6' }" />
                </div>
                <div>
                  <div class="font-semibold text-gray-900 dark:text-white">{{ loan.name || getLoanTypeInfo(loan.loan_type).label }}</div>
                  <div class="text-xs text-gray-400 flex items-center gap-1.5">
                    <Calendar :size="12" />
                    <span>每月 {{ loan.payment_day }} 日</span>
                    <span v-if="getDaysUntilPayment(loan.payment_day) <= 7" class="text-amber-500 font-medium">
                      ({{ getDaysUntilPayment(loan.payment_day) === 0 ? '今天' : getDaysUntilPayment(loan.payment_day) + '天后' }})
                    </span>
                  </div>
                </div>
              </div>
              <div class="flex flex-wrap justify-end gap-0.5">
                <button :aria-label="`编辑提醒 ${loan.name}`" class="min-h-11 min-w-11 flex items-center justify-center text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition" @click="openEdit(loan, $event)">
                  <Edit2 :size="14" />
                </button>
                <button :aria-label="`暂停提醒 ${loan.name}`" class="min-h-11 min-w-11 flex items-center justify-center text-gray-400 hover:text-amber-500 hover:bg-amber-50 dark:hover:bg-amber-900/30 rounded-lg transition" @click="toggleReminder(loan.id)" title="禁用提醒">
                  <BellOff :size="14" />
                </button>
                <button :aria-label="`删除提醒 ${loan.name}`" class="min-h-11 min-w-11 flex items-center justify-center text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition" @click="confirmDelete(loan.id, $event)">
                  <Trash2 :size="14" />
                </button>
              </div>
            </div>

            <!-- Progress Bar -->
            <div v-if="loan.principal" class="mb-3">
              <div class="flex justify-between text-xs mb-1">
                <span class="text-gray-400">还款进度</span>
                <span class="font-medium text-gray-900 dark:text-white">{{ getProgress(loan).toFixed(0) }}%</span>
              </div>
              <div class="h-1 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
                <div class="h-full rounded-full transition-all duration-500" :style="{ width: getProgress(loan) + '%', backgroundColor: loan.color || '#3B82F6' }"></div>
              </div>
            </div>

            <!-- Loan Details -->
            <div class="flex flex-wrap gap-2 text-xs">
              <div v-if="loan.principal" class="bg-gray-50 dark:bg-gray-700/50 text-gray-600 dark:text-gray-300 px-2 py-1 rounded-md">
                <span class="text-gray-400">本金</span>
                <span class="font-medium ml-1">{{ formatMoney(loan.principal) }}</span>
              </div>
              <div v-if="loan.current_balance != null" class="bg-gray-50 dark:bg-gray-700/50 text-gray-600 dark:text-gray-300 px-2 py-1 rounded-md">
                <span class="text-gray-400">待还</span>
                <span class="font-medium ml-1">{{ formatMoney(loan.current_balance) }}</span>
              </div>
              <div v-if="loan.amount" class="bg-gray-50 dark:bg-gray-700/50 text-gray-600 dark:text-gray-300 px-2 py-1 rounded-md">
                <span class="text-gray-400">月供</span>
                <span class="font-medium ml-1">{{ formatMoney(loan.amount) }}</span>
              </div>
            </div>

            <!-- Record Payment Button -->
            <button 
              v-if="loan.principal"
              class="mt-3 min-h-11 w-full py-2 border border-dashed border-gray-200 dark:border-gray-600 rounded-lg text-gray-400 hover:border-primary hover:text-primary transition text-xs font-medium"
              @click="openPayment(loan, $event)"
            >
              + 记录还款
            </button>
          </div>
        </div>
      </div>

      <!-- Paid Off Loans -->
      <div v-if="paidOffLoans.length > 0">
        <h2 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-3">已还清 🎉</h2>
        <div class="space-y-2">
          <div 
            v-for="loan in paidOffLoans" 
            :key="loan.id"
            class="bg-teal-50/50 dark:bg-teal-900/10 backdrop-blur-xl rounded-xl p-3 border border-teal-100/50 dark:border-teal-800/30 hover:shadow-sm transition-all group"
          >
            <div class="flex justify-between items-center">
              <div class="flex items-center gap-3">
                <div class="w-9 h-9 rounded-lg bg-teal-100 dark:bg-teal-800/50 flex items-center justify-center text-teal-600 dark:text-teal-400">
                  <component :is="getLoanTypeInfo(loan.loan_type).icon" :size="18" />
                </div>
                <div>
                  <div class="font-medium text-teal-700 dark:text-teal-300 text-sm">{{ loan.name || getLoanTypeInfo(loan.loan_type).label }}</div>
                  <div class="text-xs text-teal-600/60 dark:text-teal-400/60">已还清 {{ formatMoney(loan.total_paid) }}</div>
                </div>
              </div>
              <button :aria-label="`删除提醒 ${loan.name}`" class="min-h-11 min-w-11 flex items-center justify-center text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition" @click="confirmDelete(loan.id, $event)">
                <Trash2 :size="14" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Inactive Loans -->
      <div v-if="inactiveLoans.length > 0">
        <h2 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-3">已暂停</h2>
        <div class="space-y-2">
          <div 
            v-for="loan in inactiveLoans" 
            :key="loan.id"
            class="bg-gray-100/50 dark:bg-gray-800/50 backdrop-blur-xl rounded-xl p-3 border border-gray-200/30 dark:border-gray-700/30 hover:bg-white/70 dark:hover:bg-gray-700/70 transition-all duration-200 group opacity-60 hover:opacity-100"
          >
            <div class="flex justify-between items-center">
              <div class="flex items-center gap-3">
                <div class="w-9 h-9 rounded-lg bg-gray-100 dark:bg-gray-700 flex items-center justify-center text-gray-400">
                  <BellOff :size="18" />
                </div>
                <div>
                  <div class="font-medium text-gray-700 dark:text-gray-300 text-sm">{{ loan.name || getLoanTypeInfo(loan.loan_type).label }}</div>
                  <div class="text-xs text-gray-400">每月 {{ loan.payment_day }} 日</div>
                </div>
              </div>
              <div class="flex gap-0.5">
                <button :aria-label="`启用提醒 ${loan.name}`" class="min-h-11 min-w-11 flex items-center justify-center text-gray-400 hover:text-teal-500 hover:bg-teal-50 dark:hover:bg-teal-900/30 rounded-lg transition" @click="toggleReminder(loan.id)" title="启用">
                  <Bell :size="14" />
                </button>
                <button :aria-label="`删除提醒 ${loan.name}`" class="min-h-11 min-w-11 flex items-center justify-center text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition" @click="confirmDelete(loan.id, $event)">
                  <Trash2 :size="14" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Empty State -->
      <div v-if="!loading && reminders.length === 0" class="py-20 text-center">
        <div class="w-20 h-20 bg-gray-50 dark:bg-gray-700 rounded-full flex items-center justify-center mx-auto mb-4 text-4xl">
          💳
        </div>
        <p class="text-gray-500 mb-2">暂无还款提醒</p>
        <p class="text-gray-400 text-sm mb-6">添加提醒，跟踪还款进度，按时偿还</p>
        <button v-if="!props.embedded" class="px-6 py-2.5 bg-primary text-white rounded-xl hover:bg-primary/90 transition font-medium" @click="openCreate">
          添加提醒
        </button>
      </div>

      <!-- Loading -->
      <div v-if="loading" class="py-20 text-center text-gray-400">加载中...</div>
    </div>

    <!-- Create/Edit Dialog -->
    <AppDialog v-if="showDialog && props.active !== false" :title="editingReminder ? '编辑提醒' : '添加提醒'" :busy="saving || attachmentsUploading" :return-focus="dialogTrigger" :fallback-focus="dialogFallback" sheet @close="(saving || attachmentsUploading) || (closeDialog())">
      <fieldset :disabled="saving || attachmentsUploading" class="min-w-0 border-0 p-0 m-0"><div class="space-y-5">
            <!-- Loan Type -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">负债类型</label>
              <div class="grid grid-cols-3 sm:grid-cols-5 gap-2">
                <button
                  v-for="type in loanTypes"
                  :key="type.value"
                  class="flex flex-col items-center gap-1 p-3 rounded-xl border-2 transition-all"
                  :class="form.loan_type === type.value ? 'border-primary bg-primary/5' : 'border-gray-100 dark:border-gray-700 hover:border-gray-200'"
                  @click="selectLoanType(type.value)"
                >
                  <component :is="type.icon" :size="20" :style="{ color: type.color }" />
                  <span class="whitespace-nowrap text-[10px] text-gray-500 dark:text-gray-400">{{ type.label }}</span>
                </button>
              </div>
            </div>

            <!-- Link Account -->
            <div v-if="debtAccounts.length > 0">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">关联账户（可选）</label>
              <select
                :value="form.account_id || ''"
                aria-label="提醒关联账户"
                class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-hidden appearance-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                @change="(e: any) => selectAccount(e.target.value || undefined)"
              >
                <option value="">不关联账户</option>
                <option v-for="acc in debtAccounts" :key="acc.id" :value="acc.id">
                  {{ acc.name }} ({{ formatMoney(Math.abs(acc.current_balance)) }})
                </option>
              </select>
              <p class="text-xs text-gray-400 mt-1">选择后自动填充账户信息，还款时同步更新余额</p>
            </div>

            <!-- Name -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">提醒名称</label>
              <input name="name" aria-label="提醒名称" style="min-width: 0; max-width: 100%"
                v-model="form.name"
                type="text"
                placeholder="例如：房贷、花呗"
                class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
              />
            </div>

            <!-- Payment Day -->
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">还款日</label>
                <input name="payment_day" aria-label="还款日" style="min-width: 0; max-width: 100%"
                  v-model.number="form.payment_day"
                  type="number"
                  min="1"
                  max="31"
                  placeholder="1-31"
                  class="w-full h-12 px-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                />
              </div>
              <div>
                <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">账单日（可选）</label>
                <input name="billing_day" aria-label="账单日" style="min-width: 0; max-width: 100%"
                  v-model.number="form.billing_day"
                  type="number"
                  min="1"
                  max="31"
                  placeholder="信用卡账单日"
                  class="w-full h-12 px-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                />
              </div>
            </div>

            <!-- Principal & Current Balance -->
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">负债总额</label>
                <div class="relative">
                  <span class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold">¥</span>
                  <input name="principal" aria-label="负债总额" style="min-width: 0; max-width: 100%"
                    v-model.number="form.principal"
                    type="number"
                    step="0.01"
                    placeholder="本金/额度"
                    class="w-full h-12 pl-10 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                  />
                </div>
              </div>
              <div>
                <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">当前欠款</label>
                <div class="relative">
                  <span class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold">¥</span>
                  <input name="current_balance" aria-label="当前欠款" style="min-width: 0; max-width: 100%"
                    v-model.number="form.current_balance"
                    type="number"
                    step="0.01"
                    placeholder="待还金额"
                    class="w-full h-12 pl-10 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                  />
                </div>
              </div>
            </div>

            <!-- Monthly Payment -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">月供/最低还款</label>
              <div class="relative">
                <span class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold">¥</span>
                <input name="amount" aria-label="月供/最低还款" style="min-width: 0; max-width: 100%"
                  v-model.number="form.amount"
                  type="number"
                  step="0.01"
                  placeholder="每月还款金额"
                  class="w-full h-12 pl-10 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                />
              </div>
            </div>

            <!-- Advance Days -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">提前几天提醒</label>
              <input name="advance_days" aria-label="提前几天提醒" style="min-width: 0; max-width: 100%"
                v-model.number="form.advance_days"
                type="number"
                min="0"
                max="30"
                class="w-full h-12 px-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
              />
            </div>

            <!-- Remark -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">备注（可选）</label>
              <input name="remark" aria-label="备注" style="min-width: 0; max-width: 100%"
                v-model="form.remark"
                type="text"
                placeholder="添加备注"
                class="w-full h-12 px-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
              />
            </div>

            <!-- Evidence Attachments -->
            <div v-if="editingReminder">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
                <Paperclip :size="14" class="inline mr-1" />合同/凭证
              </label>
              <FileUpload
                :key="editingReminder.id"
                :disabled="saving"
                @uploading-change="attachmentsUploading = $event"
                v-model="form.evidence"
                category="reminders"
                :ref-id="editingReminder.id"
                :max-files="5"
              />
            </div>
            <div v-else class="text-xs text-gray-400 italic">
              保存后可添加合同/凭证附件
            </div>


          </div>
      </fieldset>
      <template #footer><button
              class="w-full h-12 bg-primary text-white rounded-xl font-bold hover:bg-primary/90 transition shadow-lg shadow-primary/20 disabled:opacity-50 disabled:cursor-not-allowed"
              :disabled="saving || attachmentsUploading"
              @click="submitForm"
            >
              {{ attachmentsUploading ? '附件上传中…' : saving ? '保存中…' : '保存' }}
            </button></template>
    </AppDialog>

    <!-- Record Payment Dialog -->
    <AppDialog v-if="showPaymentDialog && props.active !== false" title="记录还款" :busy="paying" :return-focus="dialogTrigger" :fallback-focus="dialogFallback" sheet @close="(paying) || (closePaymentDialog())">
      <fieldset :disabled="paying" class="min-w-0 border-0 p-0 m-0"><p class="text-gray-500 dark:text-gray-400 text-center text-sm mb-4">{{ payingReminder?.name }}</p>
          <div class="relative mb-4">
            <label class="block text-sm text-gray-500 dark:text-gray-400 mb-2">还款总额</label>
            <span class="absolute left-4 bottom-4 text-gray-400 font-bold text-lg">¥</span>
            <input name="paymentAmount" aria-label="还款总额" style="min-width: 0; max-width: 100%"
              v-model.number="paymentAmount"
              :disabled="paying || !!pendingPayment"
              type="number"
              step="0.01"
              class="w-full h-14 pl-10 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all text-2xl font-bold text-center dark:text-white"
            />
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-4">
            <div>
              <label class="block text-sm text-gray-500 dark:text-gray-400 mb-2">本金</label>
              <div class="relative">
                <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">¥</span>
                <input name="paymentPrincipal" aria-label="本金" style="min-width: 0; max-width: 100%"
                  v-model.number="paymentPrincipal"
                  :disabled="paying || !!pendingPayment"
                  type="number"
                  step="0.01"
                  placeholder="可选"
                  class="w-full h-12 pl-8 pr-3 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all dark:text-white"
                />
              </div>
            </div>
            <div>
              <label class="block text-sm text-gray-500 dark:text-gray-400 mb-2">利息</label>
              <div class="relative">
                <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">¥</span>
                <input name="paymentInterest" aria-label="利息" style="min-width: 0; max-width: 100%"
                  v-model.number="paymentInterest"
                  :disabled="paying || !!pendingPayment"
                  type="number"
                  step="0.01"
                  placeholder="可选"
                  class="w-full h-12 pl-8 pr-3 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all dark:text-white"
                />
              </div>
            </div>
          </div>
          <div class="mb-4">
            <label class="block text-sm text-gray-500 dark:text-gray-400 mb-2">还款账户</label>
            <select name="paymentAccountId" aria-label="还款账户" style="min-width: 0; max-width: 100%"
              v-model="paymentAccountId"
              :disabled="paying || !!pendingPayment"
              class="w-full h-12 px-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all dark:text-white"
            >
              <option value="">请选择账户</option>
              <option v-for="acc in sourceAccounts" :key="acc.id" :value="acc.id">
                {{ acc.name }}（¥{{ acc.current_balance.toFixed(2) }}）
              </option>
            </select>
            <p class="text-xs text-gray-400 mt-2">选择账户后将自动扣减余额并记录到明细</p>
          </div>

          <p v-if="paymentError" role="alert" class="mt-3 text-sm text-amber-700 dark:text-amber-300">{{ paymentError }}</p>
      </fieldset>
      <template #footer><button
              class="flex-1 py-3 border border-gray-200 dark:border-gray-600 rounded-xl text-gray-700 dark:text-gray-300 font-medium hover:bg-gray-50 dark:hover:bg-gray-700 transition"
              @click="closePaymentDialog"
             :disabled="paying">
              取消
            </button>
            <button
              class="flex-1 py-3 bg-green-500 text-white rounded-xl font-medium hover:bg-green-600 transition shadow-lg shadow-green-500/30 disabled:opacity-50 disabled:cursor-not-allowed"
              :disabled="paying"
              @click="submitPayment"
            >
              {{ paying ? '确认中…' : pendingPayment ? '确认上次还款结果' : '确认还款' }}
            </button></template>
    </AppDialog>

    <!-- Delete Confirm Modal -->
    <AppDialog v-if="showDeleteModal && props.active !== false" title="确认删除" :busy="deleting" :return-focus="dialogTrigger" :fallback-focus="dialogFallback" sheet @close="(deleting) || (showDeleteModal = false)">
      <fieldset :disabled="deleting" class="min-w-0 border-0 p-0 m-0"><p class="text-gray-500 dark:text-gray-400 text-center text-sm mb-6">删除后相关还款记录将从提醒中移除，已生成的账本交易会保留。</p>
      </fieldset>
      <template #footer><button
              class="flex-1 py-3 border border-gray-200 dark:border-gray-600 rounded-xl text-gray-700 dark:text-gray-300 font-medium hover:bg-gray-50 dark:hover:bg-gray-700 transition"
              @click="showDeleteModal = false"
             :disabled="deleting">
              取消
            </button>
            <button
              class="flex-1 py-3 bg-red-500 text-white rounded-xl font-medium hover:bg-red-600 transition shadow-lg shadow-red-500/30"
              @click="handleDelete"
             :disabled="deleting">
              确认删除
            </button></template>
    </AppDialog>
  </div>
</template>
