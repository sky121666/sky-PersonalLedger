<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronLeft, Edit2, Plus, Tag as TagIcon, Trash2, X } from 'lucide-vue-next'

import { tagApi, type Tag } from '@/api/tag'
import DynamicIcon from '@/components/DynamicIcon.vue'
import { toast } from '@/composables/useToast'

const router = useRouter()
const tags = ref<Tag[]>([])
const loading = ref(true)
const submitting = ref(false)
const loadError = ref(false)
const showForm = ref(false)
const editingTag = ref<Tag | null>(null)
const deletingTag = ref<Tag | null>(null)
const form = ref({ name: '', icon: '🏷️', color: '#007AFF' })

const colors = [
  '#007AFF', '#5856D6', '#AF52DE', '#FF2D55', '#FF3B30', '#FF9500',
  '#34C759', '#30B0C7', '#64748B', '#8E8E93',
]

onMounted(loadTags)

async function loadTags() {
  loading.value = true
  loadError.value = false
  try {
    tags.value = await tagApi.list()
  } catch {
    loadError.value = true
  } finally {
    loading.value = false
  }
}

function openCreate() {
  editingTag.value = null
  form.value = { name: '', icon: '🏷️', color: '#007AFF' }
  showForm.value = true
}

function openEdit(tag: Tag) {
  editingTag.value = tag
  form.value = {
    name: tag.name,
    icon: tag.icon || '🏷️',
    color: tag.color || '#007AFF',
  }
  showForm.value = true
}

function closeForm() {
  if (submitting.value) return
  showForm.value = false
  editingTag.value = null
}

async function saveTag() {
  const name = form.value.name.trim()
  if (!name) {
    toast.warning('请输入标签名称')
    return
  }
  submitting.value = true
  try {
    const payload = { name, icon: form.value.icon.trim(), color: form.value.color }
    if (editingTag.value) {
      await tagApi.update(editingTag.value.id, payload)
      toast.success('标签已更新')
    } else {
      await tagApi.create(payload)
      toast.success('标签已创建')
    }
    showForm.value = false
    editingTag.value = null
    await loadTags()
  } catch (error: any) {
    toast.error(error.message || '标签保存失败')
  } finally {
    submitting.value = false
  }
}

