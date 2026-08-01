<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import dayjs from 'dayjs'
import { Bolt, ChevronLeft, Clock3, Plus, Trash2, X } from 'lucide-vue-next'

import { accountApi, type Account } from '@/api/account'
import { categoryApi, type Category } from '@/api/category'
import { templateApi, type QuickTemplate } from '@/api/template'
import { toast } from '@/composables/useToast'
import { toLedgerInstant } from '@/utils/ledgerDate'

const router = useRouter()
const templates = ref<QuickTemplate[]>([])
const accounts = ref<Account[]>([])
const categories = ref<Category[]>([])
const loading = ref(true)
const loadError = ref(false)
const submitting = ref(false)
const showCreate = ref(false)
const applyingTemplate = ref<QuickTemplate | null>(null)
const deletingTemplate = ref<QuickTemplate | null>(null)

const form = ref({
  name: '',
  type: 'expense' as 'expense' | 'income',
  amount: '',
  account_id: '',
  category_id: '',
  remark: '',
})
const applyForm = ref({ amount: '', transaction_date: dayjs().format('YYYY-MM-DDTHH:mm') })

const activeAccounts = computed(() => accounts.value.filter((account) => !account.is_archived))
const filteredCategories = computed(() => categories.value.filter((category) => category.type === form.value.type))
const canCreate = computed(() => activeAccounts.value.length > 0 && categories.value.length > 0)

onMounted(loadData)

async function loadData() {
  loading.value = true
  loadError.value = false
  try {
    const [templateList, accountList, categoryList] = await Promise.all([
      templateApi.list(),
      accountApi.getList(false),
      categoryApi.getList(),
    ])
    templates.value = templateList
    accounts.value = accountList.list || []
    categories.value = categoryList
  } catch {
    loadError.value = true
  } finally {
    loading.value = false
  }
}

function accountName(id: string) {
  return accounts.value.find((account) => account.id === id)?.name || '账户不可用'
}

function categoryName(id: string | null) {
  if (!id) return '未分类'
  return categories.value.find((category) => category.id === id)?.name || '分类不可用'
}

function openCreateForm() {
  if (!canCreate.value) {
    toast.warning('请先补充可用账户和分类')
    return
  }
  form.value = {
    name: '',
    type: 'expense',
    amount: '',
    account_id: activeAccounts.value[0]?.id || '',
    category_id: categories.value.find((category) => category.type === 'expense')?.id || '',
    remark: '',
  }
  showCreate.value = true
}

function changeType(type: 'expense' | 'income') {
  form.value.type = type
  form.value.category_id = categories.value.find((category) => category.type === type)?.id || ''
}

async function createTemplate() {
  const amount = Number(form.value.amount || 0)
  if (!form.value.name.trim()) {
    toast.warning('请输入模板名称')
    return
  }
  if (!Number.isFinite(amount) || amount < 0) {
    toast.warning('请输入有效金额')
    return
  }
  if (!form.value.account_id || !form.value.category_id) {
    toast.warning('请选择账户和分类')
    return
  }
  submitting.value = true
  try {
    await templateApi.create({
      name: form.value.name.trim(),
      type: form.value.type,
      amount,
      account_id: form.value.account_id,
      category_id: form.value.category_id,
      remark: form.value.remark.trim(),
    })
    showCreate.value = false
    toast.success('模板已保存')
    await loadData()
  } catch (error: any) {
    toast.error(error.message || '模板保存失败')
  } finally {
    submitting.value = false
  }
}

function openApply(template: QuickTemplate) {
  applyingTemplate.value = template
  applyForm.value = {
    amount: template.amount > 0 ? String(template.amount) : '',
    transaction_date: dayjs().format('YYYY-MM-DDTHH:mm'),
  }
}

