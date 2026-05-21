<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronLeft, Plus, Trash2, Edit2, Check, X, Grid3X3 } from 'lucide-vue-next'
import { categoryApi, type Category } from '@/api/category'
import { toast } from '@/composables/useToast'
import DynamicIcon from '@/components/DynamicIcon.vue'

const router = useRouter()

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

onMounted(() => {
  loadCategories()
})

watch(activeTab, () => {
  loadCategories()
})

async function loadCategories() {
  loading.value = true
  try {
    categories.value = await categoryApi.getList(activeTab.value)
  } catch (e: any) {
    toast.error('加载分类失败')
  } finally {
    loading.value = false
  }
}

function goBack() {
  router.back()
}

function openCreate() {
  editingCategory.value = null
  form.value = {
    name: '',
    icon: activeTab.value === 'expense' ? '🍽️' : '💰',
    color: CATEGORY_COLORS[Math.floor(Math.random() * CATEGORY_COLORS.length)]
  }
  showDialog.value = true
}

function openEdit(cat: Category) {
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
  if (!form.value.name.trim()) {
    toast.warning('请输入分类名称')
    return
  }

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
  }
}

function confirmDelete(id: string) {
  deletingId.value = id
  showDeleteModal.value = true
}

async function handleDelete() {
  if (!deletingId.value) return
  try {
    await categoryApi.delete(deletingId.value)
    showDeleteModal.value = false
    deletingId.value = null
    toast.success('删除成功')
    loadCategories()
  } catch (e: any) {
    toast.error(e.message || '删除失败')
  }
}

function selectEmoji(emoji: string) {
  form.value.icon = emoji
  showEmojiPicker.value = false
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
          <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-purple-500 to-purple-600 flex items-center justify-center shadow-lg shadow-purple-500/20">
            <Grid3X3 class="text-white" :size="28" />
          </div>
          <div>
            <h1 class="text-xl font-bold text-gray-900 dark:text-white">分类管理</h1>
            <div class="text-sm text-gray-500 dark:text-gray-400 mt-0.5">{{ categories.length }} 个分类</div>
          </div>
        </div>
        <button
          class="p-2.5 bg-gray-100/50 dark:bg-white/5 text-gray-400 hover:text-purple-500 hover:bg-purple-50 dark:hover:bg-purple-900/20 rounded-full transition"
          @click="openCreate"
        >
          <Plus :size="20" />
        </button>
      </div>
    </div>

    <div class="max-w-3xl mx-auto px-4 md:px-8 py-6 space-y-6">
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
            <div v-if="!cat.is_system" class="flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
              <button 
                class="p-1.5 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition"
                @click="openEdit(cat)"
              >
                <Edit2 :size="14" />
              </button>
              <button 
                class="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition"
                @click="confirmDelete(cat.id)"
              >
                <Trash2 :size="14" />
              </button>
            </div>
          </div>
          <div class="font-semibold text-gray-900 dark:text-white text-sm">{{ cat.name }}</div>
          <div v-if="cat.is_system" class="text-[10px] text-gray-400 mt-0.5">系统预设</div>
        </div>
      </div>

      <div v-else class="py-20 text-center">
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
    <Teleport to="body">
      <div v-if="showDialog" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="closeDialog"></div>
        <div class="relative bg-white/90 dark:bg-gray-800/90 backdrop-blur-2xl rounded-3xl w-full max-w-md shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-gray-700/50">
          <div class="flex items-center justify-between p-6 border-b border-gray-100/50 dark:border-gray-700/50">
            <h3 class="text-lg font-bold dark:text-white">{{ editingCategory ? '编辑分类' : '添加分类' }}</h3>
            <button class="p-2 hover:bg-gray-100/50 dark:hover:bg-gray-700/50 rounded-xl transition" @click="closeDialog">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div class="p-6 space-y-5">
            <!-- Icon & Name -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">分类名称</label>
              <div class="flex items-center gap-3">
                <button
                  class="w-14 h-14 rounded-2xl flex items-center justify-center text-3xl border-2 border-dashed border-gray-200 hover:border-primary/50 hover:bg-primary/5 transition-all"
                  :style="{ backgroundColor: form.color + '15', borderStyle: 'solid', borderColor: form.color + '50' }"
                  @click="showEmojiPicker = !showEmojiPicker"
                >
                  <DynamicIcon :icon="form.icon" :size="28" />
                </button>
                <input
                  v-model="form.name"
                  type="text"
                  placeholder="例如：餐饮、交通"
                  class="flex-1 h-12 px-4 bg-gray-50/50 dark:bg-gray-700/50 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-lg dark:text-white"
                />
              </div>
            </div>

            <!-- Emoji Picker -->
            <div v-if="showEmojiPicker" class="animate-in slide-in-from-top-2 duration-200">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">选择图标</label>
              <div class="grid grid-cols-10 gap-1 max-h-48 overflow-y-auto p-2 bg-gray-50 dark:bg-gray-700 rounded-xl">
                <button
                  v-for="emoji in CATEGORY_EMOJIS"
                  :key="emoji"
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
                  :key="color"
                  class="w-9 h-9 rounded-full border-2 transition-all flex items-center justify-center"
                  :class="form.color === color ? 'border-gray-900 scale-110' : 'border-transparent hover:scale-105'"
                  :style="{ backgroundColor: color }"
                  @click="form.color = color"
                >
                  <Check v-if="form.color === color" :size="16" class="text-white" />
                </button>
              </div>
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
          <h3 class="text-lg font-bold text-center mb-2 dark:text-white">确认删除</h3>
          <p class="text-gray-500 text-center text-sm mb-6">删除后该分类下的交易记录将变为「未分类」状态。</p>
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
