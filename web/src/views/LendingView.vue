<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronLeft, Plus, Trash2, Edit2, X, User, ArrowDownLeft, ArrowUpRight, Check, ChevronDown, Paperclip } from 'lucide-vue-next'
import FileUpload from '@/components/FileUpload.vue'
import { lendingApi, type Lending, type CreateLendingParams, type LendingSummary, type RecordRepaymentParams } from '@/api/lending'
import { accountApi, type Account } from '@/api/account'
import { toast } from '@/composables/useToast'
import { deleteRemovedAttachments } from '@/utils/attachmentCleanup'
import dayjs from 'dayjs'

const router = useRouter()

const lendings = ref<Lending[]>([])
const accounts = ref<Account[]>([])
const summary = ref<LendingSummary | null>(null)
const loading = ref(false)
const activeTab = ref<'lend_out' | 'borrow_in' | 'settled'>('lend_out')

const showDialog = ref(false)
const editingLending = ref<Lending | null>(null)
const originalEvidence = ref('')
const form = ref<CreateLendingParams>({
  type: 'lend_out',
  contact_name: '',
  contact_phone: '',
  contact_remark: '',
  principal: 0,
  interest_rate: undefined,
  lend_date: dayjs().format('YYYY-MM-DDTHH:mm'),
  due_date: undefined,
  account_id: undefined,
  remark: '',
  evidence: '',
  create_transaction: true
})

const showRepayDialog = ref(false)
const repayingLending = ref<Lending | null>(null)
const repayForm = ref<RecordRepaymentParams>({
  amount: 0,
  record_date: dayjs().format('YYYY-MM-DDTHH:mm'),
  account_id: undefined,
  remark: '',
  evidence: '',
  create_transaction: true
})

const showDeleteModal = ref(false)
const deletingId = ref<string | null>(null)

const activeLendOut = computed(() => lendings.value.filter(l => l.type === 'lend_out' && !l.is_settled))
const activeBorrowIn = computed(() => lendings.value.filter(l => l.type === 'borrow_in' && !l.is_settled))
const settledLendings = computed(() => lendings.value.filter(l => l.is_settled))

const displayList = computed(() => {
  if (activeTab.value === 'lend_out') return activeLendOut.value
  if (activeTab.value === 'borrow_in') return activeBorrowIn.value
  return settledLendings.value
})

// When account is selected, default to sync balance
watch(() => form.value.account_id, (newVal) => {
  if (newVal && !editingLending.value) {
    form.value.create_transaction = true
  }
})

watch(() => repayForm.value.account_id, (newVal) => {
  if (newVal) {
    repayForm.value.create_transaction = true
  }
})

onMounted(() => {
  loadData()
})

async function loadData() {
  loading.value = true
  try {
    const [lendingList, accountData, summaryData] = await Promise.all([
      lendingApi.list(true),
      accountApi.getList(),
      lendingApi.getSummary()
    ])
    lendings.value = lendingList
    accounts.value = accountData.list.filter(a => !a.is_archived)
    summary.value = summaryData
  } catch (e: any) {
    toast.error('加载数据失败')
  } finally {
    loading.value = false
  }
}

function formatMoney(amount: number | undefined): string {
  if (amount === undefined || amount === null) return '¥0.00'
  return `¥${amount.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')}`
}

function getProgress(lending: Lending): number {
  if (!lending.principal || lending.principal === 0) return 0
  return Math.min(100, (lending.total_repaid / lending.principal) * 100)
}

function getDaysInfo(lending: Lending): { text: string; color: string } {
  if (!lending.due_date) return { text: '', color: '' }
  const due = dayjs(lending.due_date)
  const today = dayjs()
  const diff = due.diff(today, 'day')
  
  if (diff < 0) return { text: `逾期 ${Math.abs(diff)} 天`, color: 'text-red-500' }
  if (diff === 0) return { text: '今天到期', color: 'text-amber-500' }
  if (diff <= 7) return { text: `${diff} 天后到期`, color: 'text-amber-500' }
  return { text: `${diff} 天后到期`, color: 'text-gray-400' }
}

function openCreate(type: 'lend_out' | 'borrow_in') {
  editingLending.value = null
  originalEvidence.value = ''
  form.value = {
    type,
    contact_name: '',
    contact_phone: '',
    contact_remark: '',
    principal: 0,
    interest_rate: undefined,
    lend_date: dayjs().format('YYYY-MM-DDTHH:mm'),
    due_date: undefined,
    account_id: undefined,
    remark: '',
    evidence: '',
    create_transaction: false
  }
  showDialog.value = true
}