async function applyTemplate() {
  const template = applyingTemplate.value
  const amount = Number(applyForm.value.amount)
  if (!template || !Number.isFinite(amount) || amount <= 0) {
    toast.warning('请输入大于 0 的金额')
    return
  }
  const transactionDate = dayjs(applyForm.value.transaction_date)
  if (!transactionDate.isValid()) {
    toast.warning('请选择有效日期')
    return
  }
  submitting.value = true
  try {
    await templateApi.apply(template.id, {
      amount,
      transaction_date: toLedgerInstant(applyForm.value.transaction_date),
    })
    applyingTemplate.value = null
    toast.success('已按模板记账')
    await loadData()
  } catch (error: any) {
    toast.error(error.message || '模板使用失败')
  } finally {
    submitting.value = false
  }
}

async function deleteTemplate() {
  const template = deletingTemplate.value
  if (!template || submitting.value) return
  submitting.value = true
  try {
    await templateApi.delete(template.id)
    deletingTemplate.value = null
    toast.success('模板已删除')
    await loadData()
  } catch (error: any) {
    toast.error(error.message || '模板删除失败')
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black pb-8">
    <header class="sticky top-0 z-30 border-b border-gray-200/50 bg-white/75 px-4 py-4 backdrop-blur-xl dark:border-white/10 dark:bg-[#1C1C1E]/75 md:px-8">
      <div class="mx-auto flex max-w-3xl items-center justify-between">
        <div class="flex items-center gap-3">
          <button class="-ml-2 rounded-xl p-2 text-gray-500 transition hover:bg-black/5 dark:hover:bg-white/10" @click="router.back()"><ChevronLeft :size="20" /></button>
          <div class="flex h-12 w-12 items-center justify-center rounded-2xl bg-orange-100 text-orange-500 dark:bg-orange-900/25"><Bolt :size="24" /></div>
          <div>
            <h1 class="text-xl font-bold text-gray-900 dark:text-white">快捷模板</h1>
            <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">{{ templates.length }} 个模板 · 一次确认后记账</p>
          </div>
        </div>
        <button class="flex h-10 w-10 items-center justify-center rounded-full bg-primary text-white shadow-lg shadow-primary/20 transition active:scale-95 disabled:opacity-40" :disabled="!canCreate" @click="openCreateForm"><Plus :size="20" /></button>
      </div>
    </header>

    <main class="mx-auto max-w-3xl space-y-3 px-4 py-6 md:px-8">
      <div v-if="!loading && !canCreate" class="rounded-2xl border border-orange-200/60 bg-orange-50/80 p-4 text-sm text-orange-700 dark:border-orange-900/40 dark:bg-orange-900/20 dark:text-orange-300">
        创建模板需要至少一个可用账户和对应的收支分类。
      </div>
      <div v-if="loading" class="py-20 text-center text-sm text-gray-400">正在加载模板...</div>
      <div v-else-if="loadError" class="rounded-3xl border border-white/50 bg-white/75 p-8 text-center shadow-sm dark:border-white/5 dark:bg-[#1C1C1E]/75">
        <p class="text-gray-600 dark:text-gray-300">模板加载失败</p>
        <button class="mt-4 rounded-xl bg-primary px-5 py-2.5 text-sm font-medium text-white" @click="loadData">重新加载</button>
      </div>
      <div v-else-if="templates.length === 0" class="rounded-3xl border border-white/50 bg-white/75 p-10 text-center shadow-sm dark:border-white/5 dark:bg-[#1C1C1E]/75">
        <div class="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-orange-100 text-orange-500 dark:bg-orange-900/25"><Bolt :size="28" /></div>
        <h2 class="font-semibold text-gray-900 dark:text-white">还没有快捷模板</h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">把常用收支保存下来，使用时仍可修改金额和日期。</p>
        <button class="mt-5 rounded-xl bg-primary px-5 py-2.5 text-sm font-medium text-white disabled:opacity-40" :disabled="!canCreate" @click="openCreateForm">创建模板</button>
      </div>
      <template v-else>
        <article
          v-for="template in templates"
          :key="template.id"
          class="rounded-2xl border border-white/50 bg-white/75 p-4 shadow-sm backdrop-blur-xl dark:border-white/5 dark:bg-[#1C1C1E]/75"
        >
        <div class="flex items-start gap-4">
          <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl" :class="template.type === 'expense' ? 'bg-red-50 text-red-500 dark:bg-red-900/20' : 'bg-green-50 text-green-500 dark:bg-green-900/20'"><Bolt :size="21" /></div>
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2">
              <h2 class="font-semibold text-gray-900 dark:text-white">{{ template.name }}</h2>
              <span class="rounded-full px-2 py-0.5 text-[10px]" :class="template.type === 'expense' ? 'bg-red-50 text-red-500 dark:bg-red-900/20' : 'bg-green-50 text-green-600 dark:bg-green-900/20'">{{ template.type === 'expense' ? '支出' : '收入' }}</span>
            </div>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">{{ accountName(template.account_id) }} · {{ categoryName(template.category_id) }}</p>
            <p v-if="template.remark" class="mt-1 truncate text-xs text-gray-400">{{ template.remark }}</p>
          </div>
          <div class="text-right">
            <div class="font-mono text-lg font-bold text-gray-900 dark:text-white">{{ template.amount > 0 ? `¥${template.amount.toFixed(2)}` : '可变金额' }}</div>
            <div class="mt-1 text-[10px] text-gray-400">使用 {{ template.used_count }} 次</div>
          </div>
        </div>
        <div class="mt-4 grid grid-cols-[1fr_auto] gap-2 border-t border-gray-100/60 pt-3 dark:border-white/5">
          <button class="h-10 rounded-xl bg-primary/10 text-sm font-semibold text-primary transition hover:bg-primary/15 disabled:opacity-50" :disabled="submitting" @click="openApply(template)">使用模板</button>
          <button class="flex h-10 w-10 items-center justify-center rounded-xl text-gray-400 transition hover:bg-red-50 hover:text-red-500 dark:hover:bg-red-900/20" :disabled="submitting" @click="deletingTemplate = template"><Trash2 :size="17" /></button>
        </div>
        </article>
      </template>
    </main>

    <Teleport to="body">
      <div v-if="showCreate" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showCreate = false"></div>
        <div class="relative max-h-[90vh] w-full max-w-md overflow-y-auto rounded-3xl border border-white/30 bg-white/95 p-6 shadow-2xl dark:border-white/10 dark:bg-[#1C1C1E]/95">
          <div class="mb-5 flex items-center justify-between"><h2 class="text-lg font-bold text-gray-900 dark:text-white">创建快捷模板</h2><button class="rounded-full p-2 text-gray-400 hover:bg-black/5 dark:hover:bg-white/10" @click="showCreate = false"><X :size="19" /></button></div>
          <div class="space-y-4">
            <div class="grid grid-cols-2 gap-1 rounded-xl bg-gray-100 p-1 dark:bg-white/10">
              <button class="rounded-lg py-2 text-sm font-medium transition" :class="form.type === 'expense' ? 'bg-white text-gray-900 shadow-sm dark:bg-white/15 dark:text-white' : 'text-gray-500'" @click="changeType('expense')">支出</button>
              <button class="rounded-lg py-2 text-sm font-medium transition" :class="form.type === 'income' ? 'bg-white text-gray-900 shadow-sm dark:bg-white/15 dark:text-white' : 'text-gray-500'" @click="changeType('income')">收入</button>
            </div>
            <label class="block"><span class="mb-1.5 block text-xs font-bold uppercase tracking-wider text-gray-400">模板名称</span><input v-model="form.name" maxlength="100" class="h-12 w-full rounded-xl border-0 bg-gray-100 px-4 outline-none focus:ring-2 focus:ring-primary/30 dark:bg-white/10 dark:text-white" placeholder="例如：工作日午餐" /></label>
            <label class="block"><span class="mb-1.5 block text-xs font-bold uppercase tracking-wider text-gray-400">默认金额</span><input v-model="form.amount" type="number" min="0" step="0.01" class="h-12 w-full rounded-xl border-0 bg-gray-100 px-4 outline-none focus:ring-2 focus:ring-primary/30 dark:bg-white/10 dark:text-white" placeholder="0 表示使用时填写" /></label>
            <label class="block"><span class="mb-1.5 block text-xs font-bold uppercase tracking-wider text-gray-400">账户</span><select v-model="form.account_id" class="h-12 w-full rounded-xl border-0 bg-gray-100 px-4 outline-none focus:ring-2 focus:ring-primary/30 dark:bg-white/10 dark:text-white"><option v-for="account in activeAccounts" :key="account.id" :value="account.id">{{ account.name }}</option></select></label>
            <label class="block"><span class="mb-1.5 block text-xs font-bold uppercase tracking-wider text-gray-400">分类</span><select v-model="form.category_id" class="h-12 w-full rounded-xl border-0 bg-gray-100 px-4 outline-none focus:ring-2 focus:ring-primary/30 dark:bg-white/10 dark:text-white"><option v-for="category in filteredCategories" :key="category.id" :value="category.id">{{ category.name }}</option></select></label>
            <label class="block"><span class="mb-1.5 block text-xs font-bold uppercase tracking-wider text-gray-400">备注</span><input v-model="form.remark" class="h-12 w-full rounded-xl border-0 bg-gray-100 px-4 outline-none focus:ring-2 focus:ring-primary/30 dark:bg-white/10 dark:text-white" placeholder="选填" /></label>
            <button class="h-12 w-full rounded-xl bg-primary font-semibold text-white disabled:opacity-50" :disabled="submitting" @click="createTemplate">{{ submitting ? '保存中...' : '保存模板' }}</button>
          </div>
        </div>
      </div>

      <div v-if="applyingTemplate" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="applyingTemplate = null"></div>
        <div class="relative w-full max-w-sm rounded-3xl bg-white/95 p-6 shadow-2xl dark:bg-[#1C1C1E]/95">
          <div class="mb-1 flex items-center justify-between"><h2 class="text-lg font-bold text-gray-900 dark:text-white">使用「{{ applyingTemplate.name }}」</h2><button class="rounded-full p-2 text-gray-400 hover:bg-black/5 dark:hover:bg-white/10" @click="applyingTemplate = null"><X :size="19" /></button></div>
          <p class="mb-5 text-sm text-gray-500 dark:text-gray-400">确认金额和日期后才会写入账本。</p>
          <div class="space-y-4">
            <label class="block"><span class="mb-1.5 block text-xs font-bold uppercase tracking-wider text-gray-400">金额</span><input v-model="applyForm.amount" type="number" min="0.01" step="0.01" class="h-12 w-full rounded-xl border-0 bg-gray-100 px-4 outline-none focus:ring-2 focus:ring-primary/30 dark:bg-white/10 dark:text-white" /></label>
            <label class="block"><span class="mb-1.5 flex items-center gap-1 text-xs font-bold uppercase tracking-wider text-gray-400"><Clock3 :size="13" />日期时间</span><input v-model="applyForm.transaction_date" type="datetime-local" class="h-12 w-full rounded-xl border-0 bg-gray-100 px-4 outline-none focus:ring-2 focus:ring-primary/30 dark:bg-white/10 dark:text-white" /></label>
            <button class="h-12 w-full rounded-xl bg-primary font-semibold text-white disabled:opacity-50" :disabled="submitting" @click="applyTemplate">{{ submitting ? '记账中...' : '确认记账' }}</button>
          </div>
        </div>
      </div>

      <div v-if="deletingTemplate" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="deletingTemplate = null"></div>
        <div class="relative w-full max-w-xs rounded-3xl bg-white/95 p-6 text-center shadow-2xl dark:bg-[#1C1C1E]/95">
          <div class="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-red-100 text-red-500 dark:bg-red-900/30"><Trash2 :size="22" /></div>
          <h2 class="font-bold text-gray-900 dark:text-white">删除「{{ deletingTemplate.name }}」？</h2>
          <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">已按模板创建的交易不会受影响。</p>
          <div class="mt-6 grid grid-cols-2 gap-3"><button class="h-11 rounded-xl bg-gray-100 text-gray-700 dark:bg-white/10 dark:text-gray-200" @click="deletingTemplate = null">取消</button><button class="h-11 rounded-xl bg-red-500 font-medium text-white disabled:opacity-50" :disabled="submitting" @click="deleteTemplate">删除</button></div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
