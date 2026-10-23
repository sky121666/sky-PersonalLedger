<script setup lang="ts">
import AppDialog from '@/components/ui/AppDialog.vue'
import FinancePage from '@/components/ui/FinancePage.vue'
import { ref, onMounted, onBeforeUnmount, watch } from 'vue'
import { useRouter } from 'vue-router'
import { Plus, Trash2, Edit2, Check, Grid3X3 } from '@lucide/vue'
import { categoryApi, type Category } from '@/api/category'
import { toast } from '@/composables/useToast'
import DynamicIcon from '@/components/DynamicIcon.vue'

import { createRequestGeneration } from '@/utils/requestGeneration'

const router = useRouter()
const dialogTrigger = ref<HTMLElement | null>(null)
const dialogFallback = ref<HTMLElement | null>(null)
function captureDialogTrigger(event?: Event) {
  if (typeof document === 'undefined') return
  dialogTrigger.value = event?.currentTarget instanceof HTMLElement ? event.currentTarget : document.activeElement as HTMLElement | null
}

const categoryRequests = createRequestGeneration()
const loadFailed = ref(false)
const loadedType = ref('')
onBeforeUnmount(() => categoryRequests.begin())

// Extended emoji list for better coverage
const CATEGORY_EMOJIS = [
  // 餐饮食物
  '🍽️', '🍚', '🍜', '🍱', '🍔', '🍕', '🍟', '🌮', '🥗', '🥐', '🍞', '🥛', '🍳', '🥘', '🍲',
  '🍿', '🍎', '🍊', '🍇', '🍓', '🍑', '🥤', '🍵', '☕', '🍺', '🍷', '🧁', '🍰', '🍫', '🍬',
  // 交通出行
  '🚗', '🚕', '🚌', '🚇', '🚄', '✈️', '🛵', '🚲', '🛴', '🚶', '⛽', '🅿️', '🚁', '🛳️', '🚀',
  // 购物消费
  '🛒', '🛍️', '🏪', '🏬', '💳', '🎁', '📦', '🧾', '💰', '💵', '💴', '🪙', '💎', '👑', '🎀',
  // 服饰美容
  '👔', '👗', '👠', '👟', '👜', '🧥', '👒', '🕶️', '💄', '💅', '💇', '🧴', '🪮', '👙', '🩱',
  // 居住生活
  '🏠', '🏢', '🏡', '🛏️', '🛋️', '🪑', '💡', '💧', '🔥', '🧹', '🧺', '🔑', '🚿', '🛁', '🚽',
  // 通讯办公
  '📱', '💻', '🖥️', '⌨️', '🖨️', '📞', '📧', '📝', '📎', '📁', '🗂️', '✏️', '📐', '🔍', '📊',
  // 娱乐休闲
  '🎮', '🎬', '🎤', '🎧', '🎸', '🎹', '🎲', '🎯', '🎳', '🎪', '🎠', '🎡', '🎢', '🎰', '🎨',
  // 运动健身
  '⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '🏓', '🏸', '🥊', '🏊', '🚴', '🏃', '🧘', '🏋️', '⛳',
  // 医疗健康
  '💊', '💉', '🏥', '🩺', '🩹', '🦷', '👓', '🩼', '♿', '🧬', '🔬', '🩻', '❤️‍🩹', '🫀', '🧠',
  // 教育学习
  '📚', '📖', '🎓', '🏫', '✍️', '📒', '🖊️', '📏', '🔖', '🎒', '📐', '🧮', '🗃️', '📜', '🔭',
  // 旅行度假
  '🗺️', '🧳', '🏖️', '🏔️', '🏕️', '🎿', '🏄', '🚢', '🗼', '🗽', '🏰', '⛺', '🌅', '🌄', '📸',
  // 宠物动物
  '🐱', '🐶', '🐹', '🐰', '🦜', '🐠', '🐢', '🦎', '🐍', '🕷️', '🦔', '🐾', '🦴', '🐕', '🐈',
  // 社交人物
  '👥', '👨‍👩‍👧', '👶', '👵', '🤝', '💑', '👪', '🧑‍🤝‍🧑', '💏', '🫂', '👫', '👬', '👭', '🧑‍🍼', '👴',
  // 节日礼物
  '🎂', '🎄', '🎃', '🎆', '🧧', '🎊', '🎉', '🪅', '🎋', '🎍', '💐', '🌹', '🌸', '🎈', '🕯️',
  // 金融理财
  '📈', '📉', '💹', '🏦', '🏧', '💸', '🧾', '📑', '🏷️', '💲', '🪪', '📃', '🔐', '🗃️', '📂',
  // 其他常用
  '⭐', '🌟', '❤️', '💜', '💙', '💚', '💛', '🧡', '🤍', '🖤', '❓', '❗', '✅', '❌', '➕'
]

