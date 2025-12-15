<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronLeft, Plus, Trash2, Edit2, X, Bell, BellOff, Calendar, CreditCard, Home, Car, Wallet, Target, Banknote, Paperclip } from 'lucide-vue-next'
import FileUpload from '@/components/FileUpload.vue'
import { reminderApi, type Reminder, type CreateReminderParams, type DebtSummary, type LoanType } from '@/api/reminder'
import { accountApi, type Account, isDebtAccount } from '@/api/account'
import { toast } from '@/composables/useToast'

const router = useRouter()

const reminders = ref<Reminder[]>([])
const accounts = ref<Account[]>([])
const debtSummary = ref<DebtSummary | null>(null)
const loading = ref(false)

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
const form = ref<CreateReminderParams>(defaultForm())

const showPaymentDialog = ref(false)
const payingReminder = ref<Reminder | null>(null)
const paymentAmount = ref<number>(0)
const paymentPrincipal = ref<number>(0)
const paymentInterest = ref<number>(0)
const paymentAccountId = ref<string>('')

const showDeleteModal = ref(false)
const deletingId = ref<string | null>(null)

const activeLoans = computed(() => reminders.value.filter(r => r.is_enabled && !r.paid_off_at))
const paidOffLoans = computed(() => reminders.value.filter(r => r.paid_off_at))
const inactiveLoans = computed(() => reminders.value.filter(r => !r.is_enabled && !r.paid_off_at))
const debtAccounts = computed(() => accounts.value.filter(a => isDebtAccount(a.type)))
const sourceAccounts = computed(() => accounts.value.filter(a => !isDebtAccount(a.type)))

onMounted(() => {
  loadData()
})

