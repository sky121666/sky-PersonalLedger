<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { X, ChevronDown, Calendar, FileText, CreditCard, Paperclip } from 'lucide-vue-next'
import FileUpload from '@/components/FileUpload.vue'
import { transactionApi, type CreateTransactionParams } from '@/api/transaction'
import { categoryApi, type Category } from '@/api/category'
import { accountApi, type Account } from '@/api/account'
import { toast } from '@/composables/useToast'
import { deleteRemovedAttachments } from '@/utils/attachmentCleanup'
import { getCategoryEmoji } from '@/utils/constants'
import dayjs from 'dayjs'

const props = defineProps<{
  visible: boolean
  editId?: string | null
}>()

const emit = defineEmits<{
  (e: 'update:visible', value: boolean): void
  (e: 'success'): void
}>()

const loading = ref(false)
const categories = ref<Category[]>([])
const accounts = ref<Account[]>([])

const form = ref({
  type: 'expense' as 'income' | 'expense' | 'transfer',
  amount: '',
  account_id: '',
  to_account_id: '',
  category_id: '',
  transaction_date: dayjs().format('YYYY-MM-DDTHH:mm'),
  remark: '',
  images: ''
})

const savedTransactionId = ref<string | null>(null)
const originalImages = ref('')

const typeOptions = [
  { value: 'expense', label: '支出' },
  { value: 'income', label: '收入' },
  { value: 'transfer', label: '转账' }
]

const filteredCategories = computed(() => {
  if (form.value.type === 'transfer') return []
  return categories.value.filter(c => c.type === form.value.type)
})

const isValid = computed(() => {
  const { type, amount, account_id, to_account_id, category_id } = form.value
  if (!amount || parseFloat(amount) <= 0) return false
  if (!account_id) return false
  if (type === 'transfer' && (!to_account_id || to_account_id === account_id)) return false
  if (type !== 'transfer' && !category_id) return false
  return true
})

watch(() => props.visible, async (val) => {
  if (val) {
    await loadData()
    if (props.editId) {
      await loadTransaction()
    } else {
      resetForm()
    }
  }
})

watch(() => form.value.type, () => {
  if (!props.editId) {
    form.value.category_id = ''
    form.value.to_account_id = ''
  }
})

async function loadData() {
  try {
    const [catList, accData] = await Promise.all([
      categoryApi.getList(),
      accountApi.getList()
    ])
    categories.value = catList
    accounts.value = accData.list
    
    if (accounts.value.length > 0 && !form.value.account_id) {
      form.value.account_id = accounts.value[0].id
    }
  } catch (e) {
    console.error('Load data failed:', e)
  }
}

async function loadTransaction() {
  if (!props.editId) return
  try {
    const tx = await transactionApi.getById(props.editId)
    form.value = {
      type: tx.type,
      amount: tx.amount.toString(),
      account_id: tx.account_id,
      to_account_id: tx.to_account_id || '',
      category_id: tx.category_id || '',
      transaction_date: dayjs(tx.transaction_date).format('YYYY-MM-DDTHH:mm'),
      remark: tx.remark || '',
      images: tx.images || ''
    }
    originalImages.value = tx.images || ''
    savedTransactionId.value = tx.id
  } catch (e) {
    console.error('Load transaction failed:', e)
  }
}

function resetForm() {
  form.value = {
    type: 'expense',
    amount: '',
    account_id: accounts.value[0]?.id || '',
    to_account_id: '',
    category_id: '',
    transaction_date: dayjs().format('YYYY-MM-DDTHH:mm'),
    remark: '',
    images: ''
  }
  originalImages.value = ''
  savedTransactionId.value = null
}

function close() {
  emit('update:visible', false)
}