const CATEGORY_COLORS = [
  '#EF4444', '#F97316', '#F59E0B', '#84CC16', '#10B981', '#06B6D4',
  '#3B82F6', '#6366F1', '#8B5CF6', '#EC4899', '#64748B', '#71717A'
]

const activeTab = ref<'expense' | 'income'>('expense')
const categories = ref<Category[]>([])
const loading = ref(false)

// Dialog state
const showDialog = ref(false)
const saving = ref(false)
const editingCategory = ref<Category | null>(null)
const form = ref({
  name: '',
  icon: '🍽️',
  color: CATEGORY_COLORS[0]
})
const showEmojiPicker = ref(false)

// Delete confirm
const showDeleteModal = ref(false)
const deletingId = ref<string | null>(null)
const deleting = ref(false)

onMounted(() => {
  loadCategories()
})

watch(activeTab, () => {
  loadCategories()
})

async function loadCategories() {
  const generation = categoryRequests.begin()
  const type = activeTab.value
  loading.value = true
  loadFailed.value = false
  if (loadedType.value !== type) categories.value = []
  try {
    const result = await categoryApi.getList(type)
    if (!categoryRequests.isLatest(generation) || activeTab.value !== type) return
    categories.value = result
    loadedType.value = type
  } catch (e: any) {
    if (!categoryRequests.isLatest(generation)) return
    loadFailed.value = true
    toast.error('加载分类失败')
  } finally {
    if (categoryRequests.isLatest(generation)) loading.value = false
  }
}

function goBack() {
  router.back()
}

function openCreate(event?: Event) {
  captureDialogTrigger(event)
  editingCategory.value = null
  form.value = {
    name: '',
    icon: activeTab.value === 'expense' ? '🍽️' : '💰',
    color: CATEGORY_COLORS[Math.floor(Math.random() * CATEGORY_COLORS.length)]
  }
  showDialog.value = true
}

function openEdit(cat: Category, event?: Event) {
  captureDialogTrigger(event)
  editingCategory.value = cat
  form.value = {
    name: cat.name,
    icon: cat.icon || '💳',
    color: cat.color || CATEGORY_COLORS[0]
  }
  showDialog.value = true
}

function closeDialog() {
  showDialog.value = false
  showEmojiPicker.value = false
  editingCategory.value = null
}

async function submitForm() {
  if (saving.value) return
  if (!form.value.name.trim()) {
    toast.warning('请输入分类名称')
    return
  }

  saving.value = true
  try {
    if (editingCategory.value) {
      await categoryApi.update(editingCategory.value.id, {
        name: form.value.name,
        icon: form.value.icon,
        color: form.value.color
      })
      toast.success('更新成功')
    } else {
      await categoryApi.create({
        name: form.value.name,
        type: activeTab.value,
        icon: form.value.icon,
        color: form.value.color
      })
      toast.success('创建成功')
    }
    closeDialog()
    loadCategories()
  } catch (e: any) {
    toast.error(e.message || '保存失败')
  } finally {
    saving.value = false
  }
}

function confirmDelete(id: string, event?: Event) {
  captureDialogTrigger(event)
  deletingId.value = id
  showDeleteModal.value = true
}

async function handleDelete() {
  if (!deletingId.value || deleting.value) return
  deleting.value = true
  try {
    await categoryApi.delete(deletingId.value)
    showDeleteModal.value = false
    deletingId.value = null
    toast.success('删除成功')
    loadCategories()
  } catch (e: any) {
    toast.error(e.message || '删除失败')
  } finally {
    deleting.value = false
  }
}

