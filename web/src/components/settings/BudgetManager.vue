<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { Plus, Trash2, Edit2, X, Target, AlertCircle } from 'lucide-vue-next'
import { budgetApi, type Budget } from '@/api/budget'
import { categoryApi, type Category } from '@/api/category'
import { toast } from '@/composables/useToast'
import { getCategoryEmoji } from '@/utils/constants'

const props = defineProps<{
  visible: boolean
}>()

const emit = defineEmits<{
  (e: 'update:visible', value: boolean): void
}>()

// Props is used reactively, no need for explicit reference
if (props.visible) {
  // Component is visible
}

const loading = ref(false)
const totalBudget = ref<Budget | null>(null)
const categoryBudgets = ref<Budget[]>([])
const categories = ref<Category[]>([])

// Form State
const showForm = ref(false)
const editingBudget = ref<Budget | null>(null)
const form = ref({
  amount: '',
  categoryId: ''
})

const availableCategories = computed(() => {
  const usedIds = new Set(categoryBudgets.value.map(b => b.category_id))
  // If editing, include the current category
  if (editingBudget.value?.category_id) {
    usedIds.delete(editingBudget.value.category_id)
  }
  return categories.value.filter(c => c.type === 'expense' && !usedIds.has(c.id))
})

onMounted(() => {
  loadData()
})

async function loadData() {
  loading.value = true
  try {
    const [bData, cData] = await Promise.all([
      budgetApi.getList(),
      categoryApi.getList('expense')
    ])
    totalBudget.value = bData.total_budget
    categoryBudgets.value = bData.category_budgets || []
    categories.value = cData
  } catch (e: any) {
    toast.error('加载数据失败')
  } finally {
    loading.value = false
  }
}

function openTotalForm() {
  editingBudget.value = null // null means total budget if categoryId is empty
  form.value = {
    amount: totalBudget.value?.amount.toString() || '',
    categoryId: ''
  }
  showForm.value = true
}

function openCategoryForm(budget?: Budget) {
  editingBudget.value = budget || null
  form.value = {
    amount: budget?.amount.toString() || '',
    categoryId: budget?.category_id || ''
  }
  showForm.value = true
}

async function saveBudget() {
  const amount = parseFloat(form.value.amount)
  if (!amount || amount <= 0) {
    toast.warning('请输入有效的金额')
    return
  }

  try {
    if (form.value.categoryId) {
      // Set Category Budget
      await budgetApi.setCategory(form.value.categoryId, amount)
      toast.success('分类预算已保存')
    } else {
      // Set Total Budget
      await budgetApi.setTotal(amount)
      toast.success('总预算已保存')
    }
    showForm.value = false
    loadData()
  } catch (e: any) {
    toast.error(e.message || '保存失败')
  }
}

async function deleteBudget(id: string) {
  if (!confirm('确定要删除这个预算设置吗？')) return
  try {
    await budgetApi.delete(id)
    toast.success('删除成功')
    loadData()
  } catch (e: any) {
    toast.error(e.message || '删除失败')
  }
}

function formatMoney(val: number) {
  return val.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 0 })
}

function getPercentColor(percent: number) {
  if (percent >= 100) return 'bg-red-500'
  if (percent >= 80) return 'bg-yellow-500'
  return 'bg-primary'
}

function close() {
  emit('update:visible', false)
}
</script>

