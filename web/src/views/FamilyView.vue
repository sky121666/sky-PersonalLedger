<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, BarChart3, CheckCircle2, Plus, RefreshCw, ShieldCheck, Trash2, TrendingUp, Users } from 'lucide-vue-next'
import { budgetApi, type Budget } from '@/api/budget'
import { familyApi, type FamilyMember, type FamilyStatistics, type FamilyStatisticsCategory, type FamilyStatisticsMember, type FamilySummary } from '@/api/family'
import { toast } from '@/composables/useToast'
import { formatLocalMonth } from '@/utils/localDate'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { createRequestGeneration } from '@/utils/requestGeneration'

const router = useRouter()
const loading = ref(false)
const saving = ref(false)
const members = ref<FamilyMember[]>([])
const summary = ref<FamilySummary | null>(null)
const statistics = ref<FamilyStatistics | null>(null)
const memberBudgets = ref<Budget[]>([])
const editingId = ref<string | null>(null)
const month = ref(formatLocalMonth())
const ledgerMutationRevision = useLedgerMutationRevision()
const dataRequests = createRequestGeneration()

const form = reactive({
  name: '',
  relationship: '',
  color: '#2563EB',
  is_default: false,
  is_enabled: true
})

const enabledMembers = computed(() => members.value.filter(member => member.is_enabled))
const rankedMembers = computed(() => [...(statistics.value?.members || [])].sort((a, b) => b.expense_total - a.expense_total))
const activeRankedMembers = computed(() => rankedMembers.value.filter(member => member.expense_total > 0 || member.count > 0))
const memberBudgetStats = computed(() => {
  const amount = memberBudgets.value.reduce((sum, budget) => sum + Number(budget.amount || 0), 0)
  const spent = memberBudgets.value.reduce((sum, budget) => sum + Number(budget.spent || 0), 0)
  return {
    amount,
    spent,
    remaining: amount - spent,
    percentage: amount > 0 ? Math.round((spent / amount) * 100) : 0
  }
})
const topMemberBudgets = computed(() => [...memberBudgets.value].sort((a, b) => Number(b.percentage || 0) - Number(a.percentage || 0)).slice(0, 4))

onMounted(loadData)
watch(ledgerMutationRevision, () => void loadData())

async function loadData() {
  const requestGeneration = dataRequests.begin()
  const requestedMonth = month.value
  loading.value = true
  try {
    const [memberList, familySummary, familyStatistics, budgetList] = await Promise.all([
      familyApi.listMembers(),
      familyApi.getSummary(requestedMonth),
      familyApi.getStatistics(requestedMonth),
      budgetApi.getList()
    ])
    if (
      !dataRequests.isLatest(requestGeneration)
      || month.value !== requestedMonth
    ) return
    members.value = memberList
    summary.value = familySummary
    statistics.value = familyStatistics
    memberBudgets.value = budgetList.member_budgets || []
  } catch (error: any) {
    if (dataRequests.isLatest(requestGeneration)) {
      toast.error(error.message || '家庭数据加载失败')
    }
  } finally {
    if (dataRequests.isLatest(requestGeneration)) {
      loading.value = false
    }
  }
}

function resetForm() {
  editingId.value = null
  form.name = ''
  form.relationship = ''
  form.color = '#2563EB'
  form.is_default = members.value.length === 0
  form.is_enabled = true
}

function editMember(member: FamilyMember) {
  editingId.value = member.id
  form.name = member.name
  form.relationship = member.relationship
  form.color = member.color || '#2563EB'
  form.is_default = member.is_default
  form.is_enabled = member.is_enabled
}