function openEdit(lending: Lending) {
  editingLending.value = lending
  originalEvidence.value = lending.evidence || ''
  form.value = {
    type: lending.type,
    contact_name: lending.contact_name,
    contact_phone: lending.contact_phone || '',
    contact_remark: lending.contact_remark || '',
    principal: lending.principal,
    interest_rate: lending.interest_rate,
    lend_date: dayjs(lending.lend_date).format('YYYY-MM-DDTHH:mm'),
    due_date: lending.due_date ? dayjs(lending.due_date).format('YYYY-MM-DDTHH:mm') : undefined,
    account_id: lending.account_id,
    remark: lending.remark || '',
    evidence: lending.evidence || '',
    create_transaction: false
  }
  showDialog.value = true
}

function closeDialog() {
  showDialog.value = false
  editingLending.value = null
  originalEvidence.value = ''
}

async function submitForm() {
  if (!form.value.contact_name || form.value.principal <= 0) {
    toast.warning('请填写联系人和金额')
    return
  }

  try {
    if (editingLending.value) {
      await lendingApi.update(editingLending.value.id, {
        contact_name: form.value.contact_name,
        contact_phone: form.value.contact_phone,
        contact_remark: form.value.contact_remark,
        interest_rate: form.value.interest_rate,
        due_date: form.value.due_date,
        remark: form.value.remark,
        evidence: form.value.evidence
      })
      const failedCleanupPaths = await deleteRemovedAttachments(originalEvidence.value, form.value.evidence)
      toast.success(
        failedCleanupPaths.length > 0
          ? `更新成功，但有 ${failedCleanupPaths.length} 个旧附件清理失败`
          : '更新成功'
      )
    } else {
      await lendingApi.create(form.value)
      toast.success('创建成功')
    }
    closeDialog()
    loadData()
  } catch (e: any) {
    toast.error(e.response?.data?.error || '操作失败')
  }
}

function openRepay(lending: Lending) {
  repayingLending.value = lending
  repayForm.value = {
    amount: lending.current_balance,
    record_date: dayjs().format('YYYY-MM-DDTHH:mm'),
    account_id: undefined,
    remark: '',
    evidence: '',
    create_transaction: false
  }
  showRepayDialog.value = true
}

async function submitRepay() {
  if (!repayingLending.value || repayForm.value.amount <= 0) {
    toast.warning('请填写还款金额')
    return
  }

  try {
    await lendingApi.recordRepayment(repayingLending.value.id, repayForm.value)
    toast.success('还款记录成功')
    showRepayDialog.value = false
    loadData()
  } catch (e: any) {
    toast.error(e.response?.data?.error || '还款失败')
  }
}

function confirmDelete(id: string) {
  deletingId.value = id
  showDeleteModal.value = true
}

async function deleteItem() {
  if (!deletingId.value) return
  try {
    await lendingApi.delete(deletingId.value)
    toast.success('删除成功')
    showDeleteModal.value = false
    loadData()
  } catch (e: any) {
    toast.error('删除失败')
  }
}
</script>