async function deleteTag() {
  const tag = deletingTag.value
  if (!tag || submitting.value) return
  submitting.value = true
  try {
    await tagApi.delete(tag.id)
    deletingTag.value = null
    toast.success('标签已删除')
    await loadTags()
  } catch (error: any) {
    toast.error(error.message || '标签删除失败')
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
          <button class="-ml-2 rounded-xl p-2 text-gray-500 transition hover:bg-black/5 dark:hover:bg-white/10" @click="router.back()">
            <ChevronLeft :size="20" />
          </button>
          <div class="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
            <TagIcon :size="24" />
          </div>
          <div>
            <h1 class="text-xl font-bold text-gray-900 dark:text-white">标签管理</h1>
            <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">{{ tags.length }} 个标签 · 按真实使用次数排序</p>
          </div>
        </div>
        <button class="flex h-10 w-10 items-center justify-center rounded-full bg-primary text-white shadow-lg shadow-primary/20 transition active:scale-95" @click="openCreate">
          <Plus :size="20" />
        </button>
      </div>
    </header>

    <main class="mx-auto max-w-3xl space-y-3 px-4 py-6 md:px-8">
      <div v-if="loading" class="py-20 text-center text-sm text-gray-400">正在加载标签...</div>
      <div v-else-if="loadError" class="rounded-3xl border border-white/50 bg-white/75 p-8 text-center shadow-sm dark:border-white/5 dark:bg-[#1C1C1E]/75">
        <p class="text-gray-600 dark:text-gray-300">标签加载失败</p>
        <button class="mt-4 rounded-xl bg-primary px-5 py-2.5 text-sm font-medium text-white" @click="loadTags">重新加载</button>
      </div>
      <div v-else-if="tags.length === 0" class="rounded-3xl border border-white/50 bg-white/75 p-10 text-center shadow-sm dark:border-white/5 dark:bg-[#1C1C1E]/75">
        <div class="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10 text-primary">
          <TagIcon :size="28" />
        </div>
        <h2 class="font-semibold text-gray-900 dark:text-white">还没有标签</h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">创建标签后，可在记账时多选使用。</p>
        <button class="mt-5 rounded-xl bg-primary px-5 py-2.5 text-sm font-medium text-white" @click="openCreate">创建标签</button>
      </div>
      <template v-else>
        <article
          v-for="tag in tags"
          :key="tag.id"
          class="flex items-center gap-4 rounded-2xl border border-white/50 bg-white/75 p-4 shadow-sm backdrop-blur-xl dark:border-white/5 dark:bg-[#1C1C1E]/75"
        >
        <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl" :style="{ backgroundColor: `${tag.color || '#8E8E93'}18`, color: tag.color || '#8E8E93' }">
          <DynamicIcon :icon="tag.icon || '🏷️'" :size="21" />
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-2">
            <h2 class="truncate font-semibold text-gray-900 dark:text-white">{{ tag.name }}</h2>
            <span v-if="tag.is_system" class="rounded-full bg-gray-100 px-2 py-0.5 text-[10px] text-gray-500 dark:bg-white/10 dark:text-gray-400">默认</span>
          </div>
          <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">已用于 {{ tag.used_count }} 笔交易</p>
        </div>
        <button class="rounded-xl p-2 text-gray-400 transition hover:bg-black/5 hover:text-primary dark:hover:bg-white/10" @click="openEdit(tag)">
          <Edit2 :size="17" />
        </button>
        <button
          class="rounded-xl p-2 text-gray-400 transition hover:bg-red-50 hover:text-red-500 disabled:cursor-not-allowed disabled:opacity-25 dark:hover:bg-red-900/20"
          :disabled="tag.is_system"
          @click="deletingTag = tag"
        >
          <Trash2 :size="17" />
        </button>
        </article>
      </template>
    </main>

    <Teleport to="body">
      <div v-if="showForm" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="closeForm"></div>
        <div class="relative w-full max-w-sm rounded-3xl border border-white/30 bg-white/95 p-6 shadow-2xl dark:border-white/10 dark:bg-[#1C1C1E]/95">
          <div class="mb-5 flex items-center justify-between">
            <h2 class="text-lg font-bold text-gray-900 dark:text-white">{{ editingTag ? '编辑标签' : '创建标签' }}</h2>
            <button class="rounded-full p-2 text-gray-400 hover:bg-black/5 dark:hover:bg-white/10" @click="closeForm"><X :size="19" /></button>
          </div>
          <div class="space-y-4">
            <label class="block">
              <span class="mb-1.5 block text-xs font-bold uppercase tracking-wider text-gray-400">名称</span>
              <input v-model="form.name" maxlength="50" class="h-12 w-full rounded-xl border-0 bg-gray-100 px-4 text-gray-900 outline-none focus:ring-2 focus:ring-primary/30 dark:bg-white/10 dark:text-white" placeholder="例如：报销" />
            </label>
            <label class="block">
              <span class="mb-1.5 block text-xs font-bold uppercase tracking-wider text-gray-400">图标或 Emoji</span>
              <input v-model="form.icon" maxlength="50" class="h-12 w-full rounded-xl border-0 bg-gray-100 px-4 text-gray-900 outline-none focus:ring-2 focus:ring-primary/30 dark:bg-white/10 dark:text-white" placeholder="🏷️" />
            </label>
            <div>
              <span class="mb-2 block text-xs font-bold uppercase tracking-wider text-gray-400">颜色</span>
              <div class="flex flex-wrap gap-2">
                <button
                  v-for="color in colors"
                  :key="color"
                  type="button"
                  class="h-8 w-8 rounded-full border-2 transition"
                  :class="form.color === color ? 'scale-110 border-gray-900 dark:border-white' : 'border-transparent'"
                  :style="{ backgroundColor: color }"
                  @click="form.color = color"
                ></button>
              </div>
            </div>
            <button class="h-12 w-full rounded-xl bg-primary font-semibold text-white transition disabled:opacity-50" :disabled="submitting" @click="saveTag">
              {{ submitting ? '保存中...' : '保存标签' }}
            </button>
          </div>
        </div>
      </div>

      <div v-if="deletingTag" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="deletingTag = null"></div>
        <div class="relative w-full max-w-xs rounded-3xl bg-white/95 p-6 text-center shadow-2xl dark:bg-[#1C1C1E]/95">
          <div class="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-red-100 text-red-500 dark:bg-red-900/30"><Trash2 :size="22" /></div>
          <h2 class="font-bold text-gray-900 dark:text-white">删除「{{ deletingTag.name }}」？</h2>
          <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">历史交易中的文字标签会保留。</p>
          <div class="mt-6 grid grid-cols-2 gap-3">
            <button class="h-11 rounded-xl bg-gray-100 text-gray-700 dark:bg-white/10 dark:text-gray-200" @click="deletingTag = null">取消</button>
            <button class="h-11 rounded-xl bg-red-500 font-medium text-white disabled:opacity-50" :disabled="submitting" @click="deleteTag">删除</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
