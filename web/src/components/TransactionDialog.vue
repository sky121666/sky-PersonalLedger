<script setup lang="ts">
import { ref, computed, nextTick, onBeforeUnmount, watch } from 'vue'
import { ChevronDown, Calendar, FileText, CreditCard, Paperclip, Users, Tag as TagIcon } from '@lucide/vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import FileUpload from '@/components/FileUpload.vue'
import DynamicIcon from '@/components/DynamicIcon.vue'
import { transactionApi, type CreateTransactionParams } from '@/api/transaction'
import { authApi } from '@/api/auth'
import { createTransactionJournal, isTransactionWriteRejection, type PendingTransactionWrite } from '@/utils/transactionWriteJournal'
import { categoryApi, type Category } from '@/api/category'
import { accountApi, type Account } from '@/api/account'
import { familyApi, type FamilyMember } from '@/api/family'
import { tagApi, type Tag } from '@/api/tag'
import { toast } from '@/composables/useToast'
import { deleteRemovedAttachments } from '@/utils/attachmentCleanup'
import { getCategoryEmoji } from '@/utils/constants'
import { encodeTransactionTags, parseTransactionTags } from '@/utils/tagValues'
import { loadTransactionDialogOptions } from '@/utils/transactionDialogOptions'
import { toLedgerInstant } from '@/utils/ledgerDate'
import { createRequestGeneration } from '@/utils/requestGeneration'
import { notifyLedgerMutation } from '@/composables/useLedgerMutation'
import dayjs from 'dayjs'

const props = defineProps<{
  visible: boolean
  editId?: string | null
}>()

const emit = defineEmits<{
  (e: 'update:visible', value: boolean): void
  (e: 'success'): void
}>()

const loading = ref(false)
const loadingInitialData = ref(false)
const transactionLoadFailed = ref(false)
const amountInput = ref<HTMLInputElement | null>(null)
const transactionTrigger = ref<HTMLElement | null>(null)
const categories = ref<Category[]>([])
const accounts = ref<Account[]>([])
const familyMembers = ref<FamilyMember[]>([])
const tags = ref<Tag[]>([])
const dialogRequests = createRequestGeneration()
const dialogGeneration = ref(0)
const editTargetId = ref<string | null>(null)
const pendingCreate = ref<PendingTransactionWrite | null>(null)
const confirmationIssue = ref('')
const attachmentsUploading = ref(false)
let createJournal: ReturnType<typeof createTransactionJournal> | null = null

const form = ref({
  type: 'expense' as 'income' | 'expense' | 'transfer',
  amount: '',
  account_id: '',
  to_account_id: '',
  category_id: '',
  member_id: '',
  paid_by_member_id: '',
  tag_names: [] as string[],
  transaction_date: dayjs().format('YYYY-MM-DDTHH:mm'),
  remark: '',
  images: ''
})

const savedTransactionId = ref<string | null>(null)
const originalImages = ref('')

const typeOptions = [
  { value: 'expense', label: '支出' },
  { value: 'income', label: '收入' },
  { value: 'transfer', label: '转账' }
]

const categoryGroups = computed(() => {
  if (form.value.type === 'transfer') return []
  const groups = new Map<string, Category[]>()
  for (const category of categories.value) {
    if (category.type !== form.value.type) continue
    const group = groups.get(category.name) || []
    group.push(category)
    groups.set(category.name, group)
  }
  return [...groups.values()]
})
// Group only the picker presentation; historical IDs and API results stay intact.
const filteredCategories = computed(() => categoryGroups.value.map(group =>
  group.find(category => category.id === form.value.category_id) || group[0]!
))
const duplicateCategoryGroups = computed(() => categoryGroups.value.filter(group => group.length > 1))

const isValid = computed(() => {
  if (loadingInitialData.value || transactionLoadFailed.value) return false
  if (pendingCreate.value && !editTargetId.value) return true
  const { type, amount, account_id, to_account_id, category_id } = form.value
  if (!amount || parseFloat(amount) <= 0) return false
  if (!account_id) return false
  if (type === 'transfer' && (!to_account_id || to_account_id === account_id)) return false
  if (type !== 'transfer' && !category_id) return false
  return true
})