<template>
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black pb-24 md:pb-8">
    <!-- Header -->
    <div class="bg-white/70 dark:bg-[#1C1C1E]/70 pt-4 pb-4 px-4 md:px-8 sticky top-0 z-30 backdrop-blur-xl border-b border-gray-200/50 dark:border-white/10">
      <div class="max-w-3xl mx-auto flex items-center justify-between">
        <div class="flex items-center gap-4">
          <button @click="router.back()" class="p-2 -ml-2 text-gray-500 hover:bg-gray-100 dark:hover:bg-white/10 rounded-xl transition">
            <ChevronLeft :size="20" />
          </button>
          <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-indigo-500 to-indigo-600 flex items-center justify-center shadow-lg shadow-indigo-500/20">
            <User class="text-white" :size="28" />
          </div>
          <div>
            <h1 class="text-xl font-bold text-gray-900 dark:text-white">借款管理</h1>
            <div class="text-sm text-gray-500 dark:text-gray-400 mt-0.5">{{ lendings.length }} 笔借款</div>
          </div>
        </div>
      </div>
    </div>

    <div class="max-w-3xl mx-auto px-4 md:px-8 py-6 space-y-6">
      <!-- Summary Cards -->
      <div v-if="summary" class="grid grid-cols-2 gap-4">
        <div class="bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl rounded-2xl p-5 border border-gray-200/50 dark:border-gray-700/50 shadow-sm">
          <div class="flex items-center gap-2 text-teal-600 dark:text-teal-400 mb-3">
            <ArrowUpRight :size="18" />
            <span class="text-sm font-medium">应收</span>
          </div>
          <div class="text-2xl font-bold text-gray-900 dark:text-white font-nums">{{ formatMoney(summary.total_receivable) }}</div>
          <div class="text-xs text-gray-400 mt-1">{{ summary.active_lend_out }} 笔进行中</div>
        </div>
        <div class="bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl rounded-2xl p-5 border border-gray-200/50 dark:border-gray-700/50 shadow-sm">
          <div class="flex items-center gap-2 text-indigo-600 dark:text-indigo-400 mb-3">
            <ArrowDownLeft :size="18" />
            <span class="text-sm font-medium">应付</span>
          </div>
          <div class="text-2xl font-bold text-gray-900 dark:text-white font-nums">{{ formatMoney(summary.total_payable) }}</div>
          <div class="text-xs text-gray-400 mt-1">{{ summary.active_borrow_in }} 笔进行中</div>
        </div>
      </div>

      <!-- Net Balance -->
      <div v-if="summary" class="bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl rounded-2xl p-4 border border-gray-200/50 dark:border-gray-700/50 shadow-sm flex items-center justify-between">
        <span class="text-sm text-gray-500 dark:text-gray-400">净借贷影响</span>
        <span class="font-bold font-nums" :class="summary.net_lending >= 0 ? 'text-teal-600 dark:text-teal-400' : 'text-rose-600 dark:text-rose-400'">
          {{ summary.net_lending >= 0 ? '+' : '' }}{{ formatMoney(summary.net_lending) }}
        </span>
      </div>

      <!-- Quick Actions -->
      <div class="grid grid-cols-2 gap-3">
        <button 
          @click="openCreate('lend_out')" 
          class="flex items-center justify-center gap-2 py-3.5 bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl text-teal-600 dark:text-teal-400 rounded-2xl font-medium border border-teal-200/50 dark:border-teal-800/50 hover:bg-teal-50 dark:hover:bg-teal-900/20 transition-all active:scale-[0.98] shadow-sm"
        >
          <Plus :size="18" />
          <span>记一笔借出</span>
        </button>
        <button 
          @click="openCreate('borrow_in')" 
          class="flex items-center justify-center gap-2 py-3.5 bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl text-indigo-600 dark:text-indigo-400 rounded-2xl font-medium border border-indigo-200/50 dark:border-indigo-800/50 hover:bg-indigo-50 dark:hover:bg-indigo-900/20 transition-all active:scale-[0.98] shadow-sm"
        >
          <Plus :size="18" />
          <span>记一笔借入</span>
        </button>
      </div>

      <!-- Tabs -->
      <div class="flex gap-1 p-1 bg-gray-100/60 dark:bg-gray-800/60 backdrop-blur-sm rounded-xl">
        <button
          class="flex-1 py-2.5 rounded-lg text-sm font-medium transition-all flex items-center justify-center gap-1.5"
          :class="activeTab === 'lend_out' ? 'bg-white dark:bg-gray-700 text-teal-600 dark:text-teal-400 shadow-sm' : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-300'"
          @click="activeTab = 'lend_out'"
        >
          <ArrowUpRight :size="16" />
          借出
        </button>
        <button
          class="flex-1 py-2.5 rounded-lg text-sm font-medium transition-all flex items-center justify-center gap-1.5"
          :class="activeTab === 'borrow_in' ? 'bg-white dark:bg-gray-700 text-indigo-600 dark:text-indigo-400 shadow-sm' : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-300'"
          @click="activeTab = 'borrow_in'"
        >
          <ArrowDownLeft :size="16" />
          借入
        </button>
        <button
          class="flex-1 py-2.5 rounded-lg text-sm font-medium transition-all flex items-center justify-center gap-1.5"
          :class="activeTab === 'settled' ? 'bg-white dark:bg-gray-700 text-gray-600 dark:text-gray-300 shadow-sm' : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-300'"
          @click="activeTab = 'settled'"
        >
          <Check :size="16" />
          已结清
        </button>
      </div>

      <!-- List -->
      <div class="space-y-3">
        <div v-if="displayList.length === 0" class="py-16 text-center">
          <div class="w-16 h-16 bg-gray-100 dark:bg-gray-800 rounded-full flex items-center justify-center mx-auto mb-4">
            <User :size="28" class="text-gray-400" />
          </div>
          <p class="text-gray-500">暂无{{ activeTab === 'lend_out' ? '借出' : activeTab === 'borrow_in' ? '借入' : '已结清' }}记录</p>
        </div>

        <div
          v-for="lending in displayList"
          :key="lending.id"
          class="bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl rounded-2xl p-5 border border-gray-200/50 dark:border-gray-700/50 shadow-sm hover:shadow-md transition-all duration-200 group"
        >
          <div class="flex items-start justify-between mb-4">
            <div class="flex items-center gap-3">
              <div 
                class="w-10 h-10 rounded-full flex items-center justify-center text-white font-medium text-sm"
                :class="lending.type === 'lend_out' ? 'bg-teal-500' : 'bg-indigo-500'"
              >
                {{ lending.contact_name.charAt(0) }}
              </div>
              <div>
                <h3 class="font-semibold text-gray-900 dark:text-white">{{ lending.contact_name }}</h3>
                <div class="flex items-center gap-2 text-xs text-gray-400">
                  <span>{{ dayjs(lending.lend_date).format('YYYY/MM/DD') }}</span>
                  <span v-if="getDaysInfo(lending).text" :class="getDaysInfo(lending).color">
                    {{ getDaysInfo(lending).text }}
                  </span>
                </div>
              </div>
            </div>
            <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
              <button 
                v-if="!lending.is_settled"
                @click="openRepay(lending)" 
                class="px-2.5 py-1 text-xs font-medium rounded-lg transition"
                :class="lending.type === 'lend_out' ? 'bg-teal-50 text-teal-600 hover:bg-teal-100 dark:bg-teal-900/30 dark:text-teal-400 dark:hover:bg-teal-900/50' : 'bg-indigo-50 text-indigo-600 hover:bg-indigo-100 dark:bg-indigo-900/30 dark:text-indigo-400 dark:hover:bg-indigo-900/50'"
              >
                还款
              </button>
              <button @click="openEdit(lending)" class="p-1.5 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition">
                <Edit2 :size="14" class="text-gray-400" />
              </button>
              <button @click="confirmDelete(lending.id)" class="p-1.5 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition">
                <Trash2 :size="14" class="text-gray-400 hover:text-red-500" />
              </button>
            </div>
          </div>

          <div class="flex items-end justify-between mb-3">
            <div>
              <p class="text-xs text-gray-400 mb-0.5">{{ lending.type === 'lend_out' ? '借出' : '借入' }}</p>
              <p class="text-lg font-bold text-gray-900 dark:text-white font-nums">{{ formatMoney(lending.principal) }}</p>
            </div>
            <div class="text-right">
              <p class="text-xs text-gray-400 mb-0.5">剩余</p>
              <p class="text-lg font-bold font-nums" :class="lending.type === 'lend_out' ? 'text-teal-600 dark:text-teal-400' : 'text-indigo-600 dark:text-indigo-400'">
                {{ formatMoney(lending.current_balance) }}
              </p>
            </div>
          </div>

          <div class="relative h-1 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
            <div 
              class="h-full rounded-full transition-all duration-500"
              :class="lending.type === 'lend_out' ? 'bg-teal-500' : 'bg-indigo-500'"
              :style="{ width: `${getProgress(lending)}%` }"
            ></div>
          </div>
          <div class="flex justify-between items-center mt-2 text-xs text-gray-400">
            <span>已还 {{ formatMoney(lending.total_repaid) }}</span>
            <span>{{ getProgress(lending).toFixed(0) }}%</span>
          </div>

          <p v-if="lending.remark" class="text-xs text-gray-500 mt-3 pt-3 border-t border-gray-100 dark:border-gray-700">
            {{ lending.remark }}
          </p>
        </div>
      </div>
    </div>

    <!-- Create/Edit Dialog -->
    <Teleport to="body">
      <div v-if="showDialog" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="closeDialog"></div>
        <div class="relative bg-white/90 dark:bg-gray-800/90 backdrop-blur-2xl rounded-3xl w-full max-w-md max-h-[90vh] flex flex-col shadow-2xl overflow-hidden animate-in zoom-in-95 duration-200 border border-white/20 dark:border-gray-700/50">
          <div class="flex items-center justify-between p-6 border-b border-gray-100/50 dark:border-gray-700/50 bg-transparent">
            <h3 class="text-lg font-bold text-gray-900 dark:text-white">
              {{ editingLending ? '编辑记录' : (form.type === 'lend_out' ? '记一笔借出' : '记一笔借入') }}
            </h3>
            <button class="p-2 hover:bg-gray-100/50 dark:hover:bg-gray-700/50 rounded-xl transition" @click="closeDialog">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div class="flex-1 overflow-y-auto p-6 space-y-5">
            <!-- Contact Name -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
                {{ form.type === 'lend_out' ? '借款人姓名' : '债权人姓名' }}
              </label>
              <input
                v-model="form.contact_name"
                type="text"
                placeholder="对方姓名"
                class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
              />
            </div>

            <!-- Amount -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">金额</label>
              <div class="relative">
                <span class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold text-2xl">¥</span>
                <input
                  v-model.number="form.principal"
                  type="number"
                  step="0.01"
                  placeholder="0.00"
                  class="w-full h-16 pl-10 pr-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-2xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-bold text-3xl text-gray-900 dark:text-white"
                />
              </div>
            </div>

            <!-- Dates -->
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">日期</label>
                <input
                  v-model="form.lend_date"
                  type="datetime-local"
                  class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all text-sm text-gray-900 dark:text-white"
                />
              </div>
              <div>
                <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">还款截止日（可选）</label>
                <input
                  v-model="form.due_date"
                  type="datetime-local"
                  class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all text-sm text-gray-900 dark:text-white"
                />
              </div>
            </div>

            <!-- Account Binding (Optional) -->
            <div v-if="!editingLending">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">关联账户（可选）</label>
              <div class="relative">
                <select
                  v-model="form.account_id"
                  class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none appearance-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
                >
                  <option :value="undefined">不关联</option>
                  <option v-for="account in accounts" :key="account.id" :value="account.id">
                    {{ account.name }} (¥{{ account.current_balance.toFixed(2) }})
                  </option>
                </select>
                <ChevronDown class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" :size="20" />
              </div>
            </div>

            <!-- Create Transaction -->
            <div v-if="form.account_id && !editingLending" class="flex items-center justify-between p-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl">
              <div>
                <p class="text-sm font-medium text-gray-900 dark:text-white">同步更新余额</p>
                <p class="text-xs text-gray-500">{{ form.type === 'lend_out' ? '从账户扣除金额' : '向账户增加金额' }}</p>
              </div>
              <label class="relative inline-flex items-center cursor-pointer">
                <input type="checkbox" v-model="form.create_transaction" class="sr-only peer" />
                <div class="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-primary/20 rounded-full peer dark:bg-gray-600 peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all dark:border-gray-600 peer-checked:bg-primary"></div>
              </label>
            </div>

            <!-- Remark -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">备注（可选）</label>
              <input
                v-model="form.remark"
                type="text"
                placeholder="添加备注"
                class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium dark:text-white"
              />
            </div>

            <!-- Evidence Attachments -->
            <div v-if="editingLending">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
                <Paperclip :size="14" class="inline mr-1" />凭证附件
              </label>
              <FileUpload
                v-model="form.evidence"
                category="lendings"
                :ref-id="editingLending.id"
                :max-files="5"
              />
            </div>
            <div v-else class="text-xs text-gray-400 italic">
              保存后可添加凭证附件
            </div>

            <button
              class="w-full h-12 rounded-xl font-bold transition shadow-sm mt-2"
              :class="form.type === 'lend_out' ? 'bg-teal-500 text-white hover:bg-teal-600' : 'bg-indigo-500 text-white hover:bg-indigo-600'"
              @click="submitForm"
            >
              {{ editingLending ? '保存' : '确认' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Repay Dialog -->
    <Teleport to="body">
      <div v-if="showRepayDialog" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="showRepayDialog = false"></div>
        <div class="relative bg-white/90 dark:bg-gray-800/90 backdrop-blur-2xl rounded-3xl w-full max-w-md shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-gray-700/50">
          <div class="flex items-center justify-between p-6 border-b border-gray-100/50 dark:border-gray-700/50 bg-transparent">
            <h3 class="text-lg font-bold text-gray-900 dark:text-white">记录还款</h3>
            <button class="p-2 hover:bg-gray-100/50 dark:hover:bg-gray-700/50 rounded-xl transition" @click="showRepayDialog = false">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div v-if="repayingLending" class="p-6 space-y-5">
            <!-- Info -->
            <div class="p-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl">
              <div class="flex items-center gap-3 mb-2">
                <div 
                  class="w-10 h-10 rounded-full flex items-center justify-center text-white font-medium"
                  :class="repayingLending.type === 'lend_out' ? 'bg-teal-500' : 'bg-indigo-500'"
                >
                  {{ repayingLending.contact_name.charAt(0) }}
                </div>
                <div>
                  <p class="font-bold text-gray-900 dark:text-white">{{ repayingLending.contact_name }}</p>
                  <p class="text-xs text-gray-500">剩余 {{ formatMoney(repayingLending.current_balance) }}</p>
                </div>
              </div>
            </div>

            <!-- Amount -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">还款金额 *</label>
              <div class="relative">
                <span class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold">¥</span>
                <input
                  v-model.number="repayForm.amount"
                  type="number"
                  step="0.01"
                  class="w-full h-12 pl-8 pr-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-bold text-lg text-gray-900 dark:text-white"
                />
              </div>
            </div>

            <!-- Date -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">日期</label>
              <input
                v-model="repayForm.record_date"
                type="datetime-local"
                class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all text-sm text-gray-900 dark:text-white"
              />
            </div>

            <!-- Account -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">关联账户</label>
              <div class="relative">
                <select
                  v-model="repayForm.account_id"
                  class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none appearance-none focus:ring-2 focus:ring-primary/20 transition-all text-gray-900 dark:text-white"
                >
                  <option :value="undefined">不关联</option>
                  <option v-for="account in accounts" :key="account.id" :value="account.id">
                    {{ account.name }}
                  </option>
                </select>
                <ChevronDown class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" :size="20" />
              </div>
            </div>

            <!-- Create Transaction -->
            <div v-if="repayForm.account_id" class="flex items-center justify-between p-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl">
              <div>
                <p class="text-sm font-medium text-gray-900 dark:text-white">同步更新余额</p>
                <p class="text-xs text-gray-500">{{ repayingLending.type === 'lend_out' ? '向账户增加金额' : '从账户扣除金额' }}</p>
              </div>
              <label class="relative inline-flex items-center cursor-pointer">
                <input type="checkbox" v-model="repayForm.create_transaction" class="sr-only peer" />
                <div class="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-primary/20 rounded-full peer dark:bg-gray-600 peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all dark:border-gray-600 peer-checked:bg-primary"></div>
              </label>
            </div>

            <!-- Repay Evidence -->
            <div v-if="repayingLending">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
                <Paperclip :size="14" class="inline mr-1" />还款凭证
              </label>
              <FileUpload
                v-model="repayForm.evidence"
                category="lendings"
                :ref-id="repayingLending.id + '_repay_' + Date.now()"
                :max-files="3"
              />
            </div>

            <button
              class="w-full h-12 bg-primary text-white rounded-xl font-bold hover:bg-primary/90 transition shadow-lg shadow-primary/20"
              @click="submitRepay"
            >
              确认还款
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Delete Modal -->
    <Teleport to="body">
      <div v-if="showDeleteModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="showDeleteModal = false"></div>
        <div class="relative bg-white/90 dark:bg-gray-800/90 backdrop-blur-2xl rounded-3xl p-6 w-full max-w-sm shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-gray-700/50">
          <div class="w-12 h-12 bg-red-100 dark:bg-red-900/30 rounded-full flex items-center justify-center mb-4 mx-auto text-red-500">
            <Trash2 :size="24" />
          </div>
          <h3 class="text-lg font-bold text-center mb-2 text-gray-900 dark:text-white">确认删除</h3>
          <p class="text-gray-500 text-center text-sm mb-6">删除后借贷和还款记录无法恢复，已生成的账本交易会保留。</p>
          <div class="flex gap-3">
            <button
              class="flex-1 py-3 border border-gray-200 dark:border-gray-600 rounded-xl text-gray-700 dark:text-gray-300 font-medium hover:bg-gray-50 dark:hover:bg-gray-700 transition"
              @click="showDeleteModal = false"
            >
              取消
            </button>
            <button
              class="flex-1 py-3 bg-red-500 text-white rounded-xl font-medium hover:bg-red-600 transition shadow-lg shadow-red-500/30"
              @click="deleteItem"
            >
              删除
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