async function saveMember() {
  if (!form.name.trim()) {
    toast.error('请输入成员名称')
    return
  }
  saving.value = true
  try {
    const payload = {
      name: form.name.trim(),
      relationship: form.relationship.trim(),
      color: form.color,
      is_default: form.is_default,
      is_enabled: form.is_enabled
    }
    if (editingId.value) {
      await familyApi.updateMember(editingId.value, payload)
      toast.success('成员已更新')
    } else {
      await familyApi.createMember(payload)
      toast.success('成员已添加')
    }
    resetForm()
    await loadData()
  } catch (error: any) {
    toast.error(error.message || '保存失败')
  } finally {
    saving.value = false
  }
}

async function disableMember(member: FamilyMember) {
  if (!confirm(`停用成员「${member.name}」？历史交易归属仍会保留。`)) return
  try {
    await familyApi.deleteMember(member.id)
    toast.success('成员已停用')
    await loadData()
  } catch (error: any) {
    toast.error(error.message || '停用失败')
  }
}

function formatMoney(value = 0) {
  return `¥${Number(value).toFixed(2)}`
}

function budgetStatusClass(percentage = 0) {
  if (percentage >= 100) return 'text-rose-600 dark:text-rose-300'
  if (percentage >= 80) return 'text-amber-600 dark:text-amber-300'
  return 'text-emerald-600 dark:text-emerald-300'
}

function memberShare(member: FamilyStatisticsMember) {
  const total = Number(statistics.value?.total_expense || 0)
  if (total <= 0) return 0
  return Math.round((Number(member.expense_total || 0) / total) * 100)
}

function categoryShare(member: FamilyStatisticsMember, category: FamilyStatisticsCategory) {
  const total = Number(member.expense_total || 0)
  if (total <= 0) return 0
  return Math.max(4, Math.round((Number(category.amount || 0) / total) * 100))
}
</script>

