<script setup lang="ts">
import FinancePage from '@/components/ui/FinancePage.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import { ref, onMounted, onBeforeUnmount, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { Plus, Trash2, Edit2, Target, AlertCircle, ChevronDown, Users } from '@lucide/vue'
import { budgetApi, type Budget } from '@/api/budget'
import { categoryApi, type Category } from '@/api/category'
import { familyApi, type FamilyMember } from '@/api/family'
import { toast } from '@/composables/useToast'
import DynamicIcon from '@/components/DynamicIcon.vue'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { createRequestGeneration } from '@/utils/requestGeneration'
import { createFormSubmission } from '@/utils/formSubmission'

const router = useRouter()

const loading = ref(false)
const loadFailed = ref(false)
const totalBudget = ref<Budget | null>(null)
const categoryBudgets = ref<Budget[]>([])
const memberBudgets = ref<Budget[]>([])
const categories = ref<Category[]>([])
const familyMembers = ref<FamilyMember[]>([])
const membersLoadFailed = ref(false)
const ledgerMutationRevision = useLedgerMutationRevision()
const dataRequests = createRequestGeneration()

// Dialog state
const showDialog = ref(false)
const editingBudget = ref<Budget | null>(null)
const budgetMode = ref<'total' | 'category' | 'member'>('category')
const formSubmission = createFormSubmission()
const saving = formSubmission.saving
const dialogTrigger = ref<HTMLElement | null>(null)
const deleteTrigger = ref<HTMLElement | null>(null)
const pageHeading = ref<HTMLElement | null>(null)
const deleting = ref(false)
const form = ref({
  amount: '',
  categoryId: '',
  memberId: ''
})

// Delete confirm
const showDeleteModal = ref(false)
const deletingId = ref<string | undefined>(undefined)

const availableCategories = computed(() => {
  const usedIds = new Set(categoryBudgets.value.map(b => b.category_id))
  if (editingBudget.value?.category_id) {
    usedIds.delete(editingBudget.value.category_id)
  }
  return categories.value.filter(c => c.type === 'expense' && !usedIds.has(c.id))
})
const enabledFamilyMembers = computed(() => familyMembers.value.filter(member => member.is_enabled))
const expenseCategories = computed(() => categories.value.filter(c => c.type === 'expense'))

// Computed for potential future use
const _totalSpent = computed(() => {
  return categoryBudgets.value.reduce((sum, b) => sum + (b.spent || 0), 0)
})
void _totalSpent // prevent unused warning

onMounted(() => {
  loadData()
})

watch(ledgerMutationRevision, () => void loadData())
onBeforeUnmount(() => { dataRequests.begin(); formSubmission.reset() })