function selectEmoji(emoji: string) {
  form.value.icon = emoji
  showEmojiPicker.value = false
}
</script>

<template>
  <FinancePage title="分类管理" :context="`${categories.length} 个分类`" :icon="Grid3X3" tone="purple" back-label="返回上一页" @back="goBack">
    <template #actions><button ref="dialogFallback" type="button" aria-label="添加分类" class="finance-icon-button" @click="openCreate"><Plus :size="20" /></button></template>

    <div class="space-y-6">
      <!-- Tabs -->
      <div class="flex gap-1 p-1 bg-gray-100/60 dark:bg-gray-800/60 backdrop-blur-sm rounded-xl">
        <button
          class="flex-1 py-2.5 rounded-lg text-sm font-medium transition-all"
          :class="activeTab === 'expense' ? 'bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm' : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-300'"
          @click="activeTab = 'expense'"
        >
          支出
        </button>
        <button
          class="flex-1 py-2.5 rounded-lg text-sm font-medium transition-all"
          :class="activeTab === 'income' ? 'bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm' : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-300'"
          @click="activeTab = 'income'"
        >
          收入
        </button>
      </div>

      <div v-if="loadFailed" role="alert" class="text-sm text-amber-700">
        分类加载失败。<button class="underline" @click="loadCategories">重试</button>
      </div>
      <!-- Category Grid -->
      <div v-if="loading" class="py-20 text-center text-gray-400">加载中...</div>
      
      <div v-else-if="categories.length > 0" class="grid grid-cols-2 md:grid-cols-3 gap-3">
        <div 
          v-for="cat in categories" 
          :key="cat.id"
          class="bg-white/70 dark:bg-gray-800/70 backdrop-blur-xl rounded-2xl p-4 border border-gray-200/50 dark:border-gray-700/50 shadow-sm hover:shadow-md transition-all duration-200 group"
        >
          <div class="flex justify-between items-start mb-3">
            <div 
              class="w-12 h-12 rounded-xl flex items-center justify-center text-2xl"
              :style="{ backgroundColor: (cat.color || '#999') + '12' }"
            >
              <DynamicIcon :icon="cat.icon || '💳'" :size="24" />
            </div>
            <div v-if="!cat.is_system" class="flex flex-wrap justify-end gap-0.5">
              <button 
                :aria-label="`编辑分类 ${cat.name}`"
                class="min-h-11 min-w-11 flex items-center justify-center text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition"
                @click="openEdit(cat, $event)"
              >
                <Edit2 :size="14" />
              </button>
              <button 
                :aria-label="`删除分类 ${cat.name}`"
                class="min-h-11 min-w-11 flex items-center justify-center text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition"
                @click="confirmDelete(cat.id, $event)"
              >
                <Trash2 :size="14" />
              </button>
            </div>
          </div>
          <div class="font-semibold text-gray-900 dark:text-white text-sm">{{ cat.name }}</div>
          <div v-if="cat.is_system" class="text-[10px] text-gray-400 mt-0.5">系统预设</div>
        </div>
      </div>

      <div v-else-if="!loadFailed" class="py-20 text-center">
        <div class="w-20 h-20 bg-gray-50 dark:bg-gray-700 rounded-full flex items-center justify-center mx-auto mb-4 text-4xl">
          {{ activeTab === 'expense' ? '📦' : '💰' }}
        </div>
        <p class="text-gray-500 mb-6">暂无{{ activeTab === 'expense' ? '支出' : '收入' }}分类</p>
        <button
          class="px-6 py-2.5 bg-primary text-white rounded-xl hover:bg-primary/90 transition font-medium"
          @click="openCreate"
        >
          添加分类
        </button>
      </div>
    </div>

    <!-- Category Dialog -->
    <AppDialog v-if="showDialog" :title="editingCategory ? '编辑分类' : '添加分类'" :busy="saving" :return-focus="dialogTrigger" :fallback-focus="dialogFallback" sheet @close="(saving) || (closeDialog())">
      <fieldset :disabled="saving" class="min-w-0 border-0 p-0 m-0"><div class="space-y-5">
            <!-- Icon & Name -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">分类名称</label>
              <div class="flex items-center gap-3">
                <button
                  aria-label="选择分类图标"
                  class="w-14 h-14 shrink-0 rounded-2xl flex items-center justify-center text-3xl border-2 border-dashed border-gray-200 hover:border-primary/50 hover:bg-primary/5 transition-all"
                  :style="{ backgroundColor: form.color + '15', borderStyle: 'solid', borderColor: form.color + '50' }"
                  @click="showEmojiPicker = !showEmojiPicker"
                >
                  <DynamicIcon :icon="form.icon" :size="28" />
                </button>
                <input name="name" style="min-width: 0; max-width: 100%"
                  v-model="form.name"
                  type="text"
                  placeholder="例如：餐饮、交通"
                  aria-label="分类名称"
                  class="min-w-0 flex-1 h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-hidden focus:ring-2 focus:ring-primary/20 transition-all font-medium text-lg dark:text-white"
                />
              </div>
            </div>

            <!-- Emoji Picker -->
            <div v-if="showEmojiPicker" class="animate-in slide-in-from-top-2 duration-200">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">选择图标</label>
              <div class="grid grid-cols-5 sm:grid-cols-8 gap-1 max-h-48 overflow-y-auto p-2 bg-gray-50 dark:bg-gray-700 rounded-xl">
                <button
                  v-for="(emoji, index) in CATEGORY_EMOJIS"
                  :key="index" :aria-label="`选择图标 ${emoji}`" :aria-pressed="form.icon === emoji"
                  class="aspect-square flex items-center justify-center text-xl rounded-lg hover:bg-white dark:hover:bg-gray-600 hover:shadow-sm transition"
                  :class="form.icon === emoji ? 'bg-white shadow-sm ring-2 ring-primary/30' : ''"
                  @click="selectEmoji(emoji)"
                >
                  {{ emoji }}
                </button>
              </div>
            </div>

            <!-- Color Selection -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">标签颜色</label>
              <div class="flex flex-wrap gap-2">
                <button
                  v-for="color in CATEGORY_COLORS"
                  :key="color" :aria-label="`选择颜色 ${color}`" :aria-pressed="form.color === color"
                  class="w-9 h-9 rounded-full border-2 transition-all flex items-center justify-center"
                  :class="form.color === color ? 'border-gray-900 scale-110' : 'border-transparent hover:scale-105'"
                  :style="{ backgroundColor: color }"
                  @click="form.color = color"
                >
                  <Check v-if="form.color === color" :size="16" class="text-white" />
                </button>
              </div>
            </div>


          </div>
      </fieldset>
      <template #footer><button
              class="w-full h-12 bg-primary text-white rounded-xl font-bold hover:bg-primary/90 transition shadow-lg shadow-primary/20"
              @click="submitForm"
             :disabled="saving">
              保存
            </button></template>
    </AppDialog>

    <!-- Delete Confirm Modal -->
    <AppDialog v-if="showDeleteModal" title="确认删除" :busy="deleting" :return-focus="dialogTrigger" :fallback-focus="dialogFallback" sheet @close="(deleting) || (showDeleteModal = false)">
      <fieldset :disabled="deleting" class="min-w-0 border-0 p-0 m-0"><p class="text-gray-500 text-center text-sm mb-6">删除后该分类下的交易记录将变为「未分类」状态。</p>
      </fieldset>
      <template #footer><button
              class="flex-1 py-3 border border-gray-200 dark:border-gray-600 rounded-xl text-gray-700 dark:text-gray-300 font-medium hover:bg-gray-50 dark:hover:bg-gray-700 transition"
              @click="showDeleteModal = false"
             :disabled="deleting">
              取消
            </button>
            <button
              class="flex-1 py-3 bg-red-500 text-white rounded-xl font-medium hover:bg-red-600 transition shadow-lg shadow-red-500/30"
              @click="handleDelete"
             :disabled="deleting">
              确认删除
            </button></template>
    </AppDialog>
  </FinancePage>
</template>
