<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, Plus, RefreshCw, Users, Trash2, CheckCircle2 } from 'lucide-vue-next'
import { familyApi, type FamilyMember, type FamilySummary } from '@/api/family'
import { toast } from '@/composables/useToast'

const router = useRouter()
const loading = ref(false)
const saving = ref(false)
const members = ref<FamilyMember[]>([])
const summary = ref<FamilySummary | null>(null)
const editingId = ref<string | null>(null)
const month = ref(new Date().toISOString().slice(0, 7))

const form = reactive({
  name: '',
  relationship: '',
  color: '#2563EB',
  is_default: false,
  is_enabled: true
})

const enabledMembers = computed(() => members.value.filter(member => member.is_enabled))

onMounted(loadData)

async function loadData() {
  loading.value = true
  try {
    const [memberList, familySummary] = await Promise.all([
      familyApi.listMembers(),
      familyApi.getSummary(month.value)
    ])
    members.value = memberList
    summary.value = familySummary
  } catch (error: any) {
    toast.error(error.message || '家庭数据加载失败')
  } finally {
    loading.value = false
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