async function loadData() {
  loading.value = true
  try {
    const [reminderList, accountData, summary] = await Promise.all([
      reminderApi.getList(),
      accountApi.getList(),
      reminderApi.getDebtSummary()
    ])
    reminders.value = reminderList
    accounts.value = accountData.list
    debtSummary.value = summary
  } catch (e: any) {
    toast.error('加载数据失败')
  } finally {
    loading.value = false
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
  if (day >= currentDay) return day - currentDay
  return daysInMonth - currentDay + day
}

function openCreate() {
  editingReminder.value = null
  form.value = defaultForm()
  showDialog.value = true
}

function openEdit(reminder: Reminder) {
  editingReminder.value = reminder
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
  showDialog.value = false
  editingReminder.value = null
}

function openPayment(reminder: Reminder) {
  payingReminder.value = reminder
  paymentAmount.value = reminder.amount || 0
  paymentPrincipal.value = 0
  paymentInterest.value = 0
  paymentAccountId.value = ''
  showPaymentDialog.value = true
}

async function submitPayment() {
  if (!payingReminder.value || paymentAmount.value <= 0) return
  if (!paymentAccountId.value) {
    toast.warning('请选择还款账户')
    return
  }
  // Validate repayment doesn't exceed remaining balance
  const remaining = payingReminder.value.current_balance ?? 0
  if (remaining > 0 && paymentAmount.value > remaining) {
    toast.warning(`还款金额不能超过待还金额 ¥${remaining.toFixed(2)}`)
    return
  }
  // Validate principal + interest = total
  if (paymentPrincipal.value > 0 || paymentInterest.value > 0) {
    const sum = paymentPrincipal.value + paymentInterest.value
    if (Math.abs(sum - paymentAmount.value) > 0.01) {
      toast.warning('本金+利息必须等于还款金额')
      return
    }
  }
  try {
    await reminderApi.recordPayment(
      payingReminder.value.id, 
      paymentAmount.value,
      paymentAccountId.value,
      paymentPrincipal.value || undefined,
      paymentInterest.value || undefined
    )
    toast.success('还款记录成功，已同步到明细')
    showPaymentDialog.value = false
    payingReminder.value = null
    paymentAmount.value = 0
    paymentPrincipal.value = 0
    paymentInterest.value = 0
    paymentAccountId.value = ''
    loadData()
  } catch (e: any) {
    toast.error(e.message || '记录失败')
  }
}

async function submitForm() {
  if (!form.value.name) {
    toast.warning('请输入名称')
    return
  }

  try {
    if (editingReminder.value) {
      await reminderApi.update(editingReminder.value.id, form.value)
      toast.success('更新成功')
    } else {
      await reminderApi.create(form.value)
      toast.success('创建成功')
    }
    closeDialog()
    loadData()
  } catch (e: any) {
    toast.error(e.message || '保存失败')
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

function confirmDelete(id: string) {
  deletingId.value = id
  showDeleteModal.value = true
}

async function handleDelete() {
  if (!deletingId.value) return
  try {
    await reminderApi.delete(deletingId.value)
    showDeleteModal.value = false
    deletingId.value = null
    toast.success('删除成功')
    loadData()
  } catch (e: any) {
    toast.error(e.message || '删除失败')
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
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black pb-8">
    <!-- Header -->
    <div class="bg-white/70 dark:bg-[#1C1C1E]/70 pt-4 pb-4 px-4 md:px-8 sticky top-0 z-30 backdrop-blur-xl border-b border-gray-200/50 dark:border-white/10">
      <div class="max-w-3xl mx-auto flex items-center justify-between">
        <div class="flex items-center gap-4">
          <button @click="goBack" class="p-2 -ml-2 text-gray-500 hover:bg-gray-100 dark:hover:bg-white/10 rounded-xl transition">
            <ChevronLeft :size="20" />
          </button>
          <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-orange-500 to-orange-600 flex items-center justify-center shadow-lg shadow-orange-500/20">
            <Calendar class="text-white" :size="28" />
          </div>
          <div>
            <h1 class="text-xl font-bold text-gray-900 dark:text-white">负债管理</h1>
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

    <div class="max-w-3xl mx-auto px-4 md:px-8 py-6 space-y-6">
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
        <div class="grid grid-cols-2 gap-4">
          <div class="bg-gray-50 dark:bg-gray-700/50 rounded-xl p-3">
            <div class="text-xs text-gray-400 mb-1">待还总额</div>
            <div class="text-lg font-bold text-gray-900 dark:text-white font-nums">{{ formatMoney(debtSummary.total_debt) }}</div>
          </div>
          <div class="bg-gray-50 dark:bg-gray-700/50 rounded-xl p-3">
            <div class="text-xs text-gray-400 mb-1">已还金额</div>
            <div class="text-lg font-bold text-teal-600 dark:text-teal-400 font-nums">{{ formatMoney(debtSummary.total_paid) }}</div>
          </div>
        </div>
        <div v-if="paidOffLoans.length > 0" class="mt-4 pt-4 border-t border-gray-100 dark:border-gray-700 flex items-center gap-2 text-teal-600 dark:text-teal-400 text-sm">
          <span>🎉</span>
          <span>已还清 {{ paidOffLoans.length }} 笔分期</span>
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
              <div class="flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                <button class="p-1.5 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition" @click="openEdit(loan)">
                  <Edit2 :size="14" />
                </button>
                <button class="p-1.5 text-gray-400 hover:text-amber-500 hover:bg-amber-50 dark:hover:bg-amber-900/30 rounded-lg transition" @click="toggleReminder(loan.id)" title="禁用提醒">
                  <BellOff :size="14" />
                </button>
                <button class="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition" @click="confirmDelete(loan.id)">
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
              class="mt-3 w-full py-2 border border-dashed border-gray-200 dark:border-gray-600 rounded-lg text-gray-400 hover:border-primary hover:text-primary transition text-xs font-medium"
              @click="openPayment(loan)"
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
              <button class="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition opacity-0 group-hover:opacity-100" @click="confirmDelete(loan.id)">
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
              <div class="flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                <button class="p-1.5 text-gray-400 hover:text-teal-500 hover:bg-teal-50 dark:hover:bg-teal-900/30 rounded-lg transition" @click="toggleReminder(loan.id)" title="启用">
                  <Bell :size="14" />
                </button>
                <button class="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition" @click="confirmDelete(loan.id)">
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
        <p class="text-gray-500 mb-2">暂无分期记录</p>
        <p class="text-gray-400 text-sm mb-6">添加分期，跟踪还款进度，早日上岸</p>
        <button class="px-6 py-2.5 bg-primary text-white rounded-xl hover:bg-primary/90 transition font-medium" @click="openCreate">
          添加分期
        </button>
      </div>

      <!-- Loading -->
      <div v-if="loading" class="py-20 text-center text-gray-400">加载中...</div>
    </div>

    <!-- Create/Edit Dialog -->
    <Teleport to="body">
      <div v-if="showDialog" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="closeDialog"></div>
        <div class="relative bg-white/90 dark:bg-gray-800/90 backdrop-blur-2xl rounded-3xl w-full max-w-md max-h-[90vh] flex flex-col shadow-2xl overflow-hidden animate-in zoom-in-95 duration-200 border border-white/20 dark:border-gray-700/50">
          <div class="flex items-center justify-between p-6 border-b border-gray-100/50 dark:border-gray-700/50 bg-transparent">
            <h3 class="text-lg font-bold text-gray-900 dark:text-white">{{ editingReminder ? '编辑分期' : '添加分期' }}</h3>
            <button class="p-2 hover:bg-gray-100/50 dark:hover:bg-gray-700/50 rounded-xl transition" @click="closeDialog">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div class="flex-1 overflow-y-auto p-6 space-y-5">
            <!-- Loan Type -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">分期类型</label>
              <div class="grid grid-cols-5 gap-2">
                <button
                  v-for="type in loanTypes"
                  :key="type.value"
                  class="flex flex-col items-center gap-1 p-3 rounded-xl border-2 transition-all"
                  :class="form.loan_type === type.value ? 'border-primary bg-primary/5' : 'border-gray-100 dark:border-gray-700 hover:border-gray-200'"
                  @click="selectLoanType(type.value)"
                >
                  <component :is="type.icon" :size="20" :style="{ color: type.color }" />
                  <span class="text-[10px] text-gray-500 dark:text-gray-400">{{ type.label }}</span>
                </button>
              </div>
            </div>

            <!-- Link Account -->
            <div v-if="debtAccounts.length > 0">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">关联账户（可选）</label>
              <select
                :value="form.account_id || ''"
                class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none appearance-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
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
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">分期名称</label>
              <input
                v-model="form.name"
                type="text"
                placeholder="例如：房贷、花呗"
                class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
              />
            </div>

            <!-- Payment Day -->
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">还款日</label>
                <input
                  v-model.number="form.payment_day"
                  type="number"
                  min="1"
                  max="31"
                  placeholder="1-31"
                  class="w-full h-12 px-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                />
              </div>
              <div>
                <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">账单日（可选）</label>
                <input
                  v-model.number="form.billing_day"
                  type="number"
                  min="1"
                  max="31"
                  placeholder="信用卡账单日"
                  class="w-full h-12 px-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                />
              </div>
            </div>

            <!-- Principal & Current Balance -->
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">分期总额</label>
                <div class="relative">
                  <span class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold">¥</span>
                  <input
                    v-model.number="form.principal"
                    type="number"
                    step="0.01"
                    placeholder="本金/额度"
                    class="w-full h-12 pl-10 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                  />
                </div>
              </div>
              <div>
                <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">当前欠款</label>
                <div class="relative">
                  <span class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold">¥</span>
                  <input
                    v-model.number="form.current_balance"
                    type="number"
                    step="0.01"
                    placeholder="待还金额"
                    class="w-full h-12 pl-10 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                  />
                </div>
              </div>
            </div>

            <!-- Monthly Payment -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">月供/最低还款</label>
              <div class="relative">
                <span class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold">¥</span>
                <input
                  v-model.number="form.amount"
                  type="number"
                  step="0.01"
                  placeholder="每月还款金额"
                  class="w-full h-12 pl-10 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                />
              </div>
            </div>

            <!-- Advance Days -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">提前几天提醒</label>
              <input
                v-model.number="form.advance_days"
                type="number"
                min="0"
                max="30"
                class="w-full h-12 px-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
              />
            </div>

            <!-- Remark -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">备注（可选）</label>
              <input
                v-model="form.remark"
                type="text"
                placeholder="添加备注"
                class="w-full h-12 px-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
              />
            </div>

            <!-- Evidence Attachments -->
            <div v-if="editingReminder">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
                <Paperclip :size="14" class="inline mr-1" />合同/凭证
              </label>
              <FileUpload
                v-model="form.evidence"
                category="reminders"
                :ref-id="editingReminder.id"
                :max-files="5"
              />
            </div>
            <div v-else class="text-xs text-gray-400 italic">
              保存后可添加合同/凭证附件
            </div>

            <button
              class="w-full h-12 bg-primary text-white rounded-xl font-bold hover:bg-primary/90 transition shadow-lg shadow-primary/20"
              @click="submitForm"
            >
              保存
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Record Payment Dialog -->
    <Teleport to="body">
      <div v-if="showPaymentDialog" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="showPaymentDialog = false"></div>
        <div class="relative bg-white/90 dark:bg-gray-800/90 backdrop-blur-2xl rounded-3xl p-6 w-full max-w-sm shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-gray-700/50">
          <div class="w-12 h-12 bg-green-100 dark:bg-green-900/30 rounded-full flex items-center justify-center mb-4 mx-auto text-green-500">
            <Banknote :size="24" />
          </div>
          <h3 class="text-lg font-bold text-center mb-2 dark:text-white">记录还款</h3>
          <p class="text-gray-500 dark:text-gray-400 text-center text-sm mb-4">{{ payingReminder?.name }}</p>
          <div class="relative mb-4">
            <label class="block text-sm text-gray-500 dark:text-gray-400 mb-2">还款总额</label>
            <span class="absolute left-4 bottom-4 text-gray-400 font-bold text-lg">¥</span>
            <input
              v-model.number="paymentAmount"
              type="number"
              step="0.01"
              class="w-full h-14 pl-10 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all text-2xl font-bold text-center dark:text-white"
            />
          </div>
          <div class="grid grid-cols-2 gap-3 mb-4">
            <div>
              <label class="block text-sm text-gray-500 dark:text-gray-400 mb-2">本金</label>
              <div class="relative">
                <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">¥</span>
                <input
                  v-model.number="paymentPrincipal"
                  type="number"
                  step="0.01"
                  placeholder="可选"
                  class="w-full h-12 pl-8 pr-3 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all dark:text-white"
                />
              </div>
            </div>
            <div>
              <label class="block text-sm text-gray-500 dark:text-gray-400 mb-2">利息</label>
              <div class="relative">
                <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">¥</span>
                <input
                  v-model.number="paymentInterest"
                  type="number"
                  step="0.01"
                  placeholder="可选"
                  class="w-full h-12 pl-8 pr-3 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all dark:text-white"
                />
              </div>
            </div>
          </div>
          <div class="mb-4">
            <label class="block text-sm text-gray-500 dark:text-gray-400 mb-2">还款账户</label>
            <select
              v-model="paymentAccountId"
              class="w-full h-12 px-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all dark:text-white"
            >
              <option value="">请选择账户</option>
              <option v-for="acc in sourceAccounts" :key="acc.id" :value="acc.id">
                {{ acc.name }}（¥{{ acc.current_balance.toFixed(2) }}）
              </option>
            </select>
            <p class="text-xs text-gray-400 mt-2">选择账户后将自动扣减余额并记录到明细</p>
          </div>
          <div class="flex gap-3">
            <button
              class="flex-1 py-3 border border-gray-200 dark:border-gray-600 rounded-xl text-gray-700 dark:text-gray-300 font-medium hover:bg-gray-50 dark:hover:bg-gray-700 transition"
              @click="showPaymentDialog = false"
            >
              取消
            </button>
            <button
              class="flex-1 py-3 bg-green-500 text-white rounded-xl font-medium hover:bg-green-600 transition shadow-lg shadow-green-500/30"
              @click="submitPayment"
            >
              确认还款
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Delete Confirm Modal -->
    <Teleport to="body">
      <div v-if="showDeleteModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="showDeleteModal = false"></div>
        <div class="relative bg-white dark:bg-gray-800 rounded-3xl p-6 w-full max-w-sm shadow-2xl animate-in zoom-in-95 duration-200">
          <div class="w-12 h-12 bg-red-100 dark:bg-red-900/30 rounded-full flex items-center justify-center mb-4 mx-auto text-red-500">
            <Trash2 :size="24" />
          </div>
          <h3 class="text-lg font-bold text-center mb-2 dark:text-white">确认删除</h3>
          <p class="text-gray-500 dark:text-gray-400 text-center text-sm mb-6">删除后相关还款记录也将被清除。</p>
          <div class="flex gap-3">
            <button
              class="flex-1 py-3 border border-gray-200 dark:border-gray-600 rounded-xl text-gray-700 dark:text-gray-300 font-medium hover:bg-gray-50 dark:hover:bg-gray-700 transition"
              @click="showDeleteModal = false"
            >
              取消
            </button>
            <button
              class="flex-1 py-3 bg-red-500 text-white rounded-xl font-medium hover:bg-red-600 transition shadow-lg shadow-red-500/30"
              @click="handleDelete"
            >
              确认删除
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