function isCurrentDialog(generation: number, editId: string | null) {
  return dialogRequests.isLatest(generation) && props.visible && (props.editId || null) === editId
}

watch(() => [props.visible, props.editId] as const, async ([visible, id]) => {
  const generation = dialogRequests.begin()
  dialogGeneration.value = generation
  const editId = id || null
  editTargetId.value = editId
  loading.value = false
  if (!visible) {
    loadingInitialData.value = false
    return
  }
  transactionTrigger.value = document.activeElement instanceof HTMLElement
    ? document.activeElement
    : null
  loadingInitialData.value = true
  transactionLoadFailed.value = false
  resetForm('')
  pendingCreate.value = null
  confirmationIssue.value = ''
  attachmentsUploading.value = false
  createJournal = null
  try {
    await loadData(generation, editId)
    if (!isCurrentDialog(generation, editId)) return
    if (editId) {
      const loaded = await loadTransaction(editId, generation)
      if (isCurrentDialog(generation, editId)) transactionLoadFailed.value = !loaded
    } else {
      const profile = await authApi.getProfile()
      if (!isCurrentDialog(generation, editId)) return
      createJournal = createTransactionJournal(profile.id)
      pendingCreate.value = createJournal.read()
      if (pendingCreate.value) {
        const payload = pendingCreate.value.payload
        form.value = {
          type: payload.type, amount: String(payload.amount), account_id: payload.account_id,
          to_account_id: payload.to_account_id || '', category_id: payload.category_id || '',
          member_id: payload.member_id || '', paid_by_member_id: payload.paid_by_member_id || '',
          tag_names: parseTransactionTags(payload.tags), transaction_date: dayjs(payload.transaction_date).format('YYYY-MM-DDTHH:mm'),
          remark: payload.remark || '', images: '',
        }
      }
    }
  } catch (error) {
    if (isCurrentDialog(generation, editId)) {
      transactionLoadFailed.value = true
      toast.error((error as Error).message || '无法确认当前记账状态，请关闭后重试')
    }
  } finally {
    if (isCurrentDialog(generation, editId)) loadingInitialData.value = false
  }
  if (isCurrentDialog(generation, editId)) {
    await nextTick()
    if (isCurrentDialog(generation, editId)) amountInput.value?.focus()
  }
}, { immediate: true, flush: 'sync' })

watch(() => form.value.type, () => {
  // Initial detail hydration may include a retired category. A user changing
  // transaction type must choose again, even when that category is no longer
  // present in the active options.
  if (loadingInitialData.value) return
  form.value.category_id = ''
  form.value.to_account_id = ''
}, { flush: 'sync' })

async function loadData(generation: number, editId: string | null) {
  const options = await loadTransactionDialogOptions({
    categories: categoryApi.getList,
    accounts: accountApi.getList,
    familyMembers: familyApi.listMembers,
    tags: tagApi.list,
  })
  if (!isCurrentDialog(generation, editId)) return
  categories.value = options.categories
  accounts.value = options.accounts
  familyMembers.value = options.familyMembers.filter(member => member.is_enabled)
  tags.value = options.tags

  for (const [source, error] of Object.entries(options.failures)) {
    console.error(`Load transaction dialog ${source} failed:`, error)
  }

  if (accounts.value.length > 0 && !form.value.account_id) {
    form.value.account_id = accounts.value[0].id
  }
}

async function loadTransaction(editId: string, generation: number) {
  try {
    const tx = await transactionApi.getById(editId)
    if (!isCurrentDialog(generation, editId)) return false
    form.value = {
      type: tx.type,
      amount: tx.amount.toString(),
      account_id: tx.account_id,
      to_account_id: tx.to_account_id || '',
      category_id: tx.category_id || '',
      member_id: tx.member_id || '',
      paid_by_member_id: tx.paid_by_member_id || '',
      tag_names: parseTransactionTags(tx.tags),
      transaction_date: dayjs(tx.transaction_date).format('YYYY-MM-DDTHH:mm'),
      remark: tx.remark || '',
      images: tx.images || ''
    }
    originalImages.value = tx.images || ''
    savedTransactionId.value = tx.id
    return true
  } catch (e) {
    if (!isCurrentDialog(generation, editId)) return false
    console.error('Load transaction failed:', e)
    toast.error('交易详情加载失败，请关闭后重试')
    return false
  }
}

