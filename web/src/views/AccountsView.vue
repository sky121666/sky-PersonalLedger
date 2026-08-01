<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { accountApi, type Account, type CreateAccountParams, type AccountType } from '@/api/account'
import { Plus, X, ChevronDown, Trash2, Archive, Wallet, CreditCard, ArchiveRestore, ChevronLeft, Pen, ScrollText } from 'lucide-vue-next'
import { useRouter } from 'vue-router'
import { accountSummaryTotals } from '@/utils/accountSummary'

const router = useRouter()
import { toast } from '@/composables/useToast'
import DynamicIcon from '@/components/DynamicIcon.vue'
import Hover3D from '@/components/Hover3D.vue'

const accounts = ref<Account[]>([])
const archivedAccounts = ref<Account[]>([])
const totalAssets = ref(0)
const totalLiabilities = ref(0)
const showArchived = ref(false)

const showDialog = ref(false)
const editingAccount = ref<Account | null>(null)
const showDeleteModal = ref(false)
const deletingId = ref<string | null>(null)

const form = ref({
  name: '',
  type: 'cash',
  icon: '',
  color: '#3B82F6',
  initial_balance: '0'
})

const colorOptions = [
  '#EF4444', '#F97316', '#F59E0B', '#84CC16', '#10B981',
  '#06B6D4', '#3B82F6', '#6366F1', '#8B5CF6', '#EC4899',
  '#1677FF', '#07C160', '#1F2937', '#4B5563'
]

const accountTypes = [
  // 现金
  { value: 'cash', label: '现金', icon: 'banknote' },
  // 银行
  { value: 'bank_card', label: '银行卡', icon: 'landmark' },
  { value: 'savings', label: '储蓄卡', icon: 'credit-card' },
  // 第三方支付
  { value: 'alipay', label: '支付宝', icon: 'circle-dot' },
  { value: 'wechat', label: '微信', icon: 'message-circle' },
  { value: 'qq_pay', label: 'QQ钱包', icon: 'message-square' },
  { value: 'jd_pay', label: '京东钱包', icon: 'shopping-bag' },
  { value: 'apple_pay', label: 'Apple Pay', icon: 'smartphone' },
  // 信贷/负债
  { value: 'credit', label: '信用卡', icon: 'credit-card' },
  { value: 'huabei', label: '花呗', icon: 'flower-2' },
  { value: 'baitiao', label: '白条', icon: 'scroll' },
  { value: 'loan', label: '贷款', icon: 'building-2' },
  { value: 'mortgage', label: '房贷', icon: 'home' },
  { value: 'car_loan', label: '车贷', icon: 'car' },
  { value: 'consumer_loan', label: '消费贷', icon: 'wallet' },
  { value: 'payable', label: '应付款', icon: 'wallet' },
  { value: 'receivable', label: '应收款', icon: 'wallet' },
  // 投资
  { value: 'investment', label: '投资账户', icon: 'trending-up' },
  { value: 'fund', label: '基金', icon: 'pie-chart' },
  { value: 'stock', label: '股票', icon: 'bar-chart-2' },
  { value: 'crypto', label: '数字货币', icon: 'bitcoin' },
  // 其他
  { value: 'prepaid', label: '充值卡', icon: 'ticket' },
  { value: 'other', label: '其他', icon: 'wallet' }
]

const netAssets = computed(() => totalAssets.value - totalLiabilities.value)

const isFormValid = computed(() => {
  return form.value.name.trim() !== ''
})

onMounted(() => {
  loadAccounts()
})

async function loadAccounts() {
  try {
    const allData = await accountApi.getList(true)
    accounts.value = allData.list.filter(a => !a.is_archived)
    archivedAccounts.value = allData.list.filter(a => a.is_archived)
    const totals = accountSummaryTotals(allData)
    totalAssets.value = totals.totalAssets
    totalLiabilities.value = totals.totalLiabilities
  } catch (e) {
    console.error('Load accounts failed:', e)
  }
}

