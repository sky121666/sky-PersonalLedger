<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import TransactionDialog from '@/components/TransactionDialog.vue'
import WorkspaceHeader from '@/components/navigation/WorkspaceHeader.vue'
import PinnedRail from '@/components/navigation/PinnedRail.vue'
import MobileNavigation from '@/components/navigation/MobileNavigation.vue'
import FunctionMenu from '@/components/navigation/FunctionMenu.vue'
import { getActiveNavigationId, getNavigationItem, type NavigationId } from '@/components/navigation/catalog'
import { useAuthStore } from '@/stores/auth'
import { useThemeStore } from '@/stores/theme'
import { useWorkspacePreferencesStore } from '@/stores/workspacePreferences'
import { toast } from '@/composables/useToast'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const theme = useThemeStore()
const preferences = useWorkspacePreferencesStore()
const showQuickAdd = ref(false)
const content = ref<HTMLElement | null>(null)
const isMobile = ref(window.innerWidth < 768)
const menuOpen = ref(false)
const preferenceFailed = ref(false)
let menuTrigger: HTMLElement | null = null
let disposed = false
const activeId = computed(() => getActiveNavigationId(typeof route.name === 'string' ? route.name : null))
const canCustomize = computed(() => preferences.ready && !preferences.navigationIssue)
const preferenceMessage = computed(() => {
  if (preferences.navigationIssue === 'unsupported') return '导航偏好来自更高版本，原配置已保留，当前使用默认导航。'
  if (preferences.navigationIssue === 'invalid') return '导航偏好已损坏，当前使用默认导航。'
  return '导航偏好暂不可用，账本功能仍可使用。'
})

watch(() => route.path, () => {
  closeMenu(false)
  content.value?.scrollTo({ top: 0, left: 0, behavior: 'instant' })
}, { flush: 'post' })

async function loadPreferences() {
  const generation = auth.sessionGeneration
  preferenceFailed.value = false
  if (preferences.ready) {
    preferenceFailed.value = !preferences.reloadNavigation()
    return
  }
  try {
    preferences.attachStorage(localStorage)
    const loaded = await preferences.resolveOwner(generation)
    if (!disposed && auth.sessionGeneration === generation) preferenceFailed.value = !loaded || !!preferences.navigationIssue
  } catch {
    if (!disposed && auth.sessionGeneration === generation) preferenceFailed.value = true
  }
}

watch(() => auth.sessionGeneration, () => {
  preferences.invalidateOwner()
  closeMenu(false)
  showQuickAdd.value = false
  if (auth.isLoggedIn) void loadPreferences()
})

function checkMobile() {
  const mobile = window.innerWidth < 768
  if (mobile !== isMobile.value) closeMenu(false)
  isMobile.value = mobile
}

function handleStorage(event: StorageEvent) { preferences.handleStorage(event) }

function openMenu(event: MouseEvent) {
  if (menuOpen.value) return closeMenu()
  menuTrigger = event.currentTarget as HTMLElement
  menuOpen.value = true
}

function closeMenu(restoreFocus = true) {
  if (!menuOpen.value) return
  menuOpen.value = false
  if (restoreFocus) {
    void nextTick(() => {
      const trigger = menuTrigger?.isConnected ? menuTrigger : document.querySelector<HTMLElement>('[aria-controls="workspace-functions"]')
      trigger?.focus({ preventScroll: true })
    })
  }
}

function restoreNavigation() {
  preferenceFailed.value = !preferences.restoreNavigationDefaults()
  if (preferenceFailed.value) toast.error('默认导航恢复失败，原配置已保留，请重试')
}

function handleFocus(event: FocusEvent) {
  const target = event.target as HTMLElement | null
  if (menuOpen.value && target && !target.closest('.workspace-function-layer') && target !== menuTrigger) closeMenu(false)
  if (!isMobile.value || !target || !content.value?.contains(target)) return
  // WebKit can focus a tabindex ancestor when clicking a button. Scrolling that
  // whole region moves the button between pointerdown and pointerup.
  if (!target.matches('button, a[href], input, select, textarea, summary, [role="button"], [role="combobox"], [role="menuitem"], [role="tab"]')) return
  const nav = document.querySelector<HTMLElement>('.workspace-mobile-nav')
  if (!nav) return
  const bounds = target.getBoundingClientRect()
  const limit = nav.getBoundingClientRect().top - 12
  // Native focus scrolling knows the viewport, but not the floating navigation.
  if (bounds.bottom > limit) {
    content.value.scrollBy({ top: bounds.bottom - limit, behavior: 'instant' })
  }
}

