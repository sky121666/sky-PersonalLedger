<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Home, List, PieChart, User, Wallet, ChevronLeft, ChevronRight, Plus } from 'lucide-vue-next'
import TransactionDialog from '@/components/TransactionDialog.vue'

const showQuickAdd = ref(false)

const route = useRoute()
const router = useRouter()

// Updated tabs structure for "Chinese Style" app
// Order: Home (Dashboard) | Transactions (List) | [ADD] | Statistics (Chart) | Mine (Settings/Management)
const tabs = [
  { name: 'home', path: '/', label: '首页', icon: Home },
  { name: 'transactions', path: '/transactions', label: '明细', icon: List },
  // Middle button is handled separately in template
  { name: 'statistics', path: '/statistics', label: '统计', icon: PieChart },
  { name: 'settings', path: '/settings', label: '我的', icon: User }
]

// Routes that should highlight "我的" tab
const settingsChildRoutes = ['accounts', 'categories', 'budgets', 'reminders', 'lendings', 'report', 'family', 'ai']

const currentTab = computed(() => {
  const name = route.name as string
  // If on a child route of settings, highlight "我的"
  if (settingsChildRoutes.includes(name)) {
    return 'settings'
  }
  return name
})
const isMobile = ref(window.innerWidth < 768)
const sidebarCollapsed = ref(false)

function checkMobile() {
  isMobile.value = window.innerWidth < 768
  if (isMobile.value) sidebarCollapsed.value = true
}

function loadSidebarState() {
  const saved = localStorage.getItem('sidebar-collapsed')
  if (saved !== null && !isMobile.value) {
    sidebarCollapsed.value = saved === 'true'
  }
}

function saveSidebarState(collapsed: boolean) {
  localStorage.setItem('sidebar-collapsed', String(collapsed))
}

function toggleSidebar() {
  sidebarCollapsed.value = !sidebarCollapsed.value
  saveSidebarState(sidebarCollapsed.value)
}

onMounted(() => {
  loadSidebarState()
  window.addEventListener('resize', checkMobile)
})

onUnmounted(() => {
  window.removeEventListener('resize', checkMobile)
})

function switchTab(path: string) {
  router.push(path)
}
</script>