async function submit() {
  if (!isValid.value || loading.value) return
  
  loading.value = true
  try {
    // Convert datetime-local to ISO string
    const txDate = dayjs(form.value.transaction_date).toISOString()
    
    const params: CreateTransactionParams = {
      type: form.value.type,
      amount: parseFloat(form.value.amount),
      account_id: form.value.account_id,
      transaction_date: txDate,
      remark: form.value.remark || undefined,
      images: form.value.images || undefined
    }
    
    if (form.value.type === 'transfer') {
      params.to_account_id = form.value.to_account_id
    } else {
      params.category_id = form.value.category_id
    }
    
    if (props.editId) {
      await transactionApi.update(props.editId, params)
      const failedCleanupPaths = await deleteRemovedAttachments(originalImages.value, form.value.images)
      toast.success(
        failedCleanupPaths.length > 0
          ? `修改成功，但有 ${failedCleanupPaths.length} 个旧附件清理失败`
          : '修改成功'
      )
    } else {
      await transactionApi.create(params)
      toast.success('记账成功')
    }
    
    emit('success')
    close()
  } catch (e: any) {
    toast.error(e.message || '保存失败')
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <Teleport to="body">
    <div v-if="visible" class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="close"></div>
      
      <div class="relative bg-white/90 dark:bg-gray-800/90 backdrop-blur-2xl rounded-3xl w-full max-w-md max-h-[90vh] flex flex-col shadow-2xl overflow-hidden animate-in zoom-in-95 duration-200 border border-white/20 dark:border-gray-700/50">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 bg-transparent z-10">
          <button class="p-2 hover:bg-gray-100/50 rounded-xl transition opacity-0 cursor-default">
            <X :size="20" />
          </button>
          
          <!-- Segmented Control -->
          <div class="flex bg-gray-100/80 dark:bg-gray-700/80 p-1 rounded-xl backdrop-blur-sm">
            <button
              v-for="opt in typeOptions"
              :key="opt.value"
              class="px-4 py-1.5 text-sm font-medium rounded-lg transition-all duration-200"
              :class="form.type === opt.value ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-white shadow-sm' : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200'"
              @click="form.type = opt.value as any"
            >
              {{ opt.label }}
            </button>
          </div>

          <button class="p-2 hover:bg-gray-100/50 dark:hover:bg-gray-700/50 rounded-xl transition" @click="close">
            <X :size="20" class="text-gray-500" />
          </button>
        </div>
        
        <!-- Form Content -->
        <div class="flex-1 overflow-y-auto p-6 space-y-6">
          <!-- Amount Input -->
          <div>
            <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">金额</label>
            <div class="relative group">
              <span class="absolute left-4 top-1/2 -translate-y-1/2 text-2xl font-bold text-gray-400 transition-colors group-focus-within:text-primary">¥</span>
              <input
                v-model="form.amount"
                type="number"
                step="0.01"
                placeholder="0.00"
                class="w-full h-16 pl-10 pr-4 text-3xl font-bold bg-gray-50/50 dark:bg-gray-700/50 dark:text-white rounded-2xl border-2 border-transparent outline-none focus:bg-white dark:focus:bg-gray-600 focus:border-primary/20 transition-all placeholder:text-gray-300 dark:placeholder:text-gray-500"
                autoFocus
              />
            </div>
          </div>
          
          <!-- Category Grid -->
          <div v-if="form.type !== 'transfer'">
            <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">选择分类</label>
            <div class="grid grid-cols-5 gap-3">
              <button
                v-for="cat in filteredCategories"
                :key="cat.id"
                class="flex flex-col items-center gap-1 group"
                @click="form.category_id = cat.id"
              >
                <div 
                  class="w-12 h-12 rounded-2xl flex items-center justify-center text-xl transition-all duration-200 border-2"
                  :class="form.category_id === cat.id 
                    ? 'scale-110 shadow-lg border-primary' 
                    : 'border-transparent hover:scale-105'"
                  :style="{ 
                    backgroundColor: form.category_id === cat.id 
                      ? (cat.color || '#007AFF') + '20' 
                      : (cat.color || '#94a3b8') + '15'
                  }"
                >
                  {{ getCategoryEmoji(cat.name, cat.icon) }}
                </div>
                <span 
                  class="text-[10px] font-medium truncate w-full text-center transition-colors"
                  :class="form.category_id === cat.id ? 'text-primary' : 'text-gray-500'"
                >
                  {{ cat.name }}
                </span>
              </button>
            </div>
          </div>
          
          <!-- Account Selection -->
          <div class="space-y-4">
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
                {{ form.type === 'transfer' ? '转出账户' : '账户' }}
              </label>
              <div class="relative">
                <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
                  <CreditCard :size="18" />
                </div>
                <select
                  v-model="form.account_id"
                  class="w-full h-12 pl-11 pr-10 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none appearance-none focus:ring-2 focus:ring-primary/20 font-medium text-gray-700 dark:text-white"
                >
                  <option value="" disabled>请选择账户</option>
                  <option v-for="acc in accounts" :key="acc.id" :value="acc.id">
                    {{ acc.name }}
                  </option>
                </select>
                <ChevronDown class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" :size="18" />
              </div>
            </div>

            <!-- Transfer To Account -->
            <div v-if="form.type === 'transfer'" class="animate-in slide-in-from-top-2">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">转入账户</label>
              <div class="relative">
                <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
                  <CreditCard :size="18" />
                </div>
                <select
                  v-model="form.to_account_id"
                  class="w-full h-12 pl-11 pr-10 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none appearance-none focus:ring-2 focus:ring-primary/20 font-medium text-gray-700 dark:text-white"
                >
                  <option value="" disabled>请选择账户</option>
                  <option
                    v-for="acc in accounts"
                    :key="acc.id"
                    :value="acc.id"
                    :disabled="acc.id === form.account_id"
                  >
                    {{ acc.name }}
                  </option>
                </select>
                <ChevronDown class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" :size="18" />
              </div>
            </div>
          </div>
          
          <!-- Date & Remark -->
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">日期</label>
              <div class="relative">
                <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
                  <Calendar :size="18" />
                </div>
                <input
                  v-model="form.transaction_date"
                  type="datetime-local"
                  class="w-full h-12 pl-11 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 font-medium text-gray-700 dark:text-white"
                />
              </div>
            </div>
            
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">备注</label>
              <div class="relative">
                <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
                  <FileText :size="18" />
                </div>
                <input
                  v-model="form.remark"
                  type="text"
                  placeholder="选填"
                  class="w-full h-12 pl-11 pr-4 bg-gray-50 dark:bg-gray-700 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 font-medium text-gray-700 dark:text-white"
                />
              </div>
            </div>
          </div>

          <!-- Attachments -->
          <div v-if="savedTransactionId || props.editId">
            <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
              <Paperclip :size="14" class="inline mr-1" />附件
            </label>
            <FileUpload
              v-model="form.images"
              category="transactions"
              :ref-id="savedTransactionId || props.editId || ''"
              :max-files="5"
            />
          </div>
          <div v-else class="text-xs text-gray-400 italic">
            保存后可添加附件
          </div>
        </div>
        
        <!-- Footer -->
        <div class="p-6 border-t border-gray-100/50 dark:border-gray-700/50 bg-white/50 dark:bg-gray-800/50 backdrop-blur-md">
          <button
            class="w-full h-12 rounded-xl font-bold text-lg transition-all shadow-lg shadow-primary/20 active:scale-[0.98]"
            :class="isValid ? 'bg-primary text-white hover:bg-primary/90' : 'bg-gray-100/50 dark:bg-gray-700/50 text-gray-400 cursor-not-allowed shadow-none'"
            :disabled="!isValid || loading"
            @click="submit"
          >
            {{ loading ? '保存中...' : '保存记录' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