function handleMenuKey(event: KeyboardEvent) {
  if (!menuOpen.value || event.key !== 'Escape') return
  event.preventDefault()
  closeMenu()
}

function navigate(id: NavigationId) {
  const item = getNavigationItem(id)
  closeMenu(false)
  if (item.path && route.path !== item.path) void router.push(item.path)
}

function pin(id: NavigationId) {
  if (!getNavigationItem(id).canUnpin) return
  try {
    const pinned = preferences.navigation.pinned
    preferences.setPinned(pinned.includes(id) ? pinned.filter(item => item !== id) : [...pinned, id])
  } catch {
    toast.error('导航偏好未保存，请重试加载；其他标签可能已更新')
    preferenceFailed.value = true
  }
}

async function changeMode() {
  const scrollTop = content.value?.scrollTop ?? 0
  try {
    preferences.setNavigationMode(preferences.navigation.mode === 'top' ? 'rail' : 'top')
    closeMenu(false)
    await nextTick()
    content.value?.scrollTo({ top: scrollTop, behavior: 'instant' })
    document.querySelector<HTMLButtonElement>('.workspace-mode-toggle')?.focus({ preventScroll: true })
  } catch {
    toast.error('导航偏好未保存，请重试加载；其他标签可能已更新')
    preferenceFailed.value = true
  }
}

onMounted(() => {
  void loadPreferences()
  window.addEventListener('resize', checkMobile)
  window.addEventListener('storage', handleStorage)
  document.addEventListener('focusin', handleFocus)
  document.addEventListener('keydown', handleMenuKey)
})
onUnmounted(() => {
  disposed = true
  window.removeEventListener('resize', checkMobile)
  window.removeEventListener('storage', handleStorage)
  document.removeEventListener('focusin', handleFocus)
  document.removeEventListener('keydown', handleMenuKey)
  preferences.invalidateOwner()
})
</script>

<template>
  <div class="ledger-workspace" :data-mode="isMobile ? 'mobile' : preferences.navigation.mode">
    <WorkspaceHeader
      v-if="isMobile || preferences.navigation.mode === 'top'"
      :mobile="isMobile" :pinned="preferences.navigation.pinned" :active-id="activeId" :dark="theme.isDark" :menu-open="menuOpen" :can-customize="canCustomize"
      @navigate="navigate" @more="openMenu" @mode="changeMode" @quick-add="showQuickAdd = true" @theme="theme.toggle()"
    />
    <div class="workspace-body">
      <PinnedRail
        v-if="!isMobile && preferences.navigation.mode === 'rail'"
        :pinned="preferences.navigation.pinned" :active-id="activeId" :dark="theme.isDark" :menu-open="menuOpen" :can-customize="canCustomize"
        @navigate="navigate" @more="openMenu" @mode="changeMode" @quick-add="showQuickAdd = true" @theme="theme.toggle()"
      />
      <main ref="content" class="workspace-content scrollbar-hide" :class="{ 'mobile-content-safe': isMobile }">
        <div v-if="preferenceFailed" role="status" class="workspace-preference-notice">
          {{ preferenceMessage }}<button type="button" @click="loadPreferences">重试加载偏好</button>
          <button v-if="preferences.navigationIssue === 'invalid'" type="button" @click="restoreNavigation">恢复默认导航</button>
        </div>
        <router-view v-slot="{ Component }">
          <component :is="Component" :key="route.path" />
        </router-view>
      </main>
    </div>
    <MobileNavigation
      v-if="isMobile" :pinned="preferences.navigation.pinned" :active-id="activeId" :menu-open="menuOpen"
      @navigate="navigate" @more="openMenu"
    />
    <FunctionMenu
      v-if="menuOpen" :pinned="preferences.navigation.pinned" :active-id="activeId" :can-customize="canCustomize"
      @navigate="navigate" @pin="pin" @close="closeMenu()"
    />
    <TransactionDialog v-model:visible="showQuickAdd" @success="showQuickAdd = false" />
  </div>
</template>