<template>
  <!-- Mobile Layout -->
  <div v-if="isMobile" class="h-full flex flex-col bg-[#F2F2F7] dark:bg-black">
    <div class="flex-1 overflow-auto scrollbar-hide pb-16">
      <router-view v-slot="{ Component }">
        <transition name="fade" mode="out-in">
          <component :is="Component" />
        </transition>
      </router-view>
    </div>

    <!-- iOS Dock Style Bottom Navigation -->
    <div class="fixed bottom-0 left-0 right-0 z-50">
      <!-- Glass Background -->
      <div class="absolute inset-0 bg-white/80 dark:bg-[#1C1C1E]/80 backdrop-blur-xl border-t border-gray-200/50 dark:border-white/10"></div>
      
      <div class="relative h-[56px] flex items-center justify-around px-2">
        <!-- Left Tabs -->
        <button
          v-for="tab in tabs.slice(0, 2)"
          :key="tab.name"
          class="flex-1 flex flex-col items-center justify-center gap-1 h-full active:scale-95 transition-transform"
          :class="currentTab === tab.name ? 'text-primary' : 'text-gray-400 dark:text-gray-500'"
          @click="switchTab(tab.path)"
        >
          <component 
            :is="tab.icon" 
            :size="26" 
            :stroke-width="currentTab === tab.name ? 2.5 : 2"
            class="transition-all duration-300"
          />
          <span class="text-[10px] font-medium">{{ tab.label }}</span>
        </button>

        <!-- Center Add Button (Floating Dock Style) -->
        <div class="relative -top-5">
          <button
            class="w-14 h-14 bg-gradient-to-b from-primary to-blue-600 rounded-full shadow-lg shadow-primary/30 flex items-center justify-center text-white active:scale-90 transition-transform"
            @click="showQuickAdd = true"
          >
            <Plus :size="30" stroke-width="3" />
          </button>
        </div>

        <!-- Right Tabs -->
        <button
          v-for="tab in tabs.slice(2)"
          :key="tab.name"
          class="flex-1 flex flex-col items-center justify-center gap-1 h-full active:scale-95 transition-transform"
          :class="currentTab === tab.name ? 'text-primary' : 'text-gray-400 dark:text-gray-500'"
          @click="switchTab(tab.path)"
        >
          <component 
            :is="tab.icon" 
            :size="26" 
            :stroke-width="currentTab === tab.name ? 2.5 : 2"
            class="transition-all duration-300"
          />
          <span class="text-[10px] font-medium">{{ tab.label }}</span>
        </button>
      </div>
    </div>

    <!-- Quick Add Dialog -->
    <TransactionDialog v-model:visible="showQuickAdd" @success="showQuickAdd = false" />
  </div>

  <!-- PC Layout -->
  <div v-else class="h-full flex bg-[#F2F2F7] dark:bg-black">
    <!-- Sidebar -->
    <aside
      class="h-full bg-white/60 dark:bg-[#1C1C1E]/60 backdrop-blur-xl border-r border-gray-200/50 dark:border-white/10 flex flex-col transition-all duration-500 ease-[cubic-bezier(0.32,0.72,0,1)] z-20"
      :class="sidebarCollapsed ? 'w-20' : 'w-64'"
    >
      <!-- Logo -->
      <div class="h-16 flex items-center px-6">
        <div class="w-8 h-8 bg-gradient-to-br from-primary to-blue-600 rounded-lg flex items-center justify-center text-white shadow-lg shadow-primary/20 flex-shrink-0">
          <Wallet :size="18" />
        </div>
        <span 
          class="ml-3 font-bold text-lg text-gray-900 dark:text-white overflow-hidden whitespace-nowrap transition-all duration-300"
          :class="sidebarCollapsed ? 'opacity-0 w-0' : 'opacity-100 w-auto'"
        >
          Personal Ledger
        </span>
      </div>

      <!-- Navigation -->
      <nav class="flex-1 px-3 py-4 space-y-1">
        <!-- Quick Add (Desktop) -->
        <button
          class="w-full flex items-center mb-6 transition-all duration-300 group"
          :class="sidebarCollapsed ? 'justify-center' : 'px-3'"
          @click="showQuickAdd = true"
        >
          <div class="w-10 h-10 bg-primary text-white rounded-xl flex items-center justify-center shadow-lg shadow-primary/20 group-hover:scale-105 transition-transform">
            <Plus :size="24" stroke-width="2.5" />
          </div>
          <span 
            class="ml-3 font-medium text-gray-900 dark:text-white overflow-hidden whitespace-nowrap transition-all duration-300"
            :class="sidebarCollapsed ? 'opacity-0 w-0' : 'opacity-100 w-auto'"
          >
            记一笔
          </span>
        </button>

        <button
          v-for="tab in tabs"
          :key="tab.name"
          class="w-full flex items-center rounded-xl transition-all duration-200 group relative"
          :class="[
            sidebarCollapsed ? 'justify-center py-3' : 'px-3 py-3',
            currentTab === tab.name
              ? 'bg-black/5 dark:bg-white/10 text-primary font-medium'
              : 'text-gray-500 dark:text-gray-400 hover:bg-black/5 dark:hover:bg-white/5 hover:text-gray-900 dark:hover:text-white'
          ]"
          @click="switchTab(tab.path)"
        >
          <component
            :is="tab.icon"
            :size="22"
            :stroke-width="currentTab === tab.name ? 2.5 : 2"
            class="flex-shrink-0 transition-transform duration-300"
          />
          <span 
            class="ml-3 overflow-hidden whitespace-nowrap transition-all duration-300"
            :class="sidebarCollapsed ? 'opacity-0 w-0' : 'opacity-100 w-auto'"
          >
            {{ tab.label }}
          </span>
          
          <!-- Tooltip for collapsed mode -->
          <div 
            v-if="sidebarCollapsed"
            class="absolute left-full ml-4 px-3 py-1.5 bg-gray-900 text-white text-xs rounded-lg opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all duration-200 whitespace-nowrap shadow-xl z-50 translate-x-2 group-hover:translate-x-0"
          >
            {{ tab.label }}
          </div>
        </button>
      </nav>

      <!-- Collapse Toggle -->
      <div class="p-4">
        <button
          class="w-full flex items-center justify-center p-2 text-gray-400 hover:bg-black/5 dark:hover:bg-white/5 rounded-lg transition-all"
          @click="toggleSidebar"
        >
          <component :is="sidebarCollapsed ? ChevronRight : ChevronLeft" :size="20" />
        </button>
      </div>
    </aside>

    <!-- Main Content -->
    <main class="flex-1 overflow-auto relative scrollbar-hide">
      <router-view v-slot="{ Component }">
        <transition name="fade" mode="out-in">
          <component :is="Component" />
        </transition>
      </router-view>
      
      <!-- Desktop Dialog -->
      <TransactionDialog v-model:visible="showQuickAdd" @success="showQuickAdd = false" />
    </main>
  </div>
</template>

<style scoped>
/* Safe area for iPhone X+ */
.safe-bottom {
  padding-bottom: max(20px, env(safe-area-inset-bottom));
}
</style>
