<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { Plus, Trash2, Edit2, Check, X } from 'lucide-vue-next'
import { categoryApi, type Category } from '@/api/category'
import { toast } from '@/composables/useToast'
import { CATEGORY_EMOJIS, CATEGORY_COLORS, getCategoryEmoji } from '@/utils/constants'

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

const activeTab = ref<'expense' | 'income'>('expense')
const categories = ref<Category[]>([])
const loading = ref(false)

// Edit/Create State
const editingId = ref<string | null>(null)
const form = ref({
  name: '',
  icon: '',
  color: CATEGORY_COLORS[0]
})
const showForm = ref(false)

onMounted(() => {
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

function switchTab(type: 'expense' | 'income') {
  activeTab.value = type
  cancelEdit()
  loadCategories()
}

function startCreate() {
  editingId.value = null
  form.value = {
    name: '',
    icon: CATEGORY_EMOJIS[0],
    color: CATEGORY_COLORS[Math.floor(Math.random() * CATEGORY_COLORS.length)]
  }
  showForm.value = true
}

function startEdit(cat: Category) {
  editingId.value = cat.id
  form.value = {
    name: cat.name,
    icon: cat.icon || getCategoryEmoji(cat.name),
    color: cat.color || CATEGORY_COLORS[0]
  }
  showForm.value = true
}

function cancelEdit() {
  showForm.value = false
  editingId.value = null
}

async function saveCategory() {
  if (!form.value.name.trim()) {
    toast.warning('请输入分类名称')
    return
  }

  try {
    if (editingId.value) {
      await categoryApi.update(editingId.value, {
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
    cancelEdit()
    loadCategories()
  } catch (e: any) {
    toast.error(e.message || '保存失败')
  }
}

async function deleteCategory(id: string) {
  if (!confirm('确定要删除这个分类吗？')) return
  try {
    await categoryApi.delete(id)
    toast.success('删除成功')
    loadCategories()
  } catch (e: any) {
    toast.error(e.message || '删除失败')
  }
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
          <h3 class="text-xl font-bold text-gray-900">分类管理</h3>
          <button class="p-2 hover:bg-gray-100 rounded-xl transition" @click="close">
            <X :size="20" class="text-gray-500" />
          </button>
        </div>

        <!-- Content -->
        <div class="flex-1 flex flex-col overflow-hidden bg-gray-50">
          <!-- Tabs -->
          <div class="flex p-4 gap-2">
            <button
              class="flex-1 py-2.5 rounded-xl font-medium transition-all shadow-sm"
              :class="activeTab === 'expense' ? 'bg-red-500 text-white shadow-red-200' : 'bg-white text-gray-500 hover:bg-gray-100'"
              @click="switchTab('expense')"
            >
              支出
            </button>
            <button
              class="flex-1 py-2.5 rounded-xl font-medium transition-all shadow-sm"
              :class="activeTab === 'income' ? 'bg-green-500 text-white shadow-green-200' : 'bg-white text-gray-500 hover:bg-gray-100'"
              @click="switchTab('income')"
            >
              收入
            </button>
          </div>

          <!-- Edit Form -->
          <div v-if="showForm" class="mx-4 mb-4 p-4 bg-white rounded-2xl shadow-sm border border-gray-100 animate-in slide-in-from-top-4 duration-200">
            <div class="flex justify-between items-center mb-4">
              <span class="font-bold text-gray-800">{{ editingId ? '编辑分类' : '新建分类' }}</span>
              <button @click="cancelEdit" class="text-xs text-gray-400 hover:text-gray-600">取消</button>
            </div>
            
            <div class="space-y-4">
              <!-- Name Input -->
              <div>
                <label class="block text-xs font-medium text-gray-400 mb-1.5">分类名称</label>
                <div class="flex items-center gap-3">
                  <div 
                    class="w-12 h-12 rounded-xl flex items-center justify-center text-2xl shadow-sm border border-gray-100"
                    :style="{ backgroundColor: form.color + '20' }"
                  >
                    {{ form.icon }}
                  </div>
                  <input
                    v-model="form.name"
                    type="text"
                    placeholder="例如：餐饮、交通"
                    class="flex-1 h-12 px-4 bg-gray-50 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all"
                    autoFocus
                  />
                </div>
              </div>

              <!-- Color Selection -->
              <div>
                <label class="block text-xs font-medium text-gray-400 mb-2">标签颜色</label>
                <div class="flex flex-wrap gap-2">
                  <button
                    v-for="color in CATEGORY_COLORS"
                    :key="color"
                    class="w-8 h-8 rounded-full border-2 transition-all flex items-center justify-center"
                    :class="form.color === color ? 'border-gray-900 scale-110' : 'border-transparent hover:scale-105'"
                    :style="{ backgroundColor: color }"
                    @click="form.color = color"
                  >
                    <Check v-if="form.color === color" :size="14" class="text-white" />
                  </button>
                </div>
              </div>

              <!-- Icon Selection -->
              <div>
                <label class="block text-xs font-medium text-gray-400 mb-2">选择图标</label>
                <div class="grid grid-cols-8 gap-2 max-h-40 overflow-y-auto p-1">
                  <button
                    v-for="emoji in CATEGORY_EMOJIS"
                    :key="emoji"
                    class="aspect-square flex items-center justify-center text-xl rounded-lg hover:bg-gray-50 transition"
                    :class="form.icon === emoji ? 'bg-primary/10 ring-2 ring-primary/30' : ''"
                    @click="form.icon = emoji"
                  >
                    {{ emoji }}
                  </button>
                </div>
              </div>

              <button
                class="w-full py-3 bg-gray-900 text-white rounded-xl font-medium hover:bg-gray-800 transition active:scale-[0.98]"
                @click="saveCategory"
              >
                保存
              </button>
            </div>
          </div>

          <!-- Category List -->
          <div v-else class="flex-1 overflow-y-auto px-4 pb-4 space-y-2">
            <button
              class="w-full py-3 border-2 border-dashed border-gray-200 rounded-xl text-gray-400 font-medium hover:border-primary/50 hover:text-primary hover:bg-primary/5 transition-all flex items-center justify-center gap-2"
              @click="startCreate"
            >
              <Plus :size="18" />
              <span>新建分类</span>
            </button>

            <div v-if="loading" class="py-12 text-center text-gray-400">加载中...</div>
            <div v-else-if="categories.length === 0" class="py-12 text-center text-gray-400">暂无分类</div>
            
            <div
              v-for="cat in categories"
              :key="cat.id"
              class="flex items-center p-3 bg-white rounded-xl border border-gray-100 shadow-sm hover:shadow-md transition-all group"
            >
              <div 
                class="w-10 h-10 rounded-xl flex items-center justify-center text-xl mr-3"
                :style="{ backgroundColor: (cat.color || '#999') + '20' }"
              >
                {{ cat.icon || getCategoryEmoji(cat.name) }}
              </div>
              <div class="flex-1 text-left">
                <div class="font-medium text-gray-900">{{ cat.name }}</div>
                <div v-if="cat.is_system" class="text-xs text-gray-400">系统预设</div>
              </div>
              
              <div v-if="!cat.is_system" class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                <button 
                  class="p-2 text-gray-400 hover:text-primary hover:bg-primary/10 rounded-lg transition"
                  @click="startEdit(cat)"
                >
                  <Edit2 :size="16" />
                </button>
                <button 
                  class="p-2 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition"
                  @click="deleteCategory(cat.id)"
                >
                  <Trash2 :size="16" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