function resetForm(accountId = accounts.value[0]?.id || '') {
  form.value = {
    type: 'expense',
    amount: '',
    account_id: accountId,
    to_account_id: '',
    category_id: '',
    member_id: '',
    paid_by_member_id: '',
    tag_names: [],
    transaction_date: dayjs().format('YYYY-MM-DDTHH:mm'),
    remark: '',
    images: ''
  }
  originalImages.value = ''
  savedTransactionId.value = null
}

function close() {
  dialogRequests.begin()
  loadingInitialData.value = false
  emit('update:visible', false)
}

onBeforeUnmount(() => {
  dialogRequests.begin()
})

async function submit() {
  if (!isValid.value || loading.value || attachmentsUploading.value) return
  
  const generation = dialogGeneration.value
  const editId = editTargetId.value
  if (!isCurrentDialog(generation, editId)) return
  const submittedForm = { ...form.value, tag_names: [...form.value.tag_names] }
  const submittedOriginalImages = originalImages.value
  const journal = createJournal
  let attempted: PendingTransactionWrite | null = null
  loading.value = true
  try {
    // Convert datetime-local to ISO string
    const txDate = toLedgerInstant(submittedForm.transaction_date)
    
    const params: CreateTransactionParams = {
      type: submittedForm.type,
      amount: parseFloat(submittedForm.amount),
      account_id: submittedForm.account_id,
      transaction_date: txDate,
      remark: submittedForm.remark || undefined,
      images: submittedForm.images || undefined,
      tags: encodeTransactionTags(submittedForm.tag_names)
    }

    params.member_id = submittedForm.member_id || undefined
    params.paid_by_member_id = submittedForm.paid_by_member_id || undefined
    
    if (submittedForm.type === 'transfer') {
      params.to_account_id = submittedForm.to_account_id
    } else {
      params.category_id = submittedForm.category_id
    }
    
    if (editId) {
      await transactionApi.update(editId, params)
      const failedCleanupPaths = await deleteRemovedAttachments(submittedOriginalImages, submittedForm.images)
      if (isCurrentDialog(generation, editId)) toast.success(
        failedCleanupPaths.length > 0
          ? `修改成功，但有 ${failedCleanupPaths.length} 个旧附件清理失败`
          : '修改成功'
      )
    } else {
      if (!journal) throw Error('尚未确认当前用户，请关闭后重新打开')
      const stored = journal.read()
      if (stored && pendingCreate.value && stored.key !== pendingCreate.value.key) throw Error('记账确认记录已变化，请关闭后重新打开')
      const record = stored || pendingCreate.value || journal.stage(params)
      attempted = journal.attempt(record)
      if (isCurrentDialog(generation, editId)) pendingCreate.value = attempted
      await transactionApi.create(attempted.payload)
      notifyLedgerMutation()
      if (!journal.clear(attempted)) throw Error('另一轮结果确认仍在进行，请继续确认上次记账')
      if (isCurrentDialog(generation, editId)) pendingCreate.value = null
      if (isCurrentDialog(generation, editId)) toast.success('记账成功')
    }
    
    if (editId) notifyLedgerMutation()
    if (isCurrentDialog(generation, editId)) {
      emit('success')
      close()
    }
  } catch (e: any) {
    if (isCurrentDialog(generation, editId) && attempted && [40903, 40913].includes(e.code)) {
      confirmationIssue.value = `${e.message || '原记账状态已变化'}。请先核对明细；结束确认不会新增或撤销交易。`
    }
    if (attempted?.attempt === 1 && isTransactionWriteRejection(e) && journal) {
      try {
        if (journal.clear(attempted) && isCurrentDialog(generation, editId)) pendingCreate.value = null
      } catch (storageError) {
        if (isCurrentDialog(generation, editId)) toast.error((storageError as Error).message)
      }
    }
    if (isCurrentDialog(generation, editId)) toast.error(e.message || '保存失败')
  } finally {
    if (isCurrentDialog(generation, editId)) loading.value = false
  }
}