<template>
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black text-gray-900 dark:text-white">
    <div class="max-w-6xl mx-auto px-4 py-6 space-y-6">
      <header class="flex items-center justify-between gap-4">
        <div class="flex items-center gap-3">
          <button class="p-2 rounded-full hover:bg-black/5 dark:hover:bg-white/10" @click="router.back()">
            <ArrowLeft :size="22" />
          </button>
          <div>
            <h1 class="text-2xl font-bold">家庭成员</h1>
            <p class="text-sm text-gray-500 dark:text-gray-400">按成员管理支出归属，保持私人部署的轻量家庭账本。</p>
          </div>
        </div>
        <button class="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-white/80 dark:bg-white/10 border border-black/5 dark:border-white/10" @click="loadData">
          <RefreshCw :size="16" />
          刷新
        </button>
      </header>

      <section class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="rounded-2xl bg-white/80 dark:bg-[#1C1C1E]/80 border border-black/5 dark:border-white/10 p-5">
          <p class="text-sm text-gray-500">启用成员</p>
          <p class="mt-2 text-3xl font-bold">{{ enabledMembers.length }}</p>
        </div>
        <div class="rounded-2xl bg-white/80 dark:bg-[#1C1C1E]/80 border border-black/5 dark:border-white/10 p-5 md:col-span-2">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm text-gray-500">本月家庭支出</p>
              <p class="mt-2 text-3xl font-bold">{{ formatMoney(summary?.total_expense || 0) }}</p>
            </div>
            <input v-model="month" type="month" class="px-3 py-2 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" @change="loadData" />
          </div>
        </div>
      </section>

      <section
        v-if="memberBudgets.length"
        class="rounded-[28px] bg-white/90 dark:bg-[#151517]/95 border border-black/5 dark:border-white/10 p-5 shadow-[0_18px_50px_rgba(15,23,42,0.08)]"
      >
        <div class="flex flex-col gap-5 lg:flex-row lg:items-start">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
              <ShieldCheck :size="17" />
              <span>家庭预算健康度</span>
            </div>
            <div class="mt-3 flex flex-wrap items-end gap-x-4 gap-y-2">
              <p class="text-4xl font-black tabular-nums">{{ memberBudgetStats.percentage }}%</p>
              <p class="pb-1 text-sm text-gray-500 dark:text-gray-400">
                已用 {{ formatMoney(memberBudgetStats.spent) }} / {{ formatMoney(memberBudgetStats.amount) }}
              </p>
            </div>
            <div class="mt-4 h-2.5 overflow-hidden rounded-full bg-gray-200 dark:bg-white/10">
              <div
                class="h-full rounded-full bg-gradient-to-r from-emerald-500 via-cyan-500 to-amber-400 transition-all duration-300"
                :style="{ width: `${Math.min(memberBudgetStats.percentage, 100)}%` }"
              />
            </div>
            <p class="mt-3 text-sm" :class="budgetStatusClass(memberBudgetStats.percentage)">
              剩余额度 {{ formatMoney(memberBudgetStats.remaining) }}
            </p>
          </div>
          <div class="grid flex-[1.2] grid-cols-1 gap-3 md:grid-cols-2">
            <div
              v-for="budget in topMemberBudgets"
              :key="budget.id"
              class="rounded-2xl border border-black/5 dark:border-white/10 bg-gray-50/80 dark:bg-white/[0.04] p-4"
            >
              <div class="flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <p class="truncate font-semibold">{{ budget.member_name || '家庭成员' }}</p>
                  <p class="mt-1 truncate text-xs text-gray-500">{{ budget.category_name || '总预算' }}</p>
                </div>
                <div class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-white dark:bg-white/10">
                  <TrendingUp :size="16" :class="budgetStatusClass(budget.percentage || 0)" />
                </div>
              </div>
              <div class="mt-3 flex items-center justify-between text-sm">
                <span class="text-gray-500">已用 {{ formatMoney(budget.spent || 0) }}</span>
                <span class="font-semibold tabular-nums" :class="budgetStatusClass(budget.percentage || 0)">
                  {{ Math.round(Number(budget.percentage || 0)) }}%
                </span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section
        class="rounded-[28px] bg-white/90 dark:bg-[#151517]/95 border border-black/5 dark:border-white/10 p-5 shadow-[0_18px_50px_rgba(15,23,42,0.08)]"
      >
        <div class="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
          <div>
            <div class="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
              <BarChart3 :size="17" />
              <span>成员分类拆分</span>
            </div>
            <h2 class="mt-2 text-xl font-bold">家庭支出结构</h2>
          </div>
          <div class="text-sm text-gray-500 dark:text-gray-400">
            {{ statistics?.month || month }} · {{ formatMoney(statistics?.total_expense || 0) }}
          </div>
        </div>

        <div v-if="activeRankedMembers.length" class="mt-5 grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div
            v-for="member in activeRankedMembers"
            :key="member.member_id"
            class="rounded-2xl border border-black/5 dark:border-white/10 bg-gray-50/80 dark:bg-white/[0.04] p-4"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <div class="flex items-center gap-2">
                  <span class="h-3 w-3 rounded-full" :style="{ backgroundColor: member.color || '#2563EB' }" />
                  <h3 class="truncate font-semibold">{{ member.name }}</h3>
                </div>
                <p class="mt-1 text-xs text-gray-500">{{ member.relationship || '家庭成员' }} · {{ member.count }} 笔</p>
              </div>
              <div class="text-right">
                <p class="font-bold tabular-nums">{{ formatMoney(member.expense_total) }}</p>
                <p class="text-xs text-gray-500">{{ memberShare(member) }}%</p>
              </div>
            </div>

            <div class="mt-4 space-y-3">
              <div
                v-for="category in member.categories.slice(0, 4)"
                :key="category.category_id || category.name"
                class="space-y-1.5"
              >
                <div class="flex items-center justify-between gap-3 text-sm">
                  <span class="min-w-0 truncate text-gray-600 dark:text-gray-300">{{ category.name || '未分类' }}</span>
                  <span class="shrink-0 tabular-nums text-gray-500">{{ formatMoney(category.amount) }}</span>
                </div>
                <div class="h-2 overflow-hidden rounded-full bg-gray-200 dark:bg-white/10">
                  <div
                    class="h-full rounded-full transition-all duration-300"
                    :style="{ width: `${categoryShare(member, category)}%`, backgroundColor: category.color || member.color || '#2563EB' }"
                  />
                </div>
              </div>
              <div v-if="member.categories.length === 0" class="rounded-xl bg-white/70 dark:bg-white/[0.04] px-3 py-2 text-sm text-gray-500">
                暂无分类支出
              </div>
            </div>
          </div>
        </div>
        <div v-else class="mt-5 rounded-2xl bg-gray-50/80 dark:bg-white/[0.04] p-6 text-center text-gray-500">
          当前月份暂无成员支出结构
        </div>
      </section>

      <section class="grid grid-cols-1 lg:grid-cols-[380px_1fr] gap-6">
        <form class="rounded-2xl bg-white/90 dark:bg-[#1C1C1E]/90 border border-black/5 dark:border-white/10 p-5 space-y-4" @submit.prevent="saveMember">
          <div class="flex items-center gap-2">
            <Plus :size="18" />
            <h2 class="font-semibold">{{ editingId ? '编辑成员' : '新增成员' }}</h2>
          </div>
          <input v-model="form.name" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" placeholder="成员名称" />
          <input v-model="form.relationship" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" placeholder="关系，例如 家人 / 子女" />
          <div class="flex items-center gap-3">
            <input v-model="form.color" type="color" class="w-12 h-12 rounded-xl bg-transparent" />
            <label class="flex items-center gap-2 text-sm">
              <input v-model="form.is_default" type="checkbox" />
              默认成员
            </label>
            <label class="flex items-center gap-2 text-sm">
              <input v-model="form.is_enabled" type="checkbox" />
              启用
            </label>
          </div>
          <div class="flex gap-3">
            <button class="flex-1 py-3 rounded-xl bg-primary text-white font-medium disabled:opacity-60" :disabled="saving">
              {{ saving ? '保存中...' : '保存' }}
            </button>
            <button type="button" class="px-4 py-3 rounded-xl bg-gray-100 dark:bg-white/10" @click="resetForm">重置</button>
          </div>
        </form>

        <div class="rounded-2xl bg-white/90 dark:bg-[#1C1C1E]/90 border border-black/5 dark:border-white/10 overflow-hidden">
          <div v-if="loading" class="p-8 text-center text-gray-500">加载中...</div>
          <div v-else-if="members.length === 0" class="p-8 text-center text-gray-500">
            <Users class="mx-auto mb-3" :size="42" />
            暂无家庭成员
          </div>
          <div
            v-for="member in members"
            v-else
            :key="member.id"
            class="w-full flex items-center gap-4 p-4 border-b border-black/5 dark:border-white/10 hover:bg-black/5 dark:hover:bg-white/5"
          >
            <button class="flex flex-1 items-center gap-4 min-w-0 text-left" @click="editMember(member)">
              <span class="w-11 h-11 rounded-full flex items-center justify-center text-white font-semibold" :style="{ backgroundColor: member.color || '#2563EB' }">
                {{ member.name.slice(0, 1) }}
              </span>
              <span class="flex-1 min-w-0">
                <span class="block font-medium truncate">{{ member.name }}</span>
                <span class="text-sm text-gray-500 truncate">{{ member.relationship || '家庭成员' }}</span>
              </span>
              <span v-if="member.is_default" class="inline-flex items-center gap-1 text-xs text-emerald-600">
                <CheckCircle2 :size="14" />
                默认
              </span>
              <span class="text-xs px-2 py-1 rounded-full" :class="member.is_enabled ? 'bg-emerald-100 text-emerald-700' : 'bg-gray-100 text-gray-500'">
                {{ member.is_enabled ? '启用' : '停用' }}
              </span>
            </button>
            <button class="p-2 rounded-lg hover:bg-red-50 text-red-500" @click.stop="disableMember(member)">
              <Trash2 :size="16" />
            </button>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