async function loadData() {
  const requestGeneration = dataRequests.begin()
  loading.value = true
  loadFailed.value = false
  try {
    const [bData, cData, members] = await Promise.all([
      budgetApi.getList(),
      categoryApi.getList('expense'),
      familyApi.listMembers().then(members => ({ members, failed: false }))
        .catch(() => ({ members: [] as FamilyMember[], failed: true }))
    ])
    if (!dataRequests.isLatest(requestGeneration)) return
    totalBudget.value = bData.total_budget
    categoryBudgets.value = bData.category_budgets || []
    memberBudgets.value = bData.member_budgets || []
    categories.value = cData
    membersLoadFailed.value = members.failed
    if (!members.failed) familyMembers.value = members.members
  } catch (e: any) {
    if (dataRequests.isLatest(requestGeneration)) {
      loadFailed.value = true
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

function openTotalForm(event?: Event) {
  formSubmission.reset()
  if (event?.currentTarget instanceof HTMLElement) dialogTrigger.value = event.currentTarget
  budgetMode.value = 'total'
  editingBudget.value = null
  form.value = {
    amount: totalBudget.value?.amount.toString() || '',
    categoryId: '',
    memberId: ''
  }
  showDialog.value = true
}

function openCategoryForm(budget?: Budget, event?: Event) {
  formSubmission.reset()
  if (event?.currentTarget instanceof HTMLElement) dialogTrigger.value = event.currentTarget
  budgetMode.value = 'category'
  editingBudget.value = budget || null
  form.value = {
    amount: budget?.amount.toString() || '',
    categoryId: budget?.category_id || (availableCategories.value[0]?.id || ''),
    memberId: ''
  }
  showDialog.value = true
}

function openMemberForm(budget?: Budget, event?: Event) {
  formSubmission.reset()
  if (event?.currentTarget instanceof HTMLElement) dialogTrigger.value = event.currentTarget
  budgetMode.value = 'member'
  editingBudget.value = budget || null
  form.value = {
    amount: budget?.amount.toString() || '',
    categoryId: budget?.category_id || '',
    memberId: budget?.member_id || (enabledFamilyMembers.value[0]?.id || '')
  }
  showDialog.value = true
}

function closeDialog() {
  formSubmission.reset()
  showDialog.value = false
  editingBudget.value = null
  budgetMode.value = 'category'
}

async function submitForm() {
  if (saving.value) return
  const amount = parseFloat(form.value.amount)
  if (!Number.isFinite(amount) || amount <= 0) {
    toast.warning('请输入有效的金额')
    return
  }

  if (budgetMode.value === 'member' && !form.value.memberId) {
    toast.warning('请选择家庭成员')
    return
  }
  if (budgetMode.value === 'category' && !form.value.categoryId) {
    toast.warning('请选择分类')
    return
  }
  const submission = formSubmission.begin()
  if (!submission) return
  try {
    if (budgetMode.value === 'total') {
      await budgetApi.setTotal(amount)
      if (!submission.isCurrent()) return
      toast.success('总预算已保存')
    } else if (budgetMode.value === 'member') {
      if (form.value.categoryId) {
        await budgetApi.setCategory(form.value.categoryId, amount, undefined, form.value.memberId)
      } else {
        await budgetApi.setTotal(amount, undefined, form.value.memberId)
      }
      if (!submission.isCurrent()) return
      toast.success('成员预算已保存')
    } else {
      await budgetApi.setCategory(form.value.categoryId, amount)
      if (!submission.isCurrent()) return
      toast.success('分类预算已保存')
    }
    closeDialog()
    void loadData()
  } catch (e: any) {
    if (submission.isCurrent()) toast.error(e.message || '保存失败')
  } finally {
    submission.finish()
  }
}

function confirmDelete(id: string, event?: Event) {
  if (event?.currentTarget instanceof HTMLElement) deleteTrigger.value = event.currentTarget
  deletingId.value = id
  deleting.value = false
  showDeleteModal.value = true
}

async function handleDelete() {
  if (!deletingId.value) return
  if (deleting.value || saving.value) return
  const targetId = deletingId.value
  deleting.value = true
  try {
    await budgetApi.delete(targetId)
    if (deletingId.value !== targetId) return
    showDeleteModal.value = false
    deletingId.value = undefined
    toast.success('删除成功')
    void loadData()
  } catch (e: any) {
    if (deletingId.value === targetId) toast.error(e.message || '删除失败')
  } finally {
    deleting.value = false
  }
}

function formatMoney(val: number) {
  return val.toLocaleString('zh-CN', { minimumFractionDigits: 0, maximumFractionDigits: 0 })
}

function getPercentColor(percent: number) {
  if (percent >= 100) return 'bg-red-500'
  if (percent >= 80) return 'bg-yellow-500'
  return 'bg-primary'
}

function getPercentTextColor(percent: number) {
  if (percent >= 100) return 'text-red-500'
  if (percent >= 80) return 'text-yellow-500'
  return 'text-primary'
}

function getCategoryIcon(catId: string | null | undefined) {
  if (!catId) return '📦'
  const cat = categories.value.find(c => c.id === catId)
  return cat?.icon || '📦'
}

function getDialogTitle() {
  if (budgetMode.value === 'total') return '设置总预算'
  if (budgetMode.value === 'member') return editingBudget.value ? '编辑成员预算' : '添加成员预算'
  return editingBudget.value ? '编辑分类预算' : '添加分类预算'
}
</script>

<template>
  <FinancePage title="预算管理" :context="`${categoryBudgets.length} 个分类预算 · ${memberBudgets.length} 个成员预算`" :icon="Target" tone="green" back-label="返回" @back="goBack">
    <template #actions><button ref="pageHeading" type="button" aria-label="添加分类预算" class="finance-icon-button" :disabled="availableCategories.length === 0" @click="openCategoryForm(undefined, $event)"><Plus :size="20" /></button></template>

    <div class="space-y-5">
      <!-- Total Budget Card -->
      <div class="finance-card finance-card-padding">
        <div class="flex justify-between items-start mb-5">
          <div class="flex items-center gap-3">
            <div class="w-11 h-11 rounded-xl bg-gray-100 dark:bg-gray-700 flex items-center justify-center text-gray-600 dark:text-gray-300">
              <Target :size="20" />
            </div>
            <div>
              <div class="font-semibold text-gray-900 dark:text-white">月度总预算</div>
              <div class="finance-muted mt-1">控制每月总支出</div>
            </div>
          </div>
          <button 
            class="finance-button is-subtle budget-edit-button"
            @click="openTotalForm($event)"
          >
            {{ totalBudget ? '修改' : '设置' }}
          </button>
        </div>

        <div v-if="totalBudget">
          <div class="flex justify-between items-end mb-4">
            <div>
              <div class="finance-muted mb-1">预算金额</div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white font-nums">
                <span class="text-base font-normal text-gray-400 mr-0.5">¥</span>{{ formatMoney(totalBudget.amount) }}
              </div>
            </div>
            <div class="text-right">
              <div class="finance-muted mb-1">已使用</div>
              <div class="text-xl font-bold font-nums" :class="getPercentTextColor(totalBudget.percentage || 0)">{{ (totalBudget.percentage || 0).toFixed(0) }}%</div>
            </div>
          </div>
          
          <div class="h-1.5 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden mb-3">
            <div 
              class="h-full rounded-full transition-all duration-700 ease-out"
              :class="getPercentColor(totalBudget.percentage || 0)"
              :style="{ width: `${Math.min(totalBudget.percentage || 0, 100)}%` }"
            ></div>
          </div>

          <div class="flex justify-between finance-muted">
            <span>已用 ¥{{ formatMoney(totalBudget.spent || 0) }}</span>
            <span>剩余 ¥{{ formatMoney(Math.max(totalBudget.amount - (totalBudget.spent || 0), 0)) }}</span>
          </div>

          <div v-if="(totalBudget.percentage || 0) >= 80" class="mt-4 flex items-center gap-2 px-3 py-2 rounded-lg text-xs" :class="(totalBudget.percentage || 0) >= 100 ? 'text-red-600 bg-red-50 dark:bg-red-900/20 dark:text-red-400' : 'text-amber-600 bg-amber-50 dark:bg-amber-900/20 dark:text-amber-400'">
            <AlertCircle :size="14" />
            <span>{{ (totalBudget.percentage || 0) >= 100 ? '已超出预算' : '接近预算上限' }}</span>
          </div>
        </div>

        <div v-else class="text-center py-4 text-gray-400">
          <p class="text-sm mb-3">暂未设置月度总预算</p>
          <button 
            class="finance-button is-subtle"
            @click="openTotalForm($event)"
          >
            立即设置
          </button>
        </div>
      </div>

      <!-- Member Budgets -->
      <div>
        <div class="budget-section-head is-member">
          <div>
            <h2 class="budget-section-title">家庭成员预算</h2>
            <p v-if="memberBudgets.length" class="finance-muted mt-1">按成员控制家庭支出额度，可选绑定到具体分类</p>
          </div>
          <button
            v-if="memberBudgets.length && enabledFamilyMembers.length && !membersLoadFailed && !loadFailed && !loading"
            class="finance-button budget-add-member"
            :disabled="enabledFamilyMembers.length === 0"
            @click="openMemberForm(undefined, $event)"
          >
            添加成员预算
          </button>
        </div>

        <p v-if="loading" role="status" class="finance-muted py-3">正在加载成员预算…</p>
        <div v-else-if="loadFailed" role="alert" class="budget-member-empty">
          <AlertCircle :size="22" aria-hidden="true" />
          <div><h3>预算加载失败</h3><p>暂时无法确认预算和成员状态，请重新加载。</p></div>
          <button type="button" class="finance-button is-subtle" @click="loadData">重新加载预算</button>
        </div>
        <div v-else-if="membersLoadFailed" role="alert" class="budget-member-empty">
          <AlertCircle :size="22" aria-hidden="true" />
          <div><h3>成员加载失败</h3><p>暂时无法确认成员状态，请重新加载。</p></div>
          <button type="button" class="finance-button is-subtle" @click="loadData">重新加载成员</button>
        </div>
        <div v-else-if="memberBudgets.length === 0" class="budget-member-empty">
          <Users :size="22" aria-hidden="true" />
          <div>
            <h3>{{ enabledFamilyMembers.length ? '还没有成员预算' : familyMembers.length ? '暂无启用成员' : '暂无家庭成员' }}</h3>
            <p>{{ enabledFamilyMembers.length ? '为成员设置月度额度，也可以按分类细分。' : familyMembers.length ? '启用成员后，即可设置成员预算。' : '添加家庭成员后，即可为每位成员设置预算。' }}</p>
          </div>
          <button v-if="enabledFamilyMembers.length" type="button" class="finance-button is-primary" @click="openMemberForm(undefined, $event)">添加成员预算</button>
          <RouterLink v-else to="/family" class="finance-button is-subtle">{{ familyMembers.length ? '管理家庭成员' : '创建家庭成员' }}</RouterLink>
        </div>
        <div v-else class="budget-member-list">
          <div
            v-for="budget in memberBudgets"
            :key="budget.id"
            class="finance-card budget-row group"
          >
            <div class="flex justify-between items-start mb-3 gap-3">
              <div>
                <div class="budget-row-title">{{ budget.member_name || '家庭成员' }}</div>
                <div class="finance-muted">{{ budget.category_name || '总预算' }} · 预算 ¥{{ formatMoney(budget.amount) }}</div>
              </div>
              <div class="budget-row-actions">
                <button
                  :aria-label="`编辑${budget.member_name || '家庭成员'}的${budget.category_name || '总预算'}`"
                  class="budget-row-action"
                  @click="openMemberForm(budget, $event)"
                >
                  <Edit2 :size="14" />
                </button>
                <button
                  :aria-label="`删除${budget.member_name || '家庭成员'}的${budget.category_name || '总预算'}`"
                  class="budget-row-action is-danger"
                  @click="confirmDelete(budget.id, $event)"
                >
                  <Trash2 :size="14" />
                </button>
              </div>
            </div>
            <div class="space-y-2">
              <div class="flex justify-between finance-muted">
                <span>已用 ¥{{ formatMoney(budget.spent || 0) }}</span>
                <span class="font-bold" :class="getPercentTextColor(budget.percentage || 0)">
                  {{ (budget.percentage || 0).toFixed(0) }}%
                </span>
              </div>
              <div class="h-1 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
                <div
                  class="h-full rounded-full transition-all duration-500"
                  :class="getPercentColor(budget.percentage || 0)"
                  :style="{ width: `${Math.min(budget.percentage || 0, 100)}%` }"
                ></div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Category Budgets -->
      <div>
        <div class="budget-section-head">
          <h2 class="budget-section-title">分类预算</h2>
          <span class="finance-muted">{{ categoryBudgets.length }} 个分类</span>
        </div>

        <div v-if="loading" class="py-12 text-center text-gray-400">加载中...</div>

        <div v-else-if="categoryBudgets.length === 0" class="budget-empty">
          <h3>暂无分类预算</h3>
          <button
            v-if="availableCategories.length > 0"
            class="finance-button is-primary"
            @click="openCategoryForm(undefined, $event)"
          >
            添加分类预算
          </button>
        </div>

        <div v-else class="budget-member-list">
          <div 
            v-for="budget in categoryBudgets" 
            :key="budget.id"
            class="finance-card budget-row group"
          >
            <div class="flex justify-between items-start mb-3 gap-3">
              <div class="flex items-center gap-3">
                <div 
                  class="w-10 h-10 rounded-xl flex items-center justify-center text-xl bg-gray-50 dark:bg-gray-700"
                >
                  <DynamicIcon :icon="getCategoryIcon(budget.category_id)" :size="20" />
                </div>
                <div>
                  <div class="budget-row-title">{{ budget.category_name }}</div>
                  <div class="finance-muted">预算 ¥{{ formatMoney(budget.amount) }}</div>
                </div>
              </div>
              <div class="budget-row-actions">
                <button 
                  :aria-label="`编辑${budget.category_name}预算`"
                  class="budget-row-action"
                  @click="openCategoryForm(budget, $event)"
                >
                  <Edit2 :size="14" />
                </button>
                <button 
                  :aria-label="`删除${budget.category_name}预算`"
                  class="budget-row-action is-danger"
                  @click="confirmDelete(budget.id, $event)"
                >
                  <Trash2 :size="14" />
                </button>
              </div>
            </div>

            <div class="space-y-2">
              <div class="flex justify-between finance-muted">
                <span>已用 ¥{{ formatMoney(budget.spent || 0) }}</span>
                <span 
                  class="font-bold"
                  :class="getPercentTextColor(budget.percentage || 0)"
                >
                  {{ (budget.percentage || 0).toFixed(0) }}%
                </span>
              </div>
              <div class="h-1 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
                <div 
                  class="h-full rounded-full transition-all duration-500"
                  :class="getPercentColor(budget.percentage || 0)"
                  :style="{ width: `${Math.min(budget.percentage || 0, 100)}%` }"
                ></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <AppDialog v-if="showDialog" :title="getDialogTitle()" :busy="saving" sheet :return-focus="dialogTrigger" :fallback-focus="pageHeading" @close="closeDialog">
      <form id="budget-form" class="budget-form" novalidate @submit.prevent="submitForm">
        <label v-if="budgetMode === 'member'" class="finance-field">
          <span>选择成员</span>
          <span class="budget-select-wrap">
            <select id="budget-member" v-model="form.memberId" name="member_id" class="finance-input budget-select" :disabled="saving || !!editingBudget" required>
              <option v-for="member in enabledFamilyMembers" :key="member.id" :value="member.id">{{ member.name }}</option>
            </select>
            <ChevronDown :size="18" aria-hidden="true" />
          </span>
        </label>
        <label v-if="budgetMode === 'category' || budgetMode === 'member'" class="finance-field">
          <span>选择分类</span>
          <span class="budget-select-wrap">
            <select v-model="form.categoryId" name="category_id" class="finance-input budget-select" :disabled="saving || !!editingBudget">
              <option v-if="budgetMode === 'member'" value="">总预算</option>
              <option v-for="cat in (budgetMode === 'member' ? expenseCategories : availableCategories)" :key="cat.id" :value="cat.id">{{ cat.name }}</option>
            </select>
            <ChevronDown :size="18" aria-hidden="true" />
          </span>
        </label>
        <label class="finance-field">
          <span>预算金额</span>
          <span class="budget-amount-wrap">
            <span aria-hidden="true">¥</span>
            <input v-model="form.amount" name="amount" :disabled="saving" type="number" step="0.01" inputmode="decimal" placeholder="0" class="finance-input budget-amount-input" required />
          </span>
        </label>
      </form>
      <template #footer>
        <button type="button" class="finance-button" :disabled="saving" @click="closeDialog">取消</button>
        <button type="submit" form="budget-form" class="finance-button is-primary" :disabled="saving">{{ saving ? '保存中…' : '保存' }}</button>
      </template>
    </AppDialog>

    <AppDialog v-if="showDeleteModal" title="删除预算" :busy="deleting" :return-focus="deleteTrigger" :fallback-focus="pageHeading" @close="showDeleteModal = false">
      <p class="finance-muted">删除后将不再监控这项预算，已记交易不受影响。</p>
      <template #footer>
        <button type="button" class="finance-button" :disabled="deleting" @click="showDeleteModal = false">取消</button>
        <button type="button" class="finance-button is-danger" :disabled="deleting" @click="handleDelete">{{ deleting ? '删除中…' : '删除预算' }}</button>
      </template>
    </AppDialog>
  </FinancePage>
</template>

<style scoped>
.budget-member-empty { display: flex; align-items: center; gap: 14px; padding: 18px; border: 1px solid var(--fp-line); border-radius: 18px; background: var(--fp-surface); }
.budget-member-empty > svg { flex: none; color: var(--fp-secondary); }
.budget-member-empty > div { flex: 1; min-width: 0; }
.budget-member-empty h3 { font-size: 14px; font-weight: 600; }
.budget-member-empty p { margin-top: 5px; color: var(--fp-secondary); font-size: 13px; line-height: 1.65; }
.budget-member-empty a { text-decoration: none; }
.budget-form { display: flex; flex-direction: column; gap: 17px; }
.budget-section-title { font-size: 15px; line-height: 1.45; font-weight: 600; letter-spacing: -.012em; }
.budget-row { padding: 16px; }
.budget-add-member { background: var(--fp-ink); color: var(--fp-solid); }
.budget-edit-button { min-height: 36px; padding-inline: 12px; }
.budget-select-wrap,.budget-amount-wrap { position: relative; display: flex; align-items: center; }
.budget-select-wrap svg { position: absolute; right: 13px; color: var(--fp-secondary); pointer-events: none; }
.budget-select { appearance: none; padding-right: 40px; font-size: 14px; font-weight: 500; }
.budget-amount-wrap > span { position: absolute; left: 14px; z-index: 1; color: var(--fp-secondary); font-size: 20px; font-weight: 550; pointer-events: none; }
.budget-amount-input { min-height: 58px; padding-left: 36px; font-size: 26px; font-weight: 600; font-variant-numeric: tabular-nums; }
.budget-section-head { display: flex; align-items: center; justify-content: space-between; gap: 14px; margin-bottom: 12px; }
.budget-section-head.is-member { flex-wrap: wrap; align-items: flex-start; }
.budget-member-list { display: flex; flex-direction: column; gap: 10px; }
.budget-row-actions { display: flex; flex: none; gap: 1px; }
.budget-row-action { display: grid; place-items: center; width: 44px; height: 44px; border-radius: 10px; color: var(--fp-secondary); transition: background-color 150ms ease, color 150ms ease; }
.budget-row-action:hover { background: var(--fp-soft); color: var(--fp-ink); }
.budget-row-action.is-danger:hover { background: rgb(220 76 80 / 9%); color: var(--fp-red); }
.budget-row-title { color: var(--fp-ink); font-size: 14px; line-height: 1.5; font-weight: 550; overflow-wrap: anywhere; }
.budget-empty { padding: 32px 18px; border: 1px solid var(--fp-line); border-radius: 18px; text-align: center; background: var(--fp-surface); }
.budget-empty h3 { color: var(--fp-ink); font-size: 15px; line-height: 1.5; font-weight: 600; margin-bottom: 14px; }
@media (max-width: 767px) {
  .budget-member-empty { flex-wrap: wrap; align-items: flex-start; }
  .budget-member-empty > div { flex-basis: calc(100% - 40px); }
  .budget-member-empty > :is(a,button) { margin-left: 36px; }
  .budget-row { padding: 15px 14px; }
  .budget-section-head.is-member .budget-add-member { width: 100%; }
}
</style>