function formatMoney(value: number) {
  return value.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

function getAccountIcon(type: string) {
  const found = accountTypes.find(t => t.value === type)
  return found?.icon || 'wallet'
}

function openCreate() {
  editingAccount.value = null
  const defaultType = accountTypes[0]
  form.value = { 
    name: '', 
    type: 'cash', 
    icon: defaultType.icon,
    color: '#3B82F6',
    initial_balance: '0' 
  }
  showDialog.value = true
}

function openEdit(account: Account) {
  editingAccount.value = account
  form.value = {
    name: account.name,
    type: account.type,
    icon: account.icon || getAccountIcon(account.type),
    color: account.color || '#3B82F6',
    initial_balance: account.initial_balance.toString()
  }
  showDialog.value = true
}

function closeDialog() {
  showDialog.value = false
  editingAccount.value = null
}

async function submitForm() {
  if (!isFormValid.value) return
  
  try {
    const params: CreateAccountParams = {
      name: form.value.name,
      type: form.value.type as AccountType,
      icon: form.value.icon,
      color: form.value.color,
      initial_balance: parseFloat(form.value.initial_balance) || 0
    }
    
    if (editingAccount.value) {
      await accountApi.update(editingAccount.value.id, { 
        name: params.name,
        icon: params.icon,
        color: params.color
      })
      toast.success('修改成功')
    } else {
      await accountApi.create(params)
      toast.success('添加成功')
    }
    
    closeDialog()
    loadAccounts()
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
    await accountApi.delete(deletingId.value)
    showDeleteModal.value = false
    deletingId.value = null
    toast.success('删除成功')
    loadAccounts()
  } catch (e: any) {
    const msg = e.message || ''
    if (msg.includes('non-zero balance')) {
      toast.error('无法删除余额不为零的账户，请先归档')
    } else {
      toast.error(msg || '删除失败')
    }
  }
}

async function toggleArchive(account: Account) {
  try {
    await accountApi.archive(account.id, !account.is_archived)
    toast.success(account.is_archived ? '已恢复账户' : '已归档')
    loadAccounts()
  } catch (e: any) {
    toast.error(e.message || '操作失败')
  }
}

const displayAccounts = computed(() => showArchived.value ? archivedAccounts.value : accounts.value)
</script>

<template>
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black pb-8">
    <!-- Header -->
    <div class="bg-white/70 dark:bg-[#1C1C1E]/70 pt-4 pb-4 px-4 md:px-8 sticky top-0 z-30 backdrop-blur-xl border-b border-gray-200/50 dark:border-white/10">
      <div class="max-w-3xl mx-auto flex items-center justify-between">
        <div class="flex items-center gap-4">
          <button @click="router.back()" class="p-2 -ml-2 text-gray-500 hover:bg-gray-100 dark:hover:bg-white/10 rounded-xl transition">
            <ChevronLeft :size="20" />
          </button>
          <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center shadow-lg shadow-blue-500/20">
            <Wallet class="text-white" :size="28" />
          </div>
          <div>
            <h1 class="text-xl font-bold text-gray-900 dark:text-white">我的钱包</h1>
            <div class="text-sm text-gray-500 dark:text-gray-400 mt-0.5">{{ accounts.length }} 个账户</div>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <button
            class="p-2.5 rounded-full transition"
            :class="showArchived ? 'bg-yellow-50 dark:bg-yellow-900/30 text-yellow-600' : 'bg-gray-100/50 dark:bg-white/5 text-gray-400 hover:text-gray-600'"
            @click="showArchived = !showArchived"
          >
            <Archive :size="20" />
          </button>
          <button
            v-if="!showArchived"
            class="p-2.5 bg-gray-100/50 dark:bg-white/5 text-gray-400 hover:text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-full transition"
            @click="openCreate"
          >
            <Plus :size="20" />
          </button>
        </div>
      </div>
    </div>

    <div class="max-w-3xl mx-auto px-4 md:px-8 py-6 space-y-6">
      <!-- Asset Overview Cards -->
      <div class="grid grid-cols-3 gap-2 md:gap-4">
        <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-2xl p-3 md:p-4 flex flex-col items-center justify-center gap-0.5 shadow-sm border border-white/40 dark:border-white/5">
          <div class="text-base md:text-2xl font-bold font-nums text-gray-900 dark:text-white truncate w-full text-center">¥{{ formatMoney(netAssets) }}</div>
          <div class="text-[10px] md:text-xs text-gray-500">净资产</div>
        </div>
        <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-2xl p-3 md:p-4 flex flex-col items-center justify-center gap-0.5 shadow-sm border border-white/40 dark:border-white/5">
          <div class="text-base md:text-2xl font-bold font-nums text-green-600 dark:text-green-400 truncate w-full text-center">¥{{ formatMoney(totalAssets) }}</div>
          <div class="text-[10px] md:text-xs text-gray-500">总资产</div>
        </div>
        <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-2xl p-3 md:p-4 flex flex-col items-center justify-center gap-0.5 shadow-sm border border-white/40 dark:border-white/5">
          <div class="text-base md:text-2xl font-bold font-nums text-red-500 dark:text-red-400 truncate w-full text-center">¥{{ formatMoney(totalLiabilities) }}</div>
          <div class="text-[10px] md:text-xs text-gray-500">总负债</div>
        </div>
      </div>

      <!-- Section Title -->
      <div class="flex items-center justify-between pt-2">
        <h2 class="text-sm font-bold text-gray-900 dark:text-white px-1">{{ showArchived ? '已归档账户' : '我的账户' }}</h2>
        <span class="text-xs text-gray-400">{{ displayAccounts.length }} 张卡片</span>
      </div>

      <!-- Account Cards Grid -->
      <div v-if="displayAccounts.length > 0" class="grid grid-cols-1 sm:grid-cols-2 gap-6">
        <Hover3D
          v-for="account in displayAccounts" 
          :key="account.id"
          :intensity="15"
          :scale="1.03"
        >
          <div 
            class="group relative aspect-[1.586/1] rounded-[22px] p-5 flex flex-col justify-between overflow-hidden card-premium"
            :style="{ 
              background: `linear-gradient(145deg, 
                color-mix(in srgb, ${account.color} 100%, white 15%) 0%, 
                ${account.color} 35%, 
                color-mix(in srgb, ${account.color} 100%, black 20%) 100%)`,
              boxShadow: `
                0 25px 50px -12px ${account.color}40,
                0 12px 25px -8px ${account.color}30,
                inset 0 1px 1px rgba(255,255,255,0.2),
                inset 0 -1px 1px rgba(0,0,0,0.1)
              `
            }"
          >
            <!-- Metallic Texture Overlay -->
            <div class="absolute inset-0 opacity-[0.08] pointer-events-none" 
                 style="background: repeating-linear-gradient(
                   90deg,
                   transparent,
                   transparent 1px,
                   rgba(255,255,255,0.03) 1px,
                   rgba(255,255,255,0.03) 2px
                 );"></div>
            <!-- Glass Shine Effect -->
            <div class="absolute inset-0 bg-gradient-to-br from-white/30 via-white/5 to-transparent pointer-events-none"></div>
            <div class="absolute inset-0 bg-gradient-to-t from-black/20 via-transparent to-transparent pointer-events-none"></div>
            <!-- Top Light Reflection -->
            <div class="absolute top-0 left-0 right-0 h-1/3 bg-gradient-to-b from-white/15 to-transparent pointer-events-none"></div>
            <!-- Corner Highlights -->
            <div class="absolute -top-32 -right-32 w-64 h-64 bg-white/15 rounded-full blur-3xl pointer-events-none"></div>
            <div class="absolute -bottom-20 -left-20 w-48 h-48 bg-black/15 rounded-full blur-3xl pointer-events-none"></div>
            <!-- Edge Highlight -->
            <div class="absolute inset-0 rounded-[22px] pointer-events-none" style="box-shadow: inset 0 0 0 1px rgba(255,255,255,0.15);"></div>

            <!-- Top Row: Icon & Name -->
            <div class="relative z-10 flex items-start justify-between text-white gap-2">
              <div class="flex items-center gap-3 min-w-0 flex-1">
                <div class="w-11 h-11 rounded-xl bg-white/15 backdrop-blur-xl flex items-center justify-center shadow-lg border border-white/20 flex-shrink-0"
                     style="box-shadow: 0 6px 12px rgba(0,0,0,0.12), inset 0 1px 1px rgba(255,255,255,0.2);">
                  <DynamicIcon :icon="account.icon || getAccountIcon(account.type)" :size="20" class="drop-shadow-md" />
                </div>
                <div class="min-w-0 flex-1">
                  <div class="font-bold text-lg leading-snug drop-shadow-md truncate" style="text-shadow: 0 2px 4px rgba(0,0,0,0.2);">{{ account.name }}</div>
                  <div class="text-[10px] text-white/60 uppercase tracking-widest mt-0.5 font-medium">{{ account.type.replace('_', ' ').toUpperCase() }}</div>
                </div>
              </div>
              
              <!-- Action Buttons (Top Right) - Always visible on mobile -->
              <div class="flex gap-1.5 md:opacity-0 md:group-hover:opacity-100 transition-all duration-300 flex-shrink-0">
                <button 
                  class="p-2.5 bg-white/20 active:bg-white/40 md:hover:bg-white/30 rounded-xl text-white backdrop-blur-xl transition-all active:scale-95 md:hover:scale-110 border border-white/25 shadow-md"
                  @click.stop="router.push(`/account-logs/${account.id}`)"
                  title="查看流水"
                >
                  <ScrollText :size="14" />
                </button>
                <button 
                  class="p-2.5 bg-white/20 active:bg-white/40 md:hover:bg-white/30 rounded-xl text-white backdrop-blur-xl transition-all active:scale-95 md:hover:scale-110 border border-white/25 shadow-md"
                  @click.stop="openEdit(account)"
                >
                  <Pen :size="14" />
                </button>
                <button 
                  class="p-2.5 bg-white/20 active:bg-white/40 md:hover:bg-white/30 rounded-xl text-white backdrop-blur-xl transition-all active:scale-95 md:hover:scale-110 border border-white/25 shadow-md"
                  @click.stop="toggleArchive(account)"
                >
                  <ArchiveRestore v-if="account.is_archived" :size="14" />
                  <Archive v-else :size="14" />
                </button>
                <button 
                  class="p-2.5 bg-white/20 active:bg-red-500 md:hover:bg-red-500 rounded-xl text-white backdrop-blur-xl transition-all active:scale-95 md:hover:scale-110 border border-white/25 shadow-md"
                  @click.stop="confirmDelete(account.id)"
                >
                  <Trash2 :size="14" />
                </button>
              </div>
            </div>

            <!-- Middle: Chip (Decorative) -->
            <div class="relative z-10">
              <div class="w-14 h-10 rounded-lg flex items-center justify-center relative overflow-hidden"
                   style="background: linear-gradient(145deg, #fcd34d 0%, #f59e0b 50%, #b45309 100%);
                          box-shadow: 0 4px 8px rgba(0,0,0,0.2), inset 0 1px 2px rgba(255,255,255,0.4), inset 0 -1px 2px rgba(0,0,0,0.2);">
                <div class="absolute inset-0 bg-[linear-gradient(110deg,transparent_25%,rgba(255,255,255,0.4)_50%,transparent_75%)] animate-shimmer"></div>
                <!-- Chip Pattern -->
                <div class="grid grid-cols-4 gap-[2px] w-8">
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                  <div class="w-[5px] h-[5px] bg-gradient-to-br from-amber-600 to-amber-800 rounded-[1px]"></div>
                </div>
              </div>
            </div>

            <!-- Bottom: Balance -->
            <div class="relative z-10 text-white">
              <div class="flex items-end justify-between">
                <div>
                  <div class="text-[11px] text-white/60 mb-1.5 uppercase tracking-widest font-semibold drop-shadow-sm">Current Balance</div>
                  <div class="text-[28px] font-bold font-nums tracking-tight" style="text-shadow: 0 2px 8px rgba(0,0,0,0.25);">
                    <span class="text-lg align-top opacity-70 mr-0.5">¥</span>{{ formatMoney(account.current_balance) }}
                  </div>
                </div>
                <!-- Logo/Type indicator bottom right -->
                <div class="opacity-25 drop-shadow-lg">
                  <CreditCard :size="32" stroke-width="1.5" />
                </div>
              </div>
            </div>
          </div>
        </Hover3D>

        <!-- Add Card Button (Card Style) -->
        <Hover3D
          v-if="!showArchived"
          :intensity="8"
          :scale="1.02"
          :shine="false"
        >
          <button 
            class="aspect-[1.586/1] w-full rounded-[22px] border-2 border-dashed border-gray-300/80 dark:border-gray-600/50 flex flex-col items-center justify-center gap-4 text-gray-400 hover:text-blue-500 hover:border-blue-400/50 hover:bg-blue-50/50 dark:hover:bg-blue-900/10 transition-all duration-300 group bg-white/50 dark:bg-white/5 backdrop-blur-sm"
            @click="openCreate"
          >
            <div class="w-14 h-14 rounded-2xl bg-gray-100 dark:bg-gray-800 flex items-center justify-center group-hover:bg-blue-100 dark:group-hover:bg-blue-900/30 transition-all duration-300 shadow-sm group-hover:shadow-lg group-hover:shadow-blue-500/10">
              <Plus :size="28" class="group-hover:scale-110 transition-transform duration-300" stroke-width="1.5" />
            </div>
            <div class="text-center">
              <div class="font-semibold text-sm">添加新账户</div>
              <div class="text-xs text-gray-400 mt-0.5">银行卡 / 支付宝 / 微信...</div>
            </div>
          </button>
        </Hover3D>
      </div>

      <!-- Empty State -->
      <div v-else class="py-24 text-center">
        <div class="w-24 h-24 bg-gradient-to-br from-gray-100 to-gray-50 dark:from-gray-800 dark:to-gray-900 rounded-3xl flex items-center justify-center mx-auto mb-6 text-gray-400 shadow-lg shadow-gray-200/50 dark:shadow-black/30">
          <Archive v-if="showArchived" :size="40" stroke-width="1.5" />
          <Wallet v-else :size="40" stroke-width="1.5" />
        </div>
        <h3 class="text-lg font-bold text-gray-700 dark:text-gray-300 mb-2">{{ showArchived ? '暂无归档账户' : '开始管理您的资产' }}</h3>
        <p class="text-sm text-gray-400 mb-8 max-w-xs mx-auto">{{ showArchived ? '归档的账户会显示在这里' : '添加银行卡、支付宝、微信等账户，轻松追踪每一笔收支' }}</p>
        <button
          v-if="!showArchived"
          class="px-8 py-3 bg-gradient-to-r from-blue-500 to-blue-600 text-white rounded-2xl hover:shadow-lg hover:shadow-blue-500/30 hover:-translate-y-0.5 transition-all font-semibold text-sm"
          @click="openCreate"
        >
          <span class="flex items-center gap-2">
            <Plus :size="18" />
            添加第一张卡
          </span>
        </button>
        <button
          v-else
          class="px-6 py-2.5 border border-gray-200 dark:border-gray-600 text-gray-600 dark:text-gray-300 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-800 transition font-medium text-sm"
          @click="showArchived = false"
        >
          返回钱包
        </button>
      </div>
    </div>

    <!-- Account Dialog -->
    <Teleport to="body">
      <div v-if="showDialog" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="closeDialog"></div>
        <div class="relative bg-white/90 dark:bg-[#1C1C1E]/90 backdrop-blur-2xl rounded-[24px] w-full max-w-md shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-white/10 overflow-hidden">
          <div class="flex items-center justify-between p-6 border-b border-gray-100/50 dark:border-white/10 bg-transparent">
            <h3 class="text-lg font-bold text-gray-900 dark:text-white">{{ editingAccount ? '编辑卡片' : '添加新卡' }}</h3>
            <button class="p-2 hover:bg-black/5 dark:hover:bg-white/10 rounded-full transition" @click="closeDialog">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div class="p-6 space-y-5 max-h-[80vh] overflow-y-auto scrollbar-hide">
            <!-- Preview Card -->
            <div 
              class="aspect-[1.586/1] rounded-[16px] p-5 flex flex-col justify-between shadow-lg mb-6 transition-colors duration-300"
              :style="{ background: `linear-gradient(135deg, ${form.color} 0%, ${form.color}dd 100%)` }"
            >
               <div class="flex items-center gap-3 text-white">
                  <div class="w-8 h-8 rounded-full bg-white/20 flex items-center justify-center border border-white/10">
                    <DynamicIcon :icon="form.icon || getAccountIcon(form.type)" :size="16" />
                  </div>
                  <div>
                    <div class="font-bold text-sm">{{ form.name || '卡片名称' }}</div>
                    <div class="text-[9px] text-white/70 uppercase">{{ accountTypes.find(t => t.value === form.type)?.label || '账户类型' }}</div>
                  </div>
               </div>
               <div class="text-white text-right">
                  <div class="text-[9px] text-white/60">余额</div>
                  <div class="text-xl font-bold font-nums">¥ {{ form.initial_balance || '0.00' }}</div>
               </div>
            </div>

            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">卡片名称</label>
              <input
                v-model="form.name"
                type="text"
                placeholder="例如：招商银行"
                class="w-full h-12 px-4 bg-gray-100 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-gray-900 dark:text-white placeholder:text-gray-400"
              />
            </div>
            
            <div v-if="!editingAccount">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">账户类型</label>
              <div class="relative">
                <select
                  v-model="form.type"
                  class="w-full h-12 px-4 bg-gray-100 dark:bg-black/30 rounded-xl border-0 outline-none appearance-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-gray-900 dark:text-white"
                >
                  <option v-for="t in accountTypes" :key="t.value" :value="t.value">
                    {{ t.label }}
                  </option>
                </select>
                <ChevronDown class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" :size="20" />
              </div>
            </div>
            
            <!-- Icon Selection -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">图标</label>
              <div class="flex items-center gap-3">
                <div 
                  class="w-12 h-12 rounded-xl flex items-center justify-center text-xl shadow-sm transition-colors duration-300"
                  :style="{ backgroundColor: form.color, color: '#fff' }"
                >
                  <DynamicIcon :icon="form.icon" :size="24" />
                </div>
                <input
                  v-model="form.icon"
                  type="text"
                  placeholder="图标名称或 emoji"
                  class="flex-1 h-12 px-4 bg-gray-100 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-gray-900 dark:text-white placeholder:text-gray-400"
                />
              </div>
            </div>

            <!-- Color Selection -->
            <div>
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">卡片颜色</label>
              <div class="flex flex-wrap gap-3">
                <button
                  v-for="c in colorOptions"
                  :key="c"
                  type="button"
                  class="w-8 h-8 rounded-full transition-all shadow-sm"
                  :class="form.color === c ? 'ring-2 ring-offset-2 ring-gray-400 scale-110' : 'hover:scale-110'"
                  :style="{ backgroundColor: c }"
                  @click="form.color = c"
                />
              </div>
            </div>

            <div v-if="!editingAccount">
              <label class="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">初始余额</label>
              <div class="relative">
                <span class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold">¥</span>
                <input
                  v-model="form.initial_balance"
                  type="number"
                  step="0.01"
                  placeholder="0.00"
                  class="w-full h-12 pl-8 pr-4 bg-gray-100 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-bold text-lg text-gray-900 dark:text-white"
                />
              </div>
            </div>

            <button
              class="w-full h-12 bg-primary text-white rounded-full font-bold hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition shadow-lg shadow-primary/20 mt-4"
              :class="isFormValid ? 'bg-primary text-white hover:bg-primary/90' : 'bg-gray-100 text-gray-400 cursor-not-allowed'"
              :disabled="!isFormValid"
              @click="submitForm"
            >
              保存卡片
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Delete Confirm Modal -->
    <Teleport to="body">
      <div v-if="showDeleteModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showDeleteModal = false"></div>
        <div class="relative bg-white/90 dark:bg-[#1C1C1E]/90 backdrop-blur-xl rounded-[20px] p-6 w-[280px] shadow-2xl animate-in zoom-in-95 duration-200 text-center">
          <h3 class="text-lg font-bold text-gray-900 dark:text-white mb-2">确认销户</h3>
          <p class="text-[13px] text-gray-500 dark:text-gray-400 mb-6 leading-relaxed">删除账户后，该账户下的所有交易记录也将被一并删除，且无法恢复。</p>
          <div class="flex gap-3 justify-center border-t border-gray-200/50 dark:border-white/10 pt-4 -mx-6 -mb-2">
            <button
              class="flex-1 py-2 text-[17px] text-blue-500 font-medium active:opacity-70 transition"
              @click="showDeleteModal = false"
            >
              取消
            </button>
            <div class="w-px bg-gray-200/50 dark:bg-white/10"></div>
            <button
              class="flex-1 py-2 text-[17px] text-red-500 font-medium active:opacity-70 transition"
              @click="handleDelete"
            >
              销户
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
