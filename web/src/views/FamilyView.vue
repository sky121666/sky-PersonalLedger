<script setup lang="ts">
import { computed, nextTick, onMounted, reactive, ref, watch } from 'vue'
import { Check, CheckCircle2, ChevronDown, Pencil, Plus, RefreshCw, ShieldCheck, Trash2, TrendingUp, Users } from '@lucide/vue'
import FinancePage from '@/components/ui/FinancePage.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import { budgetApi, type Budget } from '@/api/budget'
import { familyApi, type FamilyMember, type FamilyStatistics, type FamilyStatisticsCategory, type FamilyStatisticsMember, type FamilySummary } from '@/api/family'
import { toast } from '@/composables/useToast'
import { formatLocalMonth } from '@/utils/localDate'
import { useLedgerMutationRevision } from '@/composables/useLedgerMutation'
import { createRequestGeneration } from '@/utils/requestGeneration'

const showMemberModal = ref(false)
const memberToDisable = ref<FamilyMember | null>(null)
const disablingMember = ref(false)
const disableTrigger = ref<HTMLElement | null>(null)
function confirmDisableMember(member: FamilyMember, event: MouseEvent) {
  disableTrigger.value = event.currentTarget as HTMLElement
  memberToDisable.value = member
}
const memberEditor = ref(false)
const memberTrigger = ref<HTMLElement | null>(null)
const expandedMember = ref<string | null>(null)
const memberColors = ['#007aff','#159b67','#db7d2c','#d95e8c','#6d66db']
const loading = ref(false)
const loadError = ref('')
const saving = ref(false)
const members = ref<FamilyMember[]>([])
const summary = ref<FamilySummary | null>(null)
const statistics = ref<FamilyStatistics | null>(null)
const memberBudgets = ref<Budget[]>([])
const editingId = ref<string | null>(null)
const month = ref(formatLocalMonth())
const ledgerMutationRevision = useLedgerMutationRevision()
const dataRequests = createRequestGeneration()
let loadedMonth: string | null = null

const form = reactive({
  name: '',
  relationship: '',
  color: '#2563EB',
  is_default: false,
  is_enabled: true
})

