<script setup lang="ts">
import { computed } from 'vue'
import { Wallet, PanelLeft, Plus, Sun, Moon, User, Ellipsis } from '@lucide/vue'
import { getNavigationItem, type NavigationId } from './catalog'
import { navigationIcons } from './icons'

const props = defineProps<{
  pinned: NavigationId[]
  activeId: NavigationId | null
  mobile: boolean
  dark: boolean
  menuOpen: boolean
  canCustomize: boolean
}>()
const emit = defineEmits<{
  navigate: [id: NavigationId]
  more: [event: MouseEvent]
  mode: []
  quickAdd: []
  theme: []
}>()
// Bounded projection: every overflow destination remains in the shared directory.
const visibleItems = computed(() => props.pinned.filter(id => !['more', 'settings'].includes(id)).slice(0, 5).map(getNavigationItem))
</script>

<template>
  <header class="workspace-header" :class="{ 'is-mobile': mobile }">
    <div class="workspace-brand" aria-label="Personal Ledger">
      <span class="workspace-brand-icon"><Wallet :size="20" aria-hidden="true" /></span>
      <span v-if="!mobile" class="workspace-brand-name">Personal Ledger</span>
    </div>
    <nav v-if="!mobile" aria-label="主导航" data-projection="top" class="workspace-top-nav workspace-glass">
      <button
        v-for="item in visibleItems" :key="item.id" type="button" class="workspace-destination"
        :aria-current="activeId === item.id ? 'page' : undefined" @click="emit('navigate', item.id)"
      >
        <component :is="navigationIcons[item.id]" :size="18" aria-hidden="true" />
        <span>{{ item.label }}</span>
      </button>
      <button type="button" class="workspace-destination" aria-label="打开更多导航" :aria-expanded="menuOpen" aria-controls="workspace-functions" @click="emit('more', $event)">
        <Ellipsis :size="20" aria-hidden="true" /><span>更多</span>
      </button>
    </nav>
    <div class="workspace-utilities">
      <button v-if="!mobile" type="button" class="workspace-icon-button workspace-mode-toggle" :disabled="!canCustomize" aria-label="切换到侧栏导航" title="切换到侧栏导航" @click="emit('mode')">
        <PanelLeft :size="20" aria-hidden="true" />
      </button>
      <button type="button" class="workspace-icon-button" :aria-label="dark ? '切换到浅色模式' : '切换到深色模式'" @click="emit('theme')">
        <component :is="dark ? Sun : Moon" :size="20" aria-hidden="true" />
      </button>
      <button type="button" class="workspace-icon-button" aria-label="我的" title="设置" :aria-current="activeId === 'settings' ? 'page' : undefined" @click="emit('navigate', 'settings')">
        <User :size="20" aria-hidden="true" />
      </button>
      <button type="button" class="workspace-quick-add" aria-label="记一笔" @click="($event.currentTarget as HTMLElement).focus({ preventScroll: true }); emit('quickAdd')">
        <Plus :size="20" aria-hidden="true" /><span>记一笔</span>
      </button>
    </div>
  </header>
</template>