function finishCreateConfirmation() {
  if (loading.value || !confirmationIssue.value || !pendingCreate.value || !createJournal) return
  try {
    const current = createJournal.read()
    if (current && !createJournal.clear(pendingCreate.value)) throw Error('另一轮确认正在进行，请重新打开后核对')
    pendingCreate.value = null
    confirmationIssue.value = ''
    resetForm()
    toast.success('已结束本次确认，没有新增或撤销交易')
  } catch (error) {
    toast.error((error as Error).message)
  }
}

function toggleTag(name: string) {
  const selected = form.value.tag_names
  form.value.tag_names = selected.includes(name)
    ? selected.filter((value) => value !== name)
    : [...selected, name]
}
</script>

<template>
  <AppDialog v-if="visible" :title="props.editId ? '编辑交易' : '新增交易'" close-label="关闭交易表单" :busy="loading || attachmentsUploading" :return-focus="transactionTrigger" sheet @close="close">
    <form id="transaction-form" @submit.prevent="submit">
        <div class="flex justify-center mb-4">
          <!-- Segmented Control -->
          <div class="flex bg-gray-100/80 dark:bg-gray-700/80 p-1 rounded-xl backdrop-blur-sm">
            <button
              v-for="opt in typeOptions"
              :key="opt.value"
              type="button"
              :aria-pressed="form.type === opt.value"
              :disabled="loadingInitialData || transactionLoadFailed || loading || !!pendingCreate"
              class="min-h-11 px-4 py-1.5 text-sm font-medium rounded-lg transition-all duration-200"
              :class="form.type === opt.value ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-white shadow-sm' : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200'"
              @click="form.type = opt.value as any"
            >
              {{ opt.label }}
            </button>
          </div>

        </div>

        <!-- Form Content -->
        <p v-if="pendingCreate" role="status" class="px-6 pb-2 text-sm text-amber-700 dark:text-amber-300">
          上次记账结果尚未确认，已保留原金额及账户。请先确认上次结果。
        </p>
        <div v-if="confirmationIssue" role="alert" class="px-6 pb-3 text-sm text-amber-700 dark:text-amber-300">
          <p>{{ confirmationIssue }}</p>
          <div class="mt-2 flex flex-wrap gap-3">
            <a href="#/transactions" class="inline-flex min-h-11 items-center text-primary underline" :aria-disabled="loading || attachmentsUploading" @click="loading || attachmentsUploading ? $event.preventDefault() : close()">查看明细</a>
            <button type="button" :disabled="loading" class="min-h-11 underline" @click="finishCreateConfirmation">核对后结束确认</button>
          </div>
        </div>
        <!-- Keep native fieldset layout separate from the scroll container. -->
        <div class="min-w-0">
        <fieldset :disabled="loadingInitialData || transactionLoadFailed || loading || !!pendingCreate" class="min-w-0 border-0 p-0 m-0 space-y-6">
          <!-- Amount Input -->
          <div>
            <label for="transaction-amount" class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">金额</label>
            <div class="relative group">
              <span class="absolute left-4 top-1/2 -translate-y-1/2 text-2xl font-bold text-gray-400 transition-colors group-focus-within:text-primary">¥</span>
              <input
                ref="amountInput"
                id="transaction-amount"
                v-model="form.amount"
                type="number"
                step="0.01"
                placeholder="0.00"
                class="w-full h-16 pl-10 pr-4 text-3xl font-bold bg-gray-50/50 dark:bg-gray-700/50 dark:text-white rounded-2xl border-2 border-transparent outline-hidden focus:bg-white dark:focus:bg-gray-600 focus:border-primary/20 transition-all placeholder:text-gray-300 dark:placeholder:text-gray-500"
              />
            </div>
          </div>
          
          <!-- Category Grid -->
          <div v-if="form.type !== 'transfer'">
            <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">选择分类</label>
            <div class="grid grid-cols-5 gap-3">
              <button
                v-for="cat in filteredCategories"
                :key="cat.id"
                type="button"
                :aria-label="`选择${cat.name}分类`"
                :aria-pressed="form.category_id === cat.id"
                class="flex flex-col items-center gap-1 group"
                @click="form.category_id = cat.id"
              >
                <div 
                  class="w-12 h-12 rounded-2xl flex items-center justify-center text-xl transition-all duration-200 border-2"
                  :class="form.category_id === cat.id 
                    ? 'scale-110 shadow-lg border-primary' 
                    : 'border-transparent hover:scale-105'"
                  :style="{ 
                    backgroundColor: form.category_id === cat.id 
                      ? (cat.color || '#007AFF') + '20' 
                      : (cat.color || '#94a3b8') + '15'
                  }"
                >
                  <DynamicIcon :icon="getCategoryEmoji(cat.name, cat.icon)" :size="20" />
                </div>
                <span 
                  class="text-[10px] font-medium truncate w-full text-center transition-colors"
                  :class="form.category_id === cat.id ? 'text-primary' : 'text-gray-500'"
                >
                  {{ cat.name }}
                </span>
              </button>
            </div>
            <details v-if="duplicateCategoryGroups.length" class="mt-4 rounded-xl bg-gray-50/60 p-3 dark:bg-white/5">
              <summary class="flex min-h-11 cursor-pointer items-center gap-2 text-sm text-gray-600 dark:text-gray-300">
                同名分类 <span class="text-xs text-gray-500">展开选择原分类</span>
              </summary>
              <p class="mb-3 text-xs leading-relaxed text-gray-500 dark:text-gray-400">同名分类仅在此分组，历史记录保持原分类。</p>
              <div v-for="group in duplicateCategoryGroups" :key="group[0]!.name" class="mb-3 last:mb-0">
                <p class="mb-2 text-sm font-semibold">{{ group[0]!.name }} · {{ group.length }} 个分类</p>
                <div class="grid grid-cols-2 gap-2">
                  <button v-for="(category, index) in group" :key="category.id" type="button"
                    :aria-label="`${category.name}，同名分类 ${index + 1}`" :aria-pressed="form.category_id === category.id"
                    class="flex min-h-11 items-center gap-2 rounded-xl border px-3 py-2 text-left text-xs"
                    :class="form.category_id === category.id ? 'border-primary text-primary bg-primary/10' : 'border-transparent hover:bg-gray-100 dark:hover:bg-white/10'"
                    @click="form.category_id = category.id">
                    <DynamicIcon :icon="getCategoryEmoji(category.name, category.icon)" :size="18" />
                    <span>{{ category.name }} · {{ index + 1 }}</span>
                    <span v-if="form.category_id === category.id" class="ml-auto">已选</span>
                  </button>
                </div>
              </div>
            </details>
          </div>
          
          <!-- Account Selection -->
          <div class="space-y-4">
            <div>
              <label for="transaction-account" class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
                {{ form.type === 'transfer' ? '转出账户' : '账户' }}
              </label>
              <div class="relative">
                <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
                  <CreditCard :size="18" />
                </div>
                <select
                  id="transaction-account"
                  v-model="form.account_id"
                  class="w-full h-12 pl-11 pr-10 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden appearance-none focus:ring-2 focus:ring-primary/20 font-medium text-gray-700 dark:text-white"
                >
                  <option value="" disabled>请选择账户</option>
                  <option v-for="acc in accounts" :key="acc.id" :value="acc.id">
                    {{ acc.name }}
                  </option>
                </select>
                <ChevronDown class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" :size="18" />
              </div>
            </div>

            <!-- Transfer To Account -->
            <div v-if="form.type === 'transfer'" class="animate-in slide-in-from-top-2">
              <label for="transaction-to-account" class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">转入账户</label>
              <div class="relative">
                <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
                  <CreditCard :size="18" />
                </div>
                <select
                  id="transaction-to-account"
                  v-model="form.to_account_id"
                  class="w-full h-12 pl-11 pr-10 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden appearance-none focus:ring-2 focus:ring-primary/20 font-medium text-gray-700 dark:text-white"
                >
                  <option value="" disabled>请选择账户</option>
                  <option
                    v-for="acc in accounts"
                    :key="acc.id"
                    :value="acc.id"
                    :disabled="acc.id === form.account_id"
                  >
                    {{ acc.name }}
                  </option>
                </select>
                <ChevronDown class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" :size="18" />
              </div>
            </div>
          </div>

          <!-- Family Member -->
          <div v-if="familyMembers.length > 0 || form.member_id || form.paid_by_member_id">
            <label for="transaction-member" class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">归属成员</label>
            <div class="relative">
              <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
                <Users :size="18" />
              </div>
              <select
                id="transaction-member"
                v-model="form.member_id"
                class="w-full h-12 pl-11 pr-10 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden appearance-none focus:ring-2 focus:ring-primary/20 font-medium text-gray-700 dark:text-white"
              >
                <option value="">不指定成员</option>
                <option v-if="form.member_id && !familyMembers.some(member => member.id === form.member_id)" :value="form.member_id">原归属成员（已停用或不可用）</option>
                <option v-for="member in familyMembers" :key="member.id" :value="member.id">
                  {{ member.name }}{{ member.relationship ? ` · ${member.relationship}` : '' }}
                </option>
              </select>
              <ChevronDown class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" :size="18" />
            </div>
          </div>

          <div v-if="familyMembers.length > 0 || form.member_id || form.paid_by_member_id">
            <label for="transaction-payer" class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">付款成员</label>
            <select
              id="transaction-payer"
              v-model="form.paid_by_member_id"
              class="w-full h-12 px-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 font-medium text-gray-700 dark:text-white"
            >
              <option value="">不指定付款成员</option>
              <option v-if="form.paid_by_member_id && !familyMembers.some(member => member.id === form.paid_by_member_id)" :value="form.paid_by_member_id">原付款成员（已停用或不可用）</option>
              <option v-for="member in familyMembers" :key="member.id" :value="member.id">{{ member.name }}</option>
            </select>
          </div>

          <!-- Tags -->
          <div v-if="tags.length > 0">
            <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
              <TagIcon :size="14" class="inline mr-1" />标签
            </label>
            <div class="flex flex-wrap gap-2">
              <button
                v-for="tag in tags"
                :key="tag.id"
                type="button"
                :aria-pressed="form.tag_names.includes(tag.name)"
                class="min-h-11 px-3 py-1.5 rounded-full text-xs font-medium border transition-all"
                :class="form.tag_names.includes(tag.name)
                  ? 'border-primary bg-primary/10 text-primary'
                  : 'border-gray-200/70 dark:border-white/10 bg-gray-50/70 dark:bg-white/5 text-gray-500 dark:text-gray-400 hover:border-primary/40'"
                @click="toggleTag(tag.name)"
              >
                {{ tag.name }}
              </button>
            </div>
          </div>
          
          <!-- Date & Remark -->
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label for="transaction-date" class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">日期</label>
              <div class="relative">
                <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
                  <Calendar :size="18" />
                </div>
                <input
                  id="transaction-date"
                  v-model="form.transaction_date"
                  type="datetime-local"
                  class="w-full h-12 pl-11 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 font-medium text-gray-700 dark:text-white"
                />
              </div>
            </div>
            
            <div>
              <label for="transaction-remark" class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">备注</label>
              <div class="relative">
                <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
                  <FileText :size="18" />
                </div>
                <input
                  id="transaction-remark"
                  v-model="form.remark"
                  type="text"
                  placeholder="选填"
                  class="w-full h-12 pl-11 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 font-medium text-gray-700 dark:text-white"
                />
              </div>
            </div>
          </div>

          <!-- Attachments -->
          <div v-if="!loadingInitialData && !transactionLoadFailed && savedTransactionId">
            <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
              <Paperclip :size="14" class="inline mr-1" />附件
            </label>
            <FileUpload
              :key="dialogGeneration"
              :disabled="loading"
              @uploading-change="attachmentsUploading = $event"
              v-model="form.images"
              category="transactions"
              :ref-id="savedTransactionId || props.editId || ''"
              :max-files="5"
            />
          </div>
          <div v-else class="text-xs text-gray-400 italic">
            保存后可添加附件
          </div>
        </fieldset>
        </div>
        
    </form>
    <template #footer>
          <button
            type="submit" form="transaction-form"
            class="w-full h-12 rounded-xl font-bold text-lg transition-all shadow-lg shadow-primary/20 active:scale-[0.98]"
            :class="isValid ? 'bg-primary text-white hover:bg-primary/90' : 'bg-gray-100/50 dark:bg-gray-700/50 text-gray-400 cursor-not-allowed shadow-none'"
            :disabled="!isValid || loading || attachmentsUploading"
          >
            {{ attachmentsUploading ? '附件上传中…' : loading ? '保存中...' : pendingCreate ? '确认上次记账结果' : '保存记录' }}
          </button>
    </template>
  </AppDialog>
</template>