<template>
  <Teleport to="body">
    <div v-if="visible" class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="close"></div>
      <div class="relative bg-white rounded-3xl w-full max-w-lg max-h-[85vh] flex flex-col shadow-2xl overflow-hidden">
        <!-- Header -->
        <div class="flex items-center justify-between p-6 border-b border-gray-100 bg-white z-10">
          <h3 class="text-xl font-bold text-gray-900">预算管理</h3>
          <button class="p-2 hover:bg-gray-100 rounded-xl transition" @click="close">
            <X :size="20" class="text-gray-500" />
          </button>
        </div>

        <div class="flex-1 overflow-y-auto bg-gray-50 p-4">
          <!-- Total Budget Card -->
          <div class="bg-white rounded-2xl p-5 shadow-sm border border-gray-100 mb-6">
            <div class="flex justify-between items-start mb-4">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center text-primary">
                  <Target :size="20" />
                </div>
                <div>
                  <div class="font-bold text-gray-900">月度总预算</div>
                  <div class="text-xs text-gray-400">控制每月总支出</div>
                </div>
              </div>
              <button 
                class="px-3 py-1.5 bg-gray-50 hover:bg-gray-100 text-gray-600 text-sm font-medium rounded-lg transition"
                @click="openTotalForm"
              >
                {{ totalBudget ? '修改' : '设置' }}
              </button>
            </div>

            <div v-if="totalBudget" class="space-y-3">
              <div class="flex justify-between items-end">
                <div class="text-3xl font-bold tabular-nums">
                  <span class="text-sm font-normal text-gray-400 align-top mr-0.5">¥</span>
                  {{ formatMoney(totalBudget.amount) }}
                </div>
                <div class="text-right">
                  <div class="text-xs text-gray-400 mb-0.5">已用 {{ formatMoney(totalBudget.spent || 0) }}</div>
                  <div class="font-bold tabular-nums" :class="(totalBudget.percentage || 0) > 100 ? 'text-red-500' : 'text-gray-900'">
                    {{ (totalBudget.percentage || 0).toFixed(0) }}%
                  </div>
                </div>
              </div>
              <div class="h-2.5 bg-gray-100 rounded-full overflow-hidden">
                <div 
                  class="h-full rounded-full transition-all duration-500"
                  :class="getPercentColor(totalBudget.percentage || 0)"
                  :style="{ width: `${Math.min(totalBudget.percentage || 0, 100)}%` }"
                ></div>
              </div>
              <div v-if="(totalBudget.percentage || 0) >= 80" class="flex items-center gap-1.5 text-xs text-red-500 bg-red-50 px-2 py-1 rounded-lg w-fit">
                <AlertCircle :size="12" />
                <span>接近或超出预算警告</span>
              </div>
            </div>
            <div v-else class="text-center py-4 text-gray-400 text-sm">
              暂未设置月度总预算
            </div>
          </div>

          <!-- Category Budgets -->
          <div class="space-y-4">
            <div class="flex items-center justify-between px-1">
              <h4 class="font-bold text-gray-900">分类预算</h4>
              <button 
                class="flex items-center gap-1.5 text-primary text-sm font-medium hover:bg-primary/5 px-3 py-1.5 rounded-lg transition"
                @click="openCategoryForm()"
              >
                <Plus :size="16" />
                <span>添加</span>
              </button>
            </div>

            <div v-if="categoryBudgets.length === 0" class="text-center py-8 text-gray-400 text-sm">
              暂无分类预算
            </div>

            <div v-else class="grid gap-3">
              <div 
                v-for="budget in categoryBudgets" 
                :key="budget.id"
                class="bg-white rounded-xl p-4 shadow-sm border border-gray-100 group"
              >
                <div class="flex justify-between items-start mb-3">
                  <div class="flex items-center gap-3">
                    <div class="text-xl w-8 h-8 flex items-center justify-center bg-gray-50 rounded-lg">
                      {{ getCategoryEmoji(budget.category_name || '') }}
                    </div>
                    <div>
                      <div class="font-medium text-gray-900">{{ budget.category_name }}</div>
                      <div class="text-xs text-gray-400">¥{{ formatMoney(budget.amount) }}</div>
                    </div>
                  </div>
                  <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                    <button 
                      class="p-1.5 text-gray-400 hover:text-primary hover:bg-primary/10 rounded-lg transition"
                      @click="openCategoryForm(budget)"
                    >
                      <Edit2 :size="14" />
                    </button>
                    <button 
                      class="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition"
                      @click="deleteBudget(budget.id)"
                    >
                      <Trash2 :size="14" />
                    </button>
                  </div>
                </div>

                <div class="space-y-1.5">
                  <div class="flex justify-between text-xs text-gray-400">
                    <span>已用 ¥{{ formatMoney(budget.spent || 0) }}</span>
                    <span :class="(budget.percentage || 0) > 100 ? 'text-red-500 font-medium' : ''">
                      {{ (budget.percentage || 0).toFixed(0) }}%
                    </span>
                  </div>
                  <div class="h-1.5 bg-gray-100 rounded-full overflow-hidden">
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
      </div>

      <!-- Edit Modal (Nested) -->
      <div v-if="showForm" class="absolute inset-0 z-[60] flex items-center justify-center p-4 bg-black/20 backdrop-blur-[1px]">
        <div class="bg-white rounded-2xl w-full max-w-sm p-6 shadow-xl animate-in zoom-in-95 duration-200">
          <h4 class="font-bold text-lg mb-4">
            {{ form.categoryId ? '设置分类预算' : '设置总预算' }}
          </h4>
          
          <div class="space-y-4">
            <div v-if="!editingBudget && form.categoryId !== undefined">
              <label class="block text-xs font-medium text-gray-400 mb-1.5">选择分类</label>
              <select 
                v-model="form.categoryId"
                class="w-full h-10 px-3 bg-gray-50 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 text-sm"
                :disabled="!!editingBudget"
              >
                <option value="" disabled>请选择分类</option>
                <option v-for="cat in availableCategories" :key="cat.id" :value="cat.id">
                  {{ cat.name }}
                </option>
              </select>
            </div>

            <div>
              <label class="block text-xs font-medium text-gray-400 mb-1.5">预算金额</label>
              <div class="relative">
                <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 font-bold">¥</span>
                <input
                  v-model="form.amount"
                  type="number"
                  placeholder="0"
                  class="w-full h-12 pl-8 pr-4 bg-gray-50 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 font-bold text-lg"
                  autoFocus
                />
              </div>
            </div>

            <div class="flex gap-3 pt-2">
              <button 
                class="flex-1 py-2.5 bg-gray-100 text-gray-600 rounded-xl font-medium hover:bg-gray-200 transition"
                @click="showForm = false"
              >
                取消
              </button>
              <button 
                class="flex-1 py-2.5 bg-primary text-white rounded-xl font-medium hover:bg-primary/90 transition"
                @click="saveBudget"
              >
                保存
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
