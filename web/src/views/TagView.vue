<script setup lang="ts">
import AppDialog from '@/components/ui/AppDialog.vue'
import FinancePage from '@/components/ui/FinancePage.vue'
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { Edit2, Plus, Tag as TagIcon, Trash2 } from '@lucide/vue'

import { tagApi, type Tag } from '@/api/tag'
import DynamicIcon from '@/components/DynamicIcon.vue'
import { toast } from '@/composables/useToast'

const router = useRouter()
const dialogTrigger = ref<HTMLElement | null>(null)
const dialogFallback = ref<HTMLElement | null>(null)
function captureDialogTrigger(event?: Event) {
  if (typeof document === 'undefined') return
  dialogTrigger.value = event?.currentTarget instanceof HTMLElement ? event.currentTarget : document.activeElement as HTMLElement | null
}

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

function openCreate(event?: Event) {
  captureDialogTrigger(event)
  editingTag.value = null
  form.value = { name: '', icon: '🏷️', color: '#007AFF' }
  showForm.value = true
}

function openEdit(tag: Tag, event?: Event) {
  captureDialogTrigger(event)
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
  if (submitting.value) return
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
  <FinancePage title="标签管理" :context="`${tags.length} 个标签`" :icon="TagIcon" back-label="返回上一页" @back="router.back()">
    <template #actions><button ref="dialogFallback" type="button" aria-label="添加标签" class="finance-icon-button" @click="openCreate"><Plus :size="20" /></button></template>

    <div class="space-y-3">
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
        <button class="rounded-xl p-2 text-gray-400 transition hover:bg-black/5 hover:text-primary dark:hover:bg-white/10" :aria-label="`编辑标签 ${tag.name}`" @click="openEdit(tag, $event)">
          <Edit2 :size="17" />
        </button>
        <button
          class="rounded-xl p-2 text-gray-400 transition hover:bg-red-50 hover:text-red-500 disabled:cursor-not-allowed disabled:opacity-25 dark:hover:bg-red-900/20"
          :disabled="tag.is_system" :aria-label="`删除标签 ${tag.name}`"
          @click="captureDialogTrigger($event); deletingTag = tag"
        >
          <Trash2 :size="17" />
        </button>
        </article>
      </template>
    </div>

    <AppDialog v-if="showForm" :title="editingTag ? '编辑标签' : '创建标签'" :busy="submitting" :return-focus="dialogTrigger" :fallback-focus="dialogFallback" sheet @close="(submitting) || (closeForm())">
      <fieldset :disabled="submitting" class="min-w-0 border-0 p-0 m-0"><div class="space-y-4">
            <label class="block">
              <span class="mb-1.5 block text-xs font-bold uppercase tracking-wider text-gray-400">名称</span>
              <input name="name" aria-label="名称" style="min-width: 0; max-width: 100%" v-model="form.name" maxlength="50" class="h-12 w-full rounded-xl border-0 bg-gray-100 px-4 text-gray-900 outline-hidden focus:ring-2 focus:ring-primary/30 dark:bg-white/10 dark:text-white" placeholder="例如：报销" />
            </label>
            <label class="block">
              <span class="mb-1.5 block text-xs font-bold uppercase tracking-wider text-gray-400">图标或 Emoji</span>
              <input name="icon" aria-label="图标或 Emoji" style="min-width: 0; max-width: 100%" v-model="form.icon" maxlength="50" class="h-12 w-full rounded-xl border-0 bg-gray-100 px-4 text-gray-900 outline-hidden focus:ring-2 focus:ring-primary/30 dark:bg-white/10 dark:text-white" placeholder="🏷️" />
            </label>
            <div>
              <span class="mb-2 block text-xs font-bold uppercase tracking-wider text-gray-400">颜色</span>
              <div class="flex flex-wrap gap-2">
                <button
                  v-for="color in colors"
                  :key="color" :aria-label="`选择颜色 ${color}`" :aria-pressed="form.color === color"
                  type="button"
                  class="h-8 w-8 rounded-full border-2 transition"
                  :class="form.color === color ? 'scale-110 border-gray-900 dark:border-white' : 'border-transparent'"
                  :style="{ backgroundColor: color }"
                  @click="form.color = color"
                ></button>
              </div>
            </div>

          </div>
      </fieldset>
      <template #footer><button class="h-12 w-full rounded-xl bg-primary font-semibold text-white transition disabled:opacity-50" :disabled="submitting" @click="saveTag">
              {{ submitting ? '保存中...' : '保存标签' }}
            </button></template>
    </AppDialog>

    <AppDialog v-if="deletingTag" :title="`删除「${deletingTag.name}」？`" :busy="submitting" :return-focus="dialogTrigger" :fallback-focus="dialogFallback" sheet @close="(submitting) || (deletingTag = null)">
      <fieldset :disabled="submitting" class="min-w-0 border-0 p-0 m-0"><p class="mt-2 text-sm text-gray-500 dark:text-gray-400">历史交易中的文字标签会保留。</p>
      </fieldset>
      <template #footer><button class="h-11 rounded-xl bg-gray-100 text-gray-700 dark:bg-white/10 dark:text-gray-200" @click="deletingTag = null" :disabled="submitting">取消</button>
            <button class="h-11 rounded-xl bg-red-500 font-medium text-white disabled:opacity-50" :disabled="submitting" @click="deleteTag">删除</button></template>
    </AppDialog>
  </FinancePage>
</template>
