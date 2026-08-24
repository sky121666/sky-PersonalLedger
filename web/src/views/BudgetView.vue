<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronLeft, Plus, Trash2, Edit2, X, Target, AlertCircle, ChevronDown } from 'lucide-vue-next'
import { budgetApi, type Budget } from '@/api/budget'
import { categoryApi, type Category } from '@/api/category'
import { familyApi, type FamilyMember } from '@/api/family'
import { toast } from '@/composables/useToast'
import DynamicIcon from '@/components/DynamicIcon.vue'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { createRequestGeneration } from '@/utils/requestGeneration'

const router = useRouter()

const loading = ref(false)
const totalBudget = ref<Budget | null>(null)
const categoryBudgets = ref<Budget[]>([])
const memberBudgets = ref<Budget[]>([])
const categories = ref<Category[]>([])
const familyMembers = ref<FamilyMember[]>([])
const ledgerMutationRevision = useLedgerMutationRevision()
const dataRequests = createRequestGeneration()

// Dialog state
const showDialog = ref(false)
const editingBudget = ref<Budget | null>(null)
const budgetMode = ref<'total' | 'category' | 'member'>('category')
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

async function loadData() {
  const requestGeneration = dataRequests.begin()
  loading.value = true
  try {
    const [bData, cData, members] = await Promise.all([
      budgetApi.getList(),
      categoryApi.getList('expense'),
      familyApi.listMembers().catch(() => [] as FamilyMember[])
    ])
    if (!dataRequests.isLatest(requestGeneration)) return
    totalBudget.value = bData.total_budget
    categoryBudgets.value = bData.category_budgets || []
    memberBudgets.value = bData.member_budgets || []
    categories.value = cData
    familyMembers.value = members
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

function openTotalForm() {
  budgetMode.value = 'total'
  editingBudget.value = null
  form.value = {
    amount: totalBudget.value?.amount.toString() || '',
    categoryId: '',
    memberId: ''
  }
  showDialog.value = true
}

function openCategoryForm(budget?: Budget) {
  budgetMode.value = 'category'
  editingBudget.value = budget || null
  form.value = {
    amount: budget?.amount.toString() || '',
    categoryId: budget?.category_id || (availableCategories.value[0]?.id || ''),
    memberId: ''
  }
  showDialog.value = true
}

function openMemberForm(budget?: Budget) {
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
  showDialog.value = false
  editingBudget.value = null
  budgetMode.value = 'category'
}

async function submitForm() {
  const amount = parseFloat(form.value.amount)
  if (!amount || amount <= 0) {
    toast.warning('请输入有效的金额')
    return
  }

  try {
    if (budgetMode.value === 'total') {
      await budgetApi.setTotal(amount)
      toast.success('总预算已保存')
    } else if (budgetMode.value === 'member') {
      if (!form.value.memberId) {
        toast.warning('请选择家庭成员')
        return
      }
      if (form.value.categoryId) {
        await budgetApi.setCategory(form.value.categoryId, amount, undefined, form.value.memberId)
      } else {
        await budgetApi.setTotal(amount, undefined, form.value.memberId)
      }
      toast.success('成员预算已保存')
    } else {
      if (!form.value.categoryId) {
        toast.warning('请选择分类')
        return
      }
      await budgetApi.setCategory(form.value.categoryId, amount)
      toast.success('分类预算已保存')
    }
    closeDialog()
    loadData()
  } catch (e: any) {
    toast.error(e.message || '保存失败')
  }
}

function confirmDelete(id: string) {
  deletingId.value = id
  showDeleteModal.value = true
}

async function handleDelete() {
  if (!deletingId.value) return
  try {
    await budgetApi.delete(deletingId.value)
    showDeleteModal.value = false
    deletingId.value = undefined
    toast.success('删除成功')
    loadData()
  } catch (e: any) {
    toast.error(e.message || '删除失败')
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
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black pb-8">
    <!-- Header -->
    <div class="bg-white/70 dark:bg-[#1C1C1E]/70 pt-4 pb-4 px-4 md:px-8 sticky top-0 z-30 backdrop-blur-xl border-b border-gray-200/50 dark:border-white/10">
      <div class="max-w-3xl mx-auto flex items-center justify-between">
        <div class="flex items-center gap-4">
          <button @click="goBack" class="p-2 -ml-2 text-gray-500 hover:bg-gray-100 dark:hover:bg-white/10 rounded-xl transition">
            <ChevronLeft :size="20" />
          </button>
          <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-green-500 to-green-600 flex items-center justify-center shadow-lg shadow-green-500/20">
            <Target class="text-white" :size="28" />
          </div>
          <div>
            <h1 class="text-xl font-bold text-gray-900 dark:text-white">预算管理</h1>
            <div class="text-sm text-gray-500 dark:text-gray-400 mt-0.5">{{ categoryBudgets.length }} 个分类预算 · {{ memberBudgets.length }} 个成员预算</div>
          </div>
        </div>
        <button
          class="p-2.5 bg-gray-100/50 dark:bg-white/5 text-gray-400 hover:text-green-500 hover:bg-green-50 dark:hover:bg-green-900/20 rounded-full transition"
          :class="availableCategories.length === 0 ? 'opacity-50 cursor-not-allowed' : ''"
          :disabled="availableCategories.length === 0"
          @click="openCategoryForm()"
        >
          <Plus :size="20" />
        </button>
      </div>

      <!-- Member Budgets -->
      <div>
        <div class="flex items-center justify-between mb-4">
          <div>
            <h2 class="text-lg font-bold text-gray-900 dark:text-white">家庭成员预算</h2>
            <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">按成员控制家庭支出额度，可选绑定到具体分类</p>
          </div>
          <button
            class="px-4 py-2 bg-gray-900 text-white dark:bg-white dark:text-gray-900 rounded-xl text-sm font-semibold hover:opacity-90 transition disabled:opacity-50 disabled:cursor-not-allowed"
            :disabled="enabledFamilyMembers.length === 0"
            @click="openMemberForm()"
          >
            添加成员预算
          </button>
        </div>

        <div v-if="memberBudgets.length === 0" class="bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl rounded-2xl p-6 border border-gray-200/50 dark:border-gray-700/50 text-center text-sm text-gray-500">
          {{ enabledFamilyMembers.length === 0 ? '先在家庭成员页创建成员，再设置成员预算。' : '暂无成员预算，可为家庭成员设置月度支出额度。' }}
        </div>
        <div v-else class="space-y-3">
          <div
            v-for="budget in memberBudgets"
            :key="budget.id"
            class="bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl rounded-2xl p-4 border border-gray-200/50 dark:border-gray-700/50 shadow-sm group"
          >
            <div class="flex justify-between items-start mb-3">
              <div>
                <div class="font-semibold text-gray-900 dark:text-white">{{ budget.member_name || '家庭成员' }}</div>
                <div class="text-xs text-gray-400">{{ budget.category_name || '总预算' }} · 预算 ¥{{ formatMoney(budget.amount) }}</div>
              </div>
              <div class="flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                <button
                  class="p-1.5 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition"
                  @click="openMemberForm(budget)"
                >
                  <Edit2 :size="14" />
                </button>
                <button
                  class="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition"
                  @click="confirmDelete(budget.id)"
                >
                  <Trash2 :size="14" />
                </button>
              </div>
            </div>
            <div class="space-y-2">
              <div class="flex justify-between text-xs">
                <span class="text-gray-400">已用 ¥{{ formatMoney(budget.spent || 0) }}</span>
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
    </div>

    <div class="max-w-3xl mx-auto px-4 md:px-8 py-6 space-y-6">
      <!-- Total Budget Card -->
      <div class="bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl rounded-2xl p-5 border border-gray-200/50 dark:border-gray-700/50 shadow-sm">
        <div class="flex justify-between items-start mb-5">
          <div class="flex items-center gap-3">
            <div class="w-11 h-11 rounded-xl bg-gray-100 dark:bg-gray-700 flex items-center justify-center text-gray-600 dark:text-gray-300">
              <Target :size="20" />
            </div>
            <div>
              <div class="font-semibold text-gray-900 dark:text-white">月度总预算</div>
              <div class="text-gray-400 text-xs">控制每月总支出</div>
            </div>
          </div>
          <button 
            class="px-3 py-1.5 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-600 dark:text-gray-300 text-xs font-medium rounded-lg transition"
            @click="openTotalForm"
          >
            {{ totalBudget ? '修改' : '设置' }}
          </button>
        </div>

        <div v-if="totalBudget">
          <div class="flex justify-between items-end mb-4">
            <div>
              <div class="text-gray-400 text-xs mb-1">预算金额</div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white font-nums">
                <span class="text-base font-normal text-gray-400 mr-0.5">¥</span>{{ formatMoney(totalBudget.amount) }}
              </div>
            </div>
            <div class="text-right">
              <div class="text-gray-400 text-xs mb-1">已使用</div>
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

          <div class="flex justify-between text-xs text-gray-400">
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
            class="px-4 py-2 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 rounded-lg text-xs font-medium text-gray-600 dark:text-gray-300 transition"
            @click="openTotalForm"
          >
            立即设置
          </button>
        </div>
      </div>

      <!-- Category Budgets -->
      <div>
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-bold text-gray-900 dark:text-white">分类预算</h2>
          <span class="text-sm text-gray-400">{{ categoryBudgets.length }} 个分类</span>
        </div>

        <div v-if="loading" class="py-12 text-center text-gray-400">加载中...</div>

        <div v-else-if="categoryBudgets.length === 0" class="py-12 text-center">
          <div class="w-20 h-20 bg-gray-50 dark:bg-gray-700 rounded-full flex items-center justify-center mx-auto mb-4 text-3xl">
            📊
          </div>
          <p class="text-gray-500 mb-4">暂无分类预算</p>
          <button
            v-if="availableCategories.length > 0"
            class="px-6 py-2.5 bg-primary text-white rounded-xl hover:bg-primary/90 transition font-medium"
            @click="openCategoryForm()"
          >
            添加分类预算
          </button>
        </div>

        <div v-else class="space-y-3">
          <div 
            v-for="budget in categoryBudgets" 
            :key="budget.id"
            class="bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl rounded-2xl p-4 border border-gray-200/50 dark:border-gray-700/50 shadow-sm hover:shadow-md transition-all duration-200 group"
          >
            <div class="flex justify-between items-start mb-3">
              <div class="flex items-center gap-3">
                <div 
                  class="w-10 h-10 rounded-xl flex items-center justify-center text-xl bg-gray-50 dark:bg-gray-700"
                >
                  <DynamicIcon :icon="getCategoryIcon(budget.category_id)" :size="20" />
                </div>
                <div>
                  <div class="font-semibold text-gray-900 dark:text-white">{{ budget.category_name }}</div>
                  <div class="text-xs text-gray-400">预算 ¥{{ formatMoney(budget.amount) }}</div>
                </div>
              </div>
              <div class="flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                <button 
                  class="p-1.5 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition"
                  @click="openCategoryForm(budget)"
                >
                  <Edit2 :size="14" />
                </button>
                <button 
                  class="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition"
                  @click="confirmDelete(budget.id)"
                >
                  <Trash2 :size="14" />
                </button>
              </div>
            </div>

            <div class="space-y-2">
              <div class="flex justify-between text-xs">
                <span class="text-gray-400">已用 ¥{{ formatMoney(budget.spent || 0) }}</span>
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

    <!-- Budget Dialog -->
    <Teleport to="body">
      <div v-if="showDialog" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="closeDialog"></div>
        <div class="relative bg-white/90 dark:bg-gray-800/90 backdrop-blur-2xl rounded-3xl w-full max-w-md shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-gray-700/50">
          <div class="flex items-center justify-between p-6 border-b border-gray-100/50 dark:border-gray-700/50 bg-transparent">
            <h3 class="text-lg font-bold text-gray-900 dark:text-white">{{ getDialogTitle() }}</h3>
            <button class="p-2 hover:bg-gray-100/50 dark:hover:bg-gray-700/50 rounded-xl transition" @click="closeDialog">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div class="p-6 space-y-5">
            <!-- Category Selection (for category budget only) -->
            <div v-if="budgetMode === 'member'">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">选择成员</label>
              <div class="relative">
                <select
                  v-model="form.memberId"
                  class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none appearance-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-gray-900 dark:text-white"
                  :disabled="!!editingBudget"
                >
                  <option v-for="member in enabledFamilyMembers" :key="member.id" :value="member.id">
                    {{ member.name }}
                  </option>
                </select>
                <ChevronDown class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" :size="20" />
              </div>
            </div>

            <div v-if="budgetMode === 'category' || budgetMode === 'member'">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">选择分类</label>
              <div class="relative">
                <select
                  v-model="form.categoryId"
                  class="w-full h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none appearance-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-gray-900 dark:text-white"
                  :disabled="!!editingBudget"
                >
                  <option v-if="budgetMode === 'member'" value="">总预算</option>
                  <option v-for="cat in (budgetMode === 'member' ? expenseCategories : availableCategories)" :key="cat.id" :value="cat.id">
                    {{ cat.icon }} {{ cat.name }}
                  </option>
                </select>
                <ChevronDown class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" :size="20" />
              </div>
            </div>

            <!-- Amount Input -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">预算金额</label>
              <div class="relative">
                <span class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold text-2xl">¥</span>
                <input
                  v-model="form.amount"
                  type="number"
                  step="100"
                  placeholder="0"
                  class="w-full h-16 pl-10 pr-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-2xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-bold text-3xl text-gray-900 dark:text-white"
                />
              </div>
              <p class="text-xs text-gray-400 mt-2">建议根据实际消费情况设置合理预算</p>
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

    <!-- Delete Confirm Modal -->
    <Teleport to="body">
      <div v-if="showDeleteModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="showDeleteModal = false"></div>
        <div class="relative bg-white dark:bg-gray-800 rounded-3xl p-6 w-full max-w-sm shadow-2xl animate-in zoom-in-95 duration-200">
          <div class="w-12 h-12 bg-red-100 dark:bg-red-900/30 rounded-full flex items-center justify-center mb-4 mx-auto text-red-500">
            <Trash2 :size="24" />
          </div>
          <h3 class="text-lg font-bold text-center mb-2 text-gray-900 dark:text-white">确认删除</h3>
          <p class="text-gray-500 dark:text-gray-400 text-center text-sm mb-6">删除后将不再监控该分类的支出预算。</p>
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