const enabledMembers = computed(() => members.value.filter(member => member.is_enabled))
const rankedMembers = computed(() => [...(statistics.value?.members || [])].sort((a, b) => b.expense_total - a.expense_total))
const attribution = computed(() => {
  if (!summary.value || !Array.isArray(summary.value.members)) return null
  const assigned = summary.value.members.reduce((sum, member) => sum + Math.round(member.expense_total * 100), 0)
  return { assigned: assigned / 100, unassigned: (Math.round(summary.value.total_expense * 100) - assigned) / 100 }
})
const displayMembers = computed<FamilyStatisticsMember[]>(() => {
  if (!statistics.value) return []
  const rows = [...rankedMembers.value]
  for (const member of members.value) if (!rows.some(row => row.member_id === member.id)) {
    rows.push({ member_id: member.id, name: member.name, relationship: member.relationship, color: member.color, expense_total: 0, count: 0, categories: [] })
  }
  return rows
})
function openMemberManager() { memberEditor.value = false; resetForm(); showMemberModal.value = true }
function focusMemberName() {
  void nextTick(() => document.querySelector<HTMLInputElement>('#family-member-form input[aria-label="成员名称"]')?.focus({ preventScroll: true }))
}
function addMember() { resetForm(); memberEditor.value = true; focusMemberName() }
function memberState(id: string) { return members.value.find(member => member.id === id) }
function memberDescription(id: string) {
  const member = memberState(id)
  return member ? !member.is_enabled ? '已停用' : member.is_default ? '默认成员' : member.relationship : '历史归属'
}
const memberBudgetStats = computed(() => {
  const totalMembers = new Set(memberBudgets.value.filter(budget => !budget.category_id).map(budget => budget.member_id))
  const effectiveBudgets = memberBudgets.value.filter(budget => !budget.category_id || !totalMembers.has(budget.member_id))
  const amount = effectiveBudgets.reduce((sum, budget) => sum + Number(budget.amount || 0), 0)
  const spent = effectiveBudgets.reduce((sum, budget) => sum + Number(budget.spent || 0), 0)
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
  if (loadedMonth !== requestedMonth) {
    summary.value = null
    statistics.value = null
    memberBudgets.value = []
  }
  loading.value = true
  loadError.value = ''
  try {
    const [memberList, familySummary, familyStatistics, budgetList] = await Promise.all([
      familyApi.listMembers(),
      familyApi.getSummary(requestedMonth),
      familyApi.getStatistics(requestedMonth),
      budgetApi.getList(requestedMonth)
    ])
    if (
      !dataRequests.isLatest(requestGeneration)
      || month.value !== requestedMonth
    ) return
    members.value = memberList
    summary.value = familySummary
    statistics.value = familyStatistics
    memberBudgets.value = budgetList.member_budgets || []
    loadedMonth = requestedMonth
  } catch (error: any) {
    if (dataRequests.isLatest(requestGeneration) && month.value === requestedMonth) {
      loadError.value = error.message || '家庭数据加载失败'
      toast.error(loadError.value)
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
  memberEditor.value = true
  showMemberModal.value = true
  editingId.value = member.id
  form.name = member.name
  form.relationship = member.relationship
  form.color = member.color || '#2563EB'
  form.is_default = member.is_default
  form.is_enabled = member.is_enabled
  focusMemberName()
}

async function saveMember() {
  if (saving.value) return
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
      await familyApi.createMember({ name: payload.name, relationship: payload.relationship, color: payload.color })
      toast.success('成员已添加')
    }
    resetForm()
    showMemberModal.value = false
    await loadData()
  } catch (error: any) {
    toast.error(error.message || '保存失败')
  } finally {
    saving.value = false
  }
}

async function disableMember() {
  if (!memberToDisable.value || disablingMember.value) return
  const member = memberToDisable.value
  disablingMember.value = true
  try {
    await familyApi.deleteMember(member.id)
    toast.success('成员已停用')
    await loadData()
    memberToDisable.value = null
  } catch (error: any) {
    toast.error(error.message || '停用失败')
  } finally {
    disablingMember.value = false
  }
}

function formatMoney(value = 0) {
  return `¥${Number(value).toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
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
  return Math.max(0, Math.min(100, (Number(category.amount || 0) / total) * 100))
}
</script>

<template>
  <FinancePage title="家庭成员">
    <template #actions><button ref="memberTrigger" class="finance-button" aria-label="管理成员" @click="openMemberManager"><Users :size="17" /><span>管理成员</span></button><button class="finance-icon-button" aria-label="刷新家庭数据" :disabled="loading" @click="loadData"><RefreshCw :size="17" /></button></template>
    <div v-if="loadError" role="alert" class="finance-card finance-card-padding text-sm text-amber-800 dark:text-amber-200"><p>{{ month }} 家庭数据加载失败：{{ loadError }}</p><p v-if="summary" class="mt-1">以下为该月份上次成功加载的结果，尚未更新。</p><button class="finance-button is-subtle mt-3" :disabled="loading" @click="loadData">重新加载</button></div>
    <p v-else-if="loading" role="status" class="finance-muted">正在加载 {{ month }} 家庭数据…</p>
    <section class="family-overview">
      <div class="finance-card family-count"><p class="finance-muted">启用成员</p><strong>{{ summary ? enabledMembers.length : '—' }}<span>位</span></strong></div>
      <div class="finance-card family-total"><div class="family-total-top"><div><p class="finance-muted">所选月份家庭支出</p><strong class="font-nums">{{ summary ? formatMoney(summary.total_expense) : '—' }}</strong></div><input v-model="month" aria-label="家庭统计月份" type="month" class="finance-input family-month" @change="loadData" /></div><div v-if="attribution" class="family-attribution"><span>已归属 <strong class="font-nums">{{ formatMoney(attribution.assigned) }}</strong></span><span>未归属 <strong class="font-nums">{{ formatMoney(attribution.unassigned) }}</strong></span></div></div>
    </section>
    <section class="finance-card family-member-panel">
      <div class="finance-card-heading"><h2>成员支出 <span class="finance-muted">{{ enabledMembers.length }} 位启用成员</span></h2><span class="finance-muted">{{ statistics?.month || month }}</span></div>
      <div v-if="statistics">
        <article v-for="member in displayMembers" :key="member.member_id" class="family-member-row">
          <button class="family-member-button" :aria-expanded="expandedMember === member.member_id" @click="expandedMember = expandedMember === member.member_id ? null : member.member_id">
            <span class="family-avatar" :style="{ backgroundColor: member.color || '#007aff' }">{{ (member.name || '历史成员').slice(0,1) }}</span><span class="family-member-name"><strong>{{ member.name || '历史成员' }}</strong><small>{{ memberDescription(member.member_id) || member.relationship || '成员' }}</small></span><span class="family-member-track"><i :style="{ width: `${Math.max(0, Math.min(memberShare(member),100))}%`, backgroundColor: member.color || '#007aff' }"></i></span><strong class="family-member-amount font-nums">{{ formatMoney(member.expense_total) }}</strong><span class="family-member-share">{{ memberShare(member) }}%</span><ChevronDown :size="16" class="family-chevron" :class="{ 'is-open': expandedMember === member.member_id }" />
          </button>
          <div v-if="expandedMember === member.member_id" class="family-member-details"><div v-for="category in member.categories" :key="category.category_id || category.name" class="family-category-row"><span>{{ category.name || '未分类' }}</span><strong class="font-nums">{{ formatMoney(category.amount) }}</strong><i :style="{ width: `${categoryShare(member,category)}%`, backgroundColor: category.color || member.color || '#007aff' }"></i></div><p v-if="!member.categories.length" class="finance-muted">本月暂无分类支出</p><button v-if="memberState(member.member_id)" class="finance-button is-subtle" :aria-label="`编辑成员 ${member.name}`" @click="editMember(memberState(member.member_id)!)"><Pencil :size="15" />编辑成员</button></div>
        </article>
        <article v-if="attribution && attribution.unassigned !== 0" class="family-member-row"><div class="family-member-button is-unassigned"><span class="family-avatar is-unassigned"><Users :size="18" /></span><span class="family-member-name"><strong>未归属</strong><small>尚未指定成员</small></span><strong class="family-member-amount font-nums">{{ formatMoney(attribution.unassigned) }}</strong></div></article>
        <div v-if="!displayMembers.length" class="finance-empty"><h2>暂无家庭成员</h2><p>成员用于标记支出归属，未归属的支出仍计入家庭总额。</p><button class="finance-button is-primary mt-4" @click="openMemberManager(); addMember()"><Plus :size="17" />新增成员</button></div>
      </div>
      <div v-else class="finance-empty"><p>{{ loading ? '正在加载所选月份支出结构…' : '尚未获取所选月份支出结构，请重新加载。' }}</p></div>
    </section>
    <p v-if="displayMembers.length" class="finance-muted">成员用于支出归属。未归属的支出仍计入家庭总额。</p>
      <section
        v-if="memberBudgets.length"
        class="finance-card finance-card-padding"
      >
        <div class="flex flex-col gap-5 md:flex-row md:items-start">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
              <ShieldCheck :size="17" />
              <span>家庭预算健康度</span>
            </div>
            <div class="mt-3 flex flex-wrap items-end gap-x-4 gap-y-2">
              <p class="text-3xl font-semibold tabular-nums">{{ memberBudgetStats.percentage }}%</p>
              <p class="pb-1 text-sm text-gray-500 dark:text-gray-400">
                已用 {{ formatMoney(memberBudgetStats.spent) }} / {{ formatMoney(memberBudgetStats.amount) }}
              </p>
            </div>
            <div class="mt-4 h-2.5 overflow-hidden rounded-full bg-gray-200 dark:bg-white/10">
              <div
                class="h-full rounded-full bg-primary "
                :style="{ width: `${Math.min(memberBudgetStats.percentage, 100)}%` }"
              />
            </div>
            <p class="mt-3 text-sm" :class="budgetStatusClass(memberBudgetStats.percentage)">
              剩余额度 {{ formatMoney(memberBudgetStats.remaining) }}
            </p>
            <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">成员设置总预算时按总预算计算；未设置时汇总其分类额度及对应支出。</p>
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
    <AppDialog v-if="showMemberModal" :title="memberEditor ? editingId ? '编辑成员' : '新增成员' : '管理成员'" :busy="saving" :return-focus="memberTrigger" @close="showMemberModal = false">
      <form v-if="memberEditor" id="family-member-form" class="space-y-4" @submit.prevent="saveMember"><div class="finance-form-grid"><label class="finance-field">成员名称<input v-model="form.name" aria-label="成员名称" placeholder="成员名称" class="finance-input" :disabled="saving" /></label><label class="finance-field">关系（可选）<input v-model="form.relationship" aria-label="关系" placeholder="关系，例如 家人 / 子女" class="finance-input" :disabled="saving" /></label></div><div class="finance-field"><span>头像颜色</span><div class="family-color-options"><button v-for="color in memberColors" :key="color" type="button" :aria-label="`头像颜色 ${color}`" :aria-pressed="form.color.toLowerCase() === color" :style="{ backgroundColor: color }" :disabled="saving" @click="form.color = color"><Check v-if="form.color.toLowerCase() === color" :size="16" /></button><input v-model="form.color" type="color" aria-label="自定义头像颜色" :disabled="saving" /></div></div><template v-if="editingId"><label class="family-switch-row"><span><strong>启用此成员</strong><small>停用后保留历史归属</small></span><input v-model="form.is_enabled" type="checkbox" role="switch" class="family-switch" :disabled="saving" /></label><label class="family-switch-row"><span><strong>设为默认成员</strong><small>新交易优先选择</small></span><input v-model="form.is_default" type="checkbox" role="switch" class="family-switch" :disabled="saving" /></label></template></form>
      <div v-else><button class="finance-button is-primary mb-4" @click="addMember"><Plus :size="17" />新增成员</button><div v-if="!members.length" class="finance-empty"><p>暂无家庭成员</p></div><div v-for="member in members" :key="member.id" class="family-management-row"><button class="family-management-edit" :aria-label="`编辑成员 ${member.name}`" @click="editMember(member)"><span class="family-avatar" :style="{ backgroundColor: member.color || '#007aff' }">{{ member.name.slice(0,1) }}</span><span><strong>{{ member.name }}</strong><small>{{ member.relationship || '成员' }} · {{ member.is_enabled ? '启用' : '停用' }}</small></span><CheckCircle2 v-if="member.is_default" :size="16" class="text-emerald-600" /></button><button v-if="member.is_enabled" class="finance-icon-button text-red-500" :aria-label="`停用成员 ${member.name}`" @click="confirmDisableMember(member, $event)"><Trash2 :size="17" /></button></div></div>
      <template #footer><template v-if="memberEditor"><button class="finance-button" :disabled="saving" @click="showMemberModal = false">取消</button><button class="finance-button is-primary" type="submit" form="family-member-form" :disabled="saving">{{ saving ? '保存中…' : '保存' }}</button></template><button v-else class="finance-button" @click="showMemberModal = false">关闭</button></template>
    </AppDialog>
    <AppDialog v-if="memberToDisable" title="停用成员" :busy="disablingMember" :return-focus="disableTrigger" sheet @close="memberToDisable = null">
      <p class="finance-muted">停用成员「{{ memberToDisable.name }}」？历史交易归属仍会保留。</p>
      <template #footer><button class="finance-button" :disabled="disablingMember" @click="memberToDisable = null">取消</button><button class="finance-button is-danger" :disabled="disablingMember" @click="disableMember">{{ disablingMember ? '停用中…' : '确认停用' }}</button></template>
    </AppDialog>
  </FinancePage>
</template>

<style scoped>
.family-overview { display: grid; grid-template-columns: 160px minmax(0,1fr); gap: 16px; }
.family-count,.family-total { padding: 22px; }
.family-count > strong { display: flex; align-items: baseline; gap: 8px; margin-top: 12px; font-size: 30px; font-weight: 550; }
.family-count > strong > span { font-size: 12px; color: var(--fp-secondary); font-weight: 400; }
.family-total-top { display: flex; align-items: center; justify-content: space-between; gap: 14px; flex-wrap: wrap; }
.family-total-top strong { display: block; margin-top: 9px; font-size: 28px; font-weight: 600; }
.family-month { width: 154px; min-height: 38px; font-size: 12px; }
.family-attribution { display: flex; flex-wrap: wrap; gap: 6px 24px; padding-top: 12px; margin-top: 16px; border-top: 1px solid var(--fp-line); color: var(--fp-secondary); font-size: 12px; }
.family-attribution strong { margin-left: 4px; color: var(--fp-ink); font-weight: 500; }
.family-attribution > span:last-child strong { color: #b97514; }
.family-member-panel { overflow: hidden; }
.family-member-panel > .finance-card-heading { padding: 18px 20px 14px; margin-bottom: 0; }
.family-member-button { display: flex; align-items: center; gap: 12px; width: 100%; min-height: 72px; padding: 14px 20px; text-align: left; border-top: 1px solid var(--fp-line); }
.family-avatar { display: grid; place-items: center; flex: none; width: 38px; height: 38px; border-radius: 12px; background: var(--fp-blue); color: white; font-size: 13px; font-weight: 600; }
.family-avatar.is-unassigned { background: var(--fp-soft); color: var(--fp-secondary); }
.family-member-name { flex: 1; min-width: 0; overflow-wrap: anywhere; }
.family-member-name strong { font-size: 14px; font-weight: 550; }
.family-member-name small { display: block; color: var(--fp-secondary); font-size: 12px; margin-top: 3px; }
.family-member-amount { flex: none; font-size: 14px; font-weight: 550; white-space: nowrap; }
.family-member-share { width: 45px; text-align: right; color: var(--fp-secondary); font-size: 12px; }
.family-member-track { width: 140px; height: 5px; overflow: hidden; background: var(--fp-line); border-radius: 99px; }
.family-member-track i { display: block; height: 100%; border-radius: inherit; }
.family-chevron { flex: none; color: var(--fp-secondary); transition: transform 180ms cubic-bezier(.23,1,.32,1); }
.family-chevron.is-open { transform: rotate(180deg); }
.family-member-details { padding: 0 20px 18px 70px; }
.family-category-row { position: relative; display: flex; justify-content: space-between; gap: 12px; padding: 12px 0; border-bottom: 1px solid var(--fp-line); font-size: 12px; }
.family-category-row span { color: var(--fp-secondary); overflow-wrap: anywhere; }
.family-category-row strong { font-weight: 500; white-space: nowrap; }
.family-category-row > i { position: absolute; left: 0; bottom: 0; height: 2px; opacity: .4; }
.family-member-details .finance-button { margin-top: 12px; }
.family-color-options { display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }
.family-color-options button { width: 32px; height: 32px; display: grid; place-items: center; border-radius: 50%; color: white; }
.family-color-options button[aria-pressed="true"] { outline: 2px solid var(--fp-blue); outline-offset: 3px; }
.family-color-options input { width: 32px; height: 32px; border: 0; background: transparent; }
.family-switch-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 16px 0; border-top: 1px solid var(--fp-line); }
.family-switch-row strong { font-size: 14px; font-weight: 500; }
.family-switch-row small { display: block; font-size: 12px; color: var(--fp-secondary); margin-top: 4px; }
.family-switch { appearance: none; width: 42px; height: 25px; position: relative; border-radius: 99px; background: #76768040; cursor: pointer; transition: background-color 150ms ease; }
.family-switch::before { content: ''; position: absolute; top: 3px; left: 3px; width: 19px; height: 19px; border-radius: 50%; background: white; box-shadow: 0 1px 3px #00000020; transition: transform 180ms cubic-bezier(.23,1,.32,1); }
.family-switch:checked { background: #007aff; }
.family-switch:checked::before { transform: translateX(17px); }
.family-management-row { display: flex; align-items: center; gap: 12px; border-top: 1px solid var(--fp-line); padding: 12px 0; }
.family-management-edit { display: flex; flex: 1; min-width: 0; align-items: center; gap: 12px; text-align: left; }
.family-management-edit > span:nth-child(2) { flex: 1; min-width: 0; overflow-wrap: anywhere; }
.family-management-edit strong { font-size: 14px; font-weight: 500; }
.family-management-edit small { display: block; margin-top: 3px; color: var(--fp-secondary); font-size: 12px; }
@media (hover:hover) and (pointer:fine) { .family-member-button:not(.is-unassigned):hover { background: var(--fp-blue-soft); } }
@media (max-width:767px) {
  .family-overview { grid-template-columns: 94px minmax(0,1fr); gap: 10px; }
  .family-count,.family-total { padding: 17px 14px; }
  .family-total-top strong { font-size: 24px; }
  .family-count > strong { font-size: 28px; }
  .family-month { width: 100%; max-width: 154px; }
  .family-attribution { gap: 6px 12px; }
  .family-member-panel > .finance-card-heading { padding: 17px 16px 13px; }
  .family-member-button { padding: 13px 16px; gap: 9px; }
  .family-member-track,.family-member-share { display: none; }
  .family-member-name strong,.family-member-amount { font-size: 13px; }
  .family-member-details { padding: 0 16px 18px 63px; }
}
@media (max-width:360px) { .family-overview { grid-template-columns: 80px minmax(0,1fr); } .family-count,.family-total { padding: 15px 12px; } .family-total-top strong { font-size: 21px; } }
</style>
